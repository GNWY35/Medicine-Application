package com.example.untitled1

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.hardware.camera2.*
import android.hardware.camera2.params.MeteringRectangle
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** คุณภาพของภาพเฉพาะในกรอบตรวจจับ (ROI) ส่งกลับ Flutter */
data class FrameQuality(
    val sharpness: Double,
    val isSharp: Boolean,
    val edgePixels: Int,
    val density: Double, // edgePixels / analysed pixels, 0..1
    val tooDark: Boolean,
)

class CameraHandler(private val activity: Activity) {
    companion object {
        // กรอบตรวจจับใน realtime_detection_page.dart (FractionallySizedBox) เป็นสัดส่วนของ
        // preview แนวตั้ง ต้องตรงกันทั้งสองฝั่ง
        const val ROI_WIDTH_FRACTION = 0.65f
        const val ROI_HEIGHT_FRACTION = 0.40f

        // เกณฑ์ตัดสินว่าภาพ "ชัดพอ" — ปรับได้ตามการทดสอบจริง
        private const val SHARP_THRESHOLD = 80.0
        // |Laplacian| ตั้งแต่ค่านี้นับเป็นพิกเซลขอบ (ใช้คำนวณ density)
        private const val EDGE_THRESHOLD = 30
        // ภาพมืดกว่านี้ Laplacian variance มาจาก noise ของเซนเซอร์ ไม่ใช่ความคม
        private const val MIN_LUMA = 40.0
        // ต้องชัดติดกันกี่เฟรมจึงถือว่าชัด กันเฟรมเดียวที่ noise สูงเปิดปุ่มถ่าย
        private const val SHARP_FRAMES_REQUIRED = 2
        // กันวิเคราะห์ถี่เกินไป — เว้นช่วงอย่างน้อย 120ms ต่อเฟรม
        private const val ANALYZE_INTERVAL_MS = 120L
        // หลังแตะโฟกัส ล็อกจุดนั้นไว้กี่ ms ก่อนกลับไปโฟกัสต่อเนื่องที่กลางกรอบ
        private const val TAP_FOCUS_HOLD_MS = 5000L
        // รอ AF ล็อกก่อนถ่ายนานสุดเท่านี้ แล้วถ่ายเลย (กันค้างบนเครื่องที่ AF ช้า)
        private const val FOCUS_LOCK_TIMEOUT_MS = 1500L
        // จำกัดขนาด JPEG กัน OutOfMemoryError ตอนหมุนภาพบนเครื่อง RAM น้อย
        private const val MAX_JPEG_LONG_EDGE = 2560
        private const val JPEG_QUALITY = 95
        /** ขอบเผื่อรอบกรอบตรวจจับต่อด้าน (สัดส่วนของกรอบ) กันยาที่ชิดขอบกรอบถูกตัด */
        private const val CROP_MARGIN = 0.12f
    }

    private var cameraDevice: CameraDevice? = null
    private var cameraCaptureSessions: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var analysisReader: ImageReader? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private val cameraManager by lazy { activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager }
    private var currentCameraId: String? = null
    private var previewSurface: Surface? = null
    private var previewSize: Size = Size(1280, 720)

    // คุณสมบัติกล้อง อ่านครั้งเดียวตอนเปิด
    private var activeArray: Rect? = null
    private var sensorOrientation = 90
    private var isFrontFacing = false
    private var afSupported = false
    private var continuousAfSupported = false
    private var maxAfRegions = 0
    private var maxAeRegions = 0

    // สถานะ 3A ใช้บน backgroundHandler เท่านั้น
    private var afMode = CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
    private var meteringRegions: Array<MeteringRectangle>? = null
    @Volatile private var afState = CaptureResult.CONTROL_AF_STATE_INACTIVE
    private var afStateListener: ((Int) -> Unit)? = null
    private var capturing = false
    private var pendingCaptureCallback: ((Boolean, String?) -> Unit)? = null

    private val resetFocusRunnable = Runnable { if (!capturing) resetToDefaultFocus() }

    private val previewCallback = object : CameraCaptureSession.CaptureCallback() {
        override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
            val state = result.get(CaptureResult.CONTROL_AF_STATE) ?: return
            afState = state
            afStateListener?.invoke(state)
        }
    }

    // callback ส่งคุณภาพภาพกลับ Flutter (ตั้งจาก MainActivity)
    var onSharpness: ((FrameQuality) -> Unit)? = null

    private var lastAnalyzeTime = 0L
    private var sharpStreak = 0
    private var roiBuffer = ByteArray(0)

    fun startBackgroundThread() {
        if (backgroundThread != null) return
        backgroundThread = HandlerThread("CameraBackground").apply { start() }
        backgroundHandler = Handler(backgroundThread!!.looper)
    }

    fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        } finally {
            backgroundThread = null
            backgroundHandler = null
        }
    }

    private fun selectCameraId(): String? {
        return currentCameraId ?: run {
            cameraManager.cameraIdList.firstOrNull { id ->
                val characteristics = cameraManager.getCameraCharacteristics(id)
                val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                val hasFlash = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false
                facing == CameraCharacteristics.LENS_FACING_BACK && hasFlash
            } ?: cameraManager.cameraIdList.firstOrNull { id ->
                val characteristics = cameraManager.getCameraCharacteristics(id)
                val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                facing == CameraCharacteristics.LENS_FACING_BACK
            } ?: cameraManager.cameraIdList.firstOrNull()
        }
    }

    private fun readCharacteristics(c: CameraCharacteristics) {
        activeArray = c.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
        sensorOrientation = c.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
        isFrontFacing = c.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
        val afModes = c.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES) ?: IntArray(0)
        val minFocusDistance = c.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f
        // minFocusDistance == 0 คือเลนส์ fixed-focus: ไม่มี AF ให้สั่ง
        afSupported = minFocusDistance > 0f && afModes.contains(CaptureRequest.CONTROL_AF_MODE_AUTO)
        continuousAfSupported = minFocusDistance > 0f &&
            afModes.contains(CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
        maxAfRegions = c.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AF) ?: 0
        maxAeRegions = c.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AE) ?: 0
    }

    private fun defaultAfMode(): Int = when {
        continuousAfSupported -> CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
        afSupported -> CaptureRequest.CONTROL_AF_MODE_AUTO
        else -> CaptureRequest.CONTROL_AF_MODE_OFF
    }

    /** JPEG ขนาดใหญ่สุดที่สัดส่วนเท่า preview (ภาพที่ส่ง API = สิ่งที่เห็นบนจอ) และไม่เกิน MAX_JPEG_LONG_EDGE */
    private fun chooseJpegSize(map: StreamConfigurationMap?): Size {
        val sizes = map?.getOutputSizes(ImageFormat.JPEG)?.toList().orEmpty()
        if (sizes.isEmpty()) return Size(1920, 1080)
        val aspect = previewSize.width.toFloat() / previewSize.height
        val capped = sizes.filter { max(it.width, it.height) <= MAX_JPEG_LONG_EDGE }
        return capped.filter { abs(it.width.toFloat() / it.height - aspect) < 0.02f }.maxByOrNull { it.width * it.height }
            ?: capped.maxByOrNull { it.width * it.height }
            ?: sizes.minByOrNull { it.width * it.height }!!
    }

    /** YUV เล็ก ๆ สัดส่วนเท่า preview เพื่อให้ ROI ในเฟรมวิเคราะห์ตรงกับกรอบบนจอ */
    private fun chooseAnalysisSize(map: StreamConfigurationMap?): Size {
        val aspect = previewSize.width.toFloat() / previewSize.height
        return map?.getOutputSizes(ImageFormat.YUV_420_888)
            ?.filter { it.width in 480..960 && abs(it.width.toFloat() / it.height - aspect) < 0.02f }
            ?.minByOrNull { it.width * it.height }
            ?: Size(640, 480)
    }

    // ---------------------------------------------------------------------
    // พิกัด: preview บนจอ (แนวตั้ง, normalized 0..1) -> active array ของเซนเซอร์
    // ---------------------------------------------------------------------

    /** ส่วนของ active array ที่ preview stream เห็นจริง (crop กลางตามสัดส่วน stream) พิกัดเริ่มที่ 0 */
    private fun visibleCrop(array: Rect): Rect {
        val aw = array.width()
        val ah = array.height()
        val streamAspect = previewSize.width.toFloat() / previewSize.height
        return if (aw.toFloat() / ah > streamAspect) {
            val w = (ah * streamAspect).toInt()
            val l = (aw - w) / 2
            Rect(l, 0, l + w, ah)
        } else {
            val h = (aw / streamAspect).toInt()
            val t = (ah - h) / 2
            Rect(0, t, aw, t + h)
        }
    }

    /**
     * จุดบน preview ที่แสดงตั้งตรง (แนวตั้ง) -> จุดใน active array
     * กล้องหมุนภาพตาม SENSOR_ORIENTATION ก่อนแสดง จึงต้องหมุนกลับ และกล้องหน้าแสดงแบบกระจก
     * สมมติว่าเครื่องอยู่แนวตั้งปกติ
     */
    private fun previewToSensor(vx: Float, vy: Float): Pair<Float, Float>? {
        val array = activeArray ?: return null
        val x = if (isFrontFacing) 1f - vx else vx
        val (sx, sy) = when (sensorOrientation) {
            90 -> vy to 1f - x
            180 -> 1f - x to 1f - vy
            270 -> 1f - vy to x
            else -> x to vy
        }
        val crop = visibleCrop(array)
        return (crop.left + sx * crop.width()) to (crop.top + sy * crop.height())
    }

    /** พื้นที่วัดแสง/โฟกัสเริ่มต้น = กรอบตรวจจับกลางจอ */
    private fun centerRegions(): Array<MeteringRectangle>? {
        val array = activeArray ?: return null
        val a = previewToSensor(0.5f - ROI_WIDTH_FRACTION / 2, 0.5f - ROI_HEIGHT_FRACTION / 2) ?: return null
        val b = previewToSensor(0.5f + ROI_WIDTH_FRACTION / 2, 0.5f + ROI_HEIGHT_FRACTION / 2) ?: return null
        val crop = visibleCrop(array)
        val rect = Rect(
            min(a.first, b.first).toInt().coerceAtLeast(crop.left),
            min(a.second, b.second).toInt().coerceAtLeast(crop.top),
            max(a.first, b.first).toInt().coerceAtMost(crop.right - 1),
            max(a.second, b.second).toInt().coerceAtMost(crop.bottom - 1),
        )
        if (rect.width() <= 0 || rect.height() <= 0) return null
        return arrayOf(MeteringRectangle(rect, MeteringRectangle.METERING_WEIGHT_MAX))
    }

    /** สี่เหลี่ยมรอบจุดที่แตะ ถ้าชิดขอบจะเลื่อนเข้าในโดยคงขนาดไว้ */
    private fun tapRegion(normX: Float, normY: Float): MeteringRectangle? {
        val array = activeArray ?: return null
        val (cx, cy) = previewToSensor(normX.coerceIn(0f, 1f), normY.coerceIn(0f, 1f)) ?: return null
        val crop = visibleCrop(array)
        val size = (max(crop.width(), crop.height()) * 0.08f).toInt()
            .coerceIn(1, min(crop.width(), crop.height()) - 1)
        val left = (cx.toInt() - size / 2).coerceIn(crop.left, crop.right - 1 - size)
        val top = (cy.toInt() - size / 2).coerceIn(crop.top, crop.bottom - 1 - size)
        return MeteringRectangle(left, top, size, size, MeteringRectangle.METERING_WEIGHT_MAX)
    }

    // ---------------------------------------------------------------------
    // Requests
    // ---------------------------------------------------------------------

    private fun apply3A(builder: CaptureRequest.Builder) {
        builder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
        builder.set(CaptureRequest.CONTROL_AF_MODE, afMode)
        builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
        val regions = meteringRegions
        if (regions != null) {
            if (afSupported && maxAfRegions > 0) builder.set(CaptureRequest.CONTROL_AF_REGIONS, regions)
            if (maxAeRegions > 0) builder.set(CaptureRequest.CONTROL_AE_REGIONS, regions)
        }
        builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
    }

    private fun buildPreviewRequest(camera: CameraDevice, surface: Surface, afTrigger: Int? = null): CaptureRequest {
        val builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
        builder.addTarget(surface)
        analysisReader?.surface?.let { builder.addTarget(it) }
        apply3A(builder)
        if (afTrigger != null) builder.set(CaptureRequest.CONTROL_AF_TRIGGER, afTrigger)
        return builder.build()
    }

    /** กลับไปโฟกัสต่อเนื่องที่กรอบกลางจอ และปลดล็อก AF ที่ค้างจากการแตะหรือการถ่าย */
    private fun resetToDefaultFocus() {
        val cam = cameraDevice ?: return
        val session = cameraCaptureSessions ?: return
        val surface = previewSurface ?: return
        try {
            afMode = defaultAfMode()
            meteringRegions = centerRegions()
            if (afSupported) {
                session.capture(buildPreviewRequest(cam, surface, CaptureRequest.CONTROL_AF_TRIGGER_CANCEL), previewCallback, backgroundHandler)
            }
            session.setRepeatingRequest(buildPreviewRequest(cam, surface), previewCallback, backgroundHandler)
        } catch (_: Exception) {
            // session ถูกปิดไปแล้ว
        }
    }

    /**
     * วิเคราะห์ความคมชัดจาก preview frame (YUV_420_888)
     * ใช้แค่ Y plane (ความสว่าง) คำนวณ Laplacian variance เฉพาะในกรอบตรวจจับ
     * พื้นหลังนอกกรอบไม่ทำให้ "ชัด" หลอก ๆ อีกต่อไป
     */
    private fun analyzeFrame(image: Image) {
        try {
            val now = System.currentTimeMillis()
            if (now - lastAnalyzeTime < ANALYZE_INTERVAL_MS) return
            lastAnalyzeTime = now

            val w = image.width
            val h = image.height
            // เฟรมวิเคราะห์อยู่ในแนวเซนเซอร์ ส่วนกรอบบนจอเป็นแนวตั้ง: หมุน 90/270 ต้องสลับแกน
            val swap = sensorOrientation % 180 != 0
            val roiW = (w * (if (swap) ROI_HEIGHT_FRACTION else ROI_WIDTH_FRACTION)).toInt()
            val roiH = (h * (if (swap) ROI_WIDTH_FRACTION else ROI_HEIGHT_FRACTION)).toInt()
            if (roiW < 3 || roiH < 3) return
            val x0 = (w - roiW) / 2
            val y0 = (h - roiH) / 2

            // Y plane มี pixelStride = 1 เสมอ อ่านทีละแถวเฉพาะช่วง ROI ลง buffer ที่ใช้ซ้ำ
            val yPlane = image.planes[0]
            val yBuffer = yPlane.buffer
            val rowStride = yPlane.rowStride
            if (roiBuffer.size < roiW * roiH) roiBuffer = ByteArray(roiW * roiH)
            val roi = roiBuffer
            for (row in 0 until roiH) {
                yBuffer.position((y0 + row) * rowStride + x0)
                yBuffer.get(roi, row * roiW, roiW)
            }

            // Laplacian kernel 3x3 → variance, step 2 ข้ามพิกเซลเพื่อความเร็ว
            var sum = 0L
            var sumSq = 0L
            var lumaSum = 0L
            var count = 0
            var edgePixels = 0
            val step = 2
            for (y in 1 until roiH - 1 step step) {
                val rowBase = y * roiW
                for (x in 1 until roiW - 1 step step) {
                    val idx = rowBase + x
                    val center = roi[idx].toInt() and 0xFF
                    val lap = (roi[idx - roiW].toInt() and 0xFF) + (roi[idx + roiW].toInt() and 0xFF) +
                        (roi[idx - 1].toInt() and 0xFF) + (roi[idx + 1].toInt() and 0xFF) - 4 * center
                    sum += lap
                    sumSq += lap.toLong() * lap
                    lumaSum += center
                    count++
                    if (abs(lap) >= EDGE_THRESHOLD) edgePixels++
                }
            }

            if (count == 0) return
            val mean = sum.toDouble() / count
            val variance = sumSq.toDouble() / count - mean * mean
            val tooDark = lumaSum.toDouble() / count < MIN_LUMA
            // เลนส์กำลังเลื่อนหาโฟกัส ภาพที่ถ่ายตอนนี้จะเบลอ
            val afBusy = afState == CaptureResult.CONTROL_AF_STATE_PASSIVE_SCAN ||
                afState == CaptureResult.CONTROL_AF_STATE_ACTIVE_SCAN
            sharpStreak = if (variance >= SHARP_THRESHOLD && !tooDark && !afBusy) sharpStreak + 1 else 0

            val quality = FrameQuality(
                sharpness = variance,
                isSharp = sharpStreak >= SHARP_FRAMES_REQUIRED,
                edgePixels = edgePixels,
                density = edgePixels.toDouble() / count,
                tooDark = tooDark,
            )
            activity.runOnUiThread {
                onSharpness?.invoke(quality)
            }
        } catch (e: Exception) {
            // วิเคราะห์ frame ล้มเหลว ข้ามไป ไม่ทำให้กล้องค้าง
        }
    }

    private fun setupPreviewSession(camera: CameraDevice, surface: Surface, resultCallback: (Boolean, String?) -> Unit) {
        try {
            val analysisSurf = analysisReader?.surface
            // JPEG reader อยู่ใน session เดียวกับ preview: ถ่ายได้ทันทีโดยใช้ AF/AE ที่ปรับไว้แล้ว
            val targets = mutableListOf(surface, imageReader!!.surface)
            if (analysisSurf != null) targets.add(analysisSurf)

            camera.createCaptureSession(targets, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    cameraCaptureSessions = session
                    try {
                        afMode = defaultAfMode()
                        meteringRegions = centerRegions()
                        session.setRepeatingRequest(buildPreviewRequest(camera, surface), previewCallback, backgroundHandler)
                        resultCallback(true, null)
                    } catch (e: CameraAccessException) {
                        resultCallback(false, e.message)
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    resultCallback(false, "Session configure failed")
                }
            }, backgroundHandler)
        } catch (e: CameraAccessException) {
            resultCallback(false, e.message)
        }
    }

    fun openCameraWithPreview(previewSurface: Surface, previewSize: Size, resultCallback: (Boolean, String?) -> Unit) {
        startBackgroundThread()
        try {
            val cameraId = selectCameraId()

            if (cameraId == null) {
                resultCallback(false, "No camera available")
                return
            }

            currentCameraId = cameraId
            this.previewSize = previewSize

            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            readCharacteristics(characteristics)
            val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val chosen = chooseJpegSize(map)

            imageReader = ImageReader.newInstance(chosen.width, chosen.height, ImageFormat.JPEG, 2)

            // ImageReader ตัวที่ 2 — สำหรับวิเคราะห์ความคมชัด (ขนาดเล็กเพื่อความเร็ว)
            val analysisSize = chooseAnalysisSize(map)
            analysisReader = ImageReader.newInstance(analysisSize.width, analysisSize.height, ImageFormat.YUV_420_888, 2)
            analysisReader!!.setOnImageAvailableListener({ reader ->
                val img = reader.acquireLatestImage()
                if (img != null) {
                    try {
                        analyzeFrame(img)
                    } finally {
                        img.close()
                    }
                }
            }, backgroundHandler)

            this.previewSurface = previewSurface

            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    setupPreviewSession(camera, previewSurface, resultCallback)
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    cameraDevice = null
                    resultCallback(false, "Camera disconnected")
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    cameraDevice = null
                    resultCallback(false, "Camera error: $error")
                }
            }, backgroundHandler)

        } catch (e: SecurityException) {
            resultCallback(false, "Permission denied: ${e.message}")
        } catch (e: Exception) {
            resultCallback(false, e.message)
        }
    }

    fun takePicture(resultCallback: (Boolean, String?) -> Unit) {
        val handler = backgroundHandler
        if (handler == null) {
            resultCallback(false, "Camera not opened")
            return
        }
        handler.post {
            val camera = cameraDevice
            val session = cameraCaptureSessions
            val reader = imageReader
            val surface = previewSurface
            if (camera == null || session == null || reader == null || surface == null) {
                resultCallback(false, "Camera not opened")
                return@post
            }
            if (capturing) {
                resultCallback(false, "Capture already in progress")
                return@post
            }
            capturing = true
            pendingCaptureCallback = resultCallback
            handler.removeCallbacks(resetFocusRunnable)
            reader.setOnImageAvailableListener({ r -> saveJpeg(r) }, handler)
            lockFocusThenCapture(camera, session, surface, reader, handler)
        }
    }

    /** ล็อก AF ก่อนถ่าย (ถ้ามี AF) เพื่อไม่ให้ถ่ายตอนเลนส์ยังเลื่อน มี timeout กันค้าง */
    private fun lockFocusThenCapture(
        camera: CameraDevice,
        session: CameraCaptureSession,
        surface: Surface,
        reader: ImageReader,
        handler: Handler,
    ) {
        if (!afSupported) {
            captureStill(camera, session, reader)
            return
        }
        val locked = afState == CaptureResult.CONTROL_AF_STATE_FOCUSED_LOCKED ||
            afState == CaptureResult.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED
        if (afMode == CaptureRequest.CONTROL_AF_MODE_AUTO && locked) {
            // แตะโฟกัสไว้แล้วและล็อกแล้ว ถ่ายได้เลย
            captureStill(camera, session, reader)
            return
        }

        var done = false
        var timeout: Runnable? = null
        fun proceed() {
            if (done) return
            done = true
            afStateListener = null
            timeout?.let { handler.removeCallbacks(it) }
            captureStill(camera, session, reader)
        }
        timeout = Runnable { proceed() }
        afStateListener = { state ->
            if (state == CaptureResult.CONTROL_AF_STATE_FOCUSED_LOCKED ||
                state == CaptureResult.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED
            ) proceed()
        }
        handler.postDelayed(timeout, FOCUS_LOCK_TIMEOUT_MS)

        // AUTO ที่กำลังสแกนจากการแตะอยู่แล้ว: รอผลเฉย ๆ ไม่ต้อง trigger ซ้ำ
        val scanning = afMode == CaptureRequest.CONTROL_AF_MODE_AUTO &&
            afState == CaptureResult.CONTROL_AF_STATE_ACTIVE_SCAN
        if (!scanning) {
            try {
                session.capture(
                    buildPreviewRequest(camera, surface, CaptureRequest.CONTROL_AF_TRIGGER_START),
                    previewCallback,
                    handler,
                )
            } catch (_: Exception) {
                proceed()
            }
        }
    }

    private fun captureStill(camera: CameraDevice, session: CameraCaptureSession, reader: ImageReader) {
        try {
            val builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
            builder.addTarget(reader.surface)
            apply3A(builder)
            builder.set(CaptureRequest.JPEG_QUALITY, JPEG_QUALITY.toByte())

            session.capture(builder.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
                    resetToDefaultFocus()
                }

                override fun onCaptureFailed(session: CameraCaptureSession, request: CaptureRequest, failure: CaptureFailure) {
                    resetToDefaultFocus()
                    finishCapture(false, "Capture failed: ${failure.reason}")
                }
            }, backgroundHandler)
        } catch (e: Exception) {
            resetToDefaultFocus()
            finishCapture(false, e.message)
        }
    }

    private fun finishCapture(ok: Boolean, value: String?) {
        capturing = false
        val callback = pendingCaptureCallback ?: return
        pendingCaptureCallback = null
        callback(ok, value)
    }

    /** หมุนภาพให้ตั้งตรงตาม SENSOR_ORIENTATION (เครื่องแนวตั้ง) แล้วบันทึก */
    private fun saveJpeg(reader: ImageReader) {
        val image = reader.acquireLatestImage() ?: return
        try {
            val buffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            image.close()

            val time = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val file = File(activity.cacheDir, "IMG_$time.jpg")
            val output = cropToFrameJpeg(bytes, sensorOrientation)
                ?: rotateJpeg(bytes, sensorOrientation)
                ?: bytes
            FileOutputStream(file).use { it.write(output) }
            finishCapture(true, file.absolutePath)
        } catch (e: Exception) {
            finishCapture(false, e.message)
        } finally {
            try { image.close() } catch (_: Exception) {}
        }
    }

    /**
     * ตัดเฉพาะกรอบตรวจจับ (ROI + ขอบเผื่อ CROP_MARGIN) แล้วหมุนให้ตั้งตรง เพื่อให้ API เห็นเฉพาะยาในกรอบ
     * กรอบอยู่กึ่งกลางและสมมาตร จึงคำนวณในพิกัด JPEG ก่อนหมุนได้โดยสลับแกนเมื่อหมุน 90/270 (ไม่ขึ้นกับ mirror)
     * ถอดรหัสเฉพาะส่วนที่ตัดด้วย BitmapRegionDecoder เพื่อประหยัดหน่วยความจำ คืน null ถ้าล้มเหลว
     */
    private fun cropToFrameJpeg(bytes: ByteArray, degrees: Int): ByteArray? {
        var region: Bitmap? = null
        var rotated: Bitmap? = null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            val w = bounds.outWidth
            val h = bounds.outHeight
            if (w <= 0 || h <= 0) return null

            val swap = degrees % 180 != 0
            val fx = min(1f, (if (swap) ROI_HEIGHT_FRACTION else ROI_WIDTH_FRACTION) * (1 + 2 * CROP_MARGIN))
            val fy = min(1f, (if (swap) ROI_WIDTH_FRACTION else ROI_HEIGHT_FRACTION) * (1 + 2 * CROP_MARGIN))
            val cw = (w * fx).toInt()
            val ch = (h * fy).toInt()
            val left = (w - cw) / 2
            val top = (h - ch) / 2
            val rect = Rect(left, top, left + cw, top + ch)

            @Suppress("DEPRECATION")
            val decoder = android.graphics.BitmapRegionDecoder.newInstance(bytes, 0, bytes.size, false)
                ?: return null
            region = try {
                decoder.decodeRegion(rect, null)
            } finally {
                decoder.recycle()
            } ?: return null

            val src = region
            rotated = if (degrees % 360 == 0) src else {
                val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
                Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
            }
            ByteArrayOutputStream(cw * ch / 4).use { out ->
                rotated.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
                out.toByteArray()
            }
        } catch (t: Throwable) {
            null
        } finally {
            if (rotated != null && rotated !== region) rotated.recycle()
            region?.recycle()
        }
    }

    /** คืน null ถ้าไม่ต้องหมุนหรือหมุนไม่สำเร็จ (เช่น OutOfMemoryError) ให้ใช้ไบต์เดิม */
    private fun rotateJpeg(bytes: ByteArray, degrees: Int): ByteArray? {
        if (degrees % 360 == 0) return null
        var bmp: Bitmap? = null
        var rotated: Bitmap? = null
        return try {
            bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
            val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
            rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
            ByteArrayOutputStream(bytes.size).use { out ->
                rotated.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
                out.toByteArray()
            }
        } catch (t: Throwable) {
            null
        } finally {
            if (rotated != null && rotated !== bmp) rotated.recycle()
            bmp?.recycle()
        }
    }

    fun closeCamera() {
        backgroundHandler?.removeCallbacks(resetFocusRunnable)
        afStateListener = null
        try {
            cameraCaptureSessions?.close()
            cameraCaptureSessions = null
            cameraDevice?.close()
            cameraDevice = null
            imageReader?.close()
            imageReader = null
            analysisReader?.close()
            analysisReader = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
        onSharpness = null
        stopBackgroundThread()
        capturing = false
        pendingCaptureCallback = null
        sharpStreak = 0
    }

    /**
     * แตะเพื่อโฟกัส: normX/normY คือจุดบน preview ที่แสดงตั้งตรง (0..1) หลังหัก crop ของ BoxFit แล้ว
     * ลำดับ: CANCEL -> AF_MODE_AUTO + regions -> TRIGGER_START แล้วค้างไว้ TAP_FOCUS_HOLD_MS
     * ก่อนกลับไป CONTINUOUS_PICTURE
     */
    fun focusAt(normX: Float, normY: Float, resultCallback: (Boolean, String?) -> Unit) {
        val handler = backgroundHandler
        if (handler == null) {
            resultCallback(false, "Camera not ready")
            return
        }
        handler.post {
            val cam = cameraDevice
            val session = cameraCaptureSessions
            val surface = previewSurface
            if (cam == null || session == null || surface == null) {
                resultCallback(false, "Camera not ready")
                return@post
            }
            // ระหว่างถ่าย AF ถูกล็อกไว้ ไม่รบกวน
            if (capturing) {
                resultCallback(true, null)
                return@post
            }
            val region = tapRegion(normX, normY)
            val canMeter = (afSupported && maxAfRegions > 0) || maxAeRegions > 0
            if (region == null || !canMeter) {
                // เครื่อง fixed-focus หรือไม่รองรับ metering region: ไม่มีอะไรให้ปรับ
                resultCallback(true, null)
                return@post
            }

            try {
                handler.removeCallbacks(resetFocusRunnable)
                if (afSupported) {
                    // ยกเลิกการสแกนเดิมก่อนเปลี่ยนโหมด
                    session.capture(buildPreviewRequest(cam, surface, CaptureRequest.CONTROL_AF_TRIGGER_CANCEL), previewCallback, handler)
                    afMode = CaptureRequest.CONTROL_AF_MODE_AUTO
                }
                meteringRegions = arrayOf(region)
                session.setRepeatingRequest(buildPreviewRequest(cam, surface), previewCallback, handler)
                if (afSupported) {
                    session.capture(buildPreviewRequest(cam, surface, CaptureRequest.CONTROL_AF_TRIGGER_START), previewCallback, handler)
                }
                handler.postDelayed(resetFocusRunnable, TAP_FOCUS_HOLD_MS)
                resultCallback(true, null)
            } catch (e: Exception) {
                resultCallback(false, e.message)
            }
        }
    }
}
