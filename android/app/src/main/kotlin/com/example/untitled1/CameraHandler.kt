package com.example.untitled1

import android.app.Activity
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import android.hardware.camera2.params.MeteringRectangle
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.abs

class CameraHandler(private val activity: Activity) {
    private var cameraDevice: CameraDevice? = null
    private var cameraCaptureSessions: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var analysisReader: ImageReader? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private val cameraManager by lazy { activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager }
    private var currentCameraId: String? = null
    private var torchEnabled: Boolean = false
    private var previewSurface: Surface? = null

    // callback ส่งค่าความคมชัดกลับ Flutter (ตั้งจาก MainActivity)
    var onSharpness: ((Double, Boolean) -> Unit)? = null

    // เกณฑ์ตัดสินว่าภาพ "ชัดพอ" — ปรับได้ตามการทดสอบจริง
    private val sharpThreshold = 80.0

    // กันวิเคราะห์ถี่เกินไป — เว้นช่วงอย่างน้อย 120ms ต่อเฟรม
    private var lastAnalyzeTime = 0L
    private val analyzeIntervalMs = 120L

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

    private fun setFlashMode(builder: CaptureRequest.Builder, enabled: Boolean) {
        if (enabled) {
            builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
            builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH)
        } else {
            builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
        }
    }

    /**
     * วิเคราะห์ความคมชัดจาก preview frame (YUV_420_888)
     * ใช้แค่ Y plane (ความสว่าง) คำนวณ Laplacian variance
     */
    private fun analyzeFrame(image: Image) {
        try {
            val now = System.currentTimeMillis()
            if (now - lastAnalyzeTime < analyzeIntervalMs) return
            lastAnalyzeTime = now

            val w = image.width
            val h = image.height
            val yPlane = image.planes[0]
            val yBuffer = yPlane.buffer
            val rowStride = yPlane.rowStride

            // ดึงค่า luminance ลงอาเรย์ (เฉพาะ Y plane)
            val gray = IntArray(w * h)
            val rowData = ByteArray(rowStride)
            for (row in 0 until h) {
                yBuffer.position(row * rowStride)
                val readLen = minOf(rowStride, yBuffer.remaining())
                yBuffer.get(rowData, 0, readLen)
                for (col in 0 until w) {
                    gray[row * w + col] = rowData[col].toInt() and 0xFF
                }
            }

            // Laplacian kernel 3x3 → variance
            var sum = 0.0
            var sumSq = 0.0
            var count = 0
            // step 2 — ข้ามพิกเซลเพื่อความเร็ว
            val step = 2
            for (y in 1 until h - 1 step step) {
                for (x in 1 until w - 1 step step) {
                    val idx = y * w + x
                    val lap = (gray[idx - w] + gray[idx + w] +
                            gray[idx - 1] + gray[idx + 1] -
                            4 * gray[idx]).toDouble()
                    sum += lap
                    sumSq += lap * lap
                    count++
                }
            }

            if (count == 0) return
            val mean = sum / count
            val variance = (sumSq / count) - (mean * mean)
            val isSharp = variance >= sharpThreshold

            activity.runOnUiThread {
                onSharpness?.invoke(variance, isSharp)
            }
        } catch (e: Exception) {
            // วิเคราะห์ frame ล้มเหลว ข้ามไป ไม่ทำให้กล้องค้าง
        }
    }

    private fun setupPreviewSession(camera: CameraDevice, surface: Surface, resultCallback: (Boolean, String?) -> Unit) {
        try {
            val analysisSurf = analysisReader?.surface
            val targets = mutableListOf(surface, imageReader!!.surface)
            if (analysisSurf != null) targets.add(analysisSurf)

            camera.createCaptureSession(targets, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    cameraCaptureSessions = session
                    try {
                        val previewRequestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                        previewRequestBuilder.addTarget(surface)
                        if (analysisSurf != null) previewRequestBuilder.addTarget(analysisSurf)
                        previewRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                        session.setRepeatingRequest(previewRequestBuilder.build(), null, backgroundHandler)
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

            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val outputSizes = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(ImageFormat.JPEG) ?: arrayOf(Size(1920, 1080))
            val chosen = outputSizes.firstOrNull() ?: Size(1920, 1080)

            imageReader = ImageReader.newInstance(chosen.width, chosen.height, ImageFormat.JPEG, 2)

            // ImageReader ตัวที่ 2 — สำหรับวิเคราะห์ความคมชัด (ขนาดเล็กเพื่อความเร็ว)
            analysisReader = ImageReader.newInstance(640, 480, ImageFormat.YUV_420_888, 2)
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

    private fun restorePreviewSession(camera: CameraDevice, readerSurface: Surface) {
        val prevSurf = previewSurface
        if (prevSurf != null) {
            torchEnabled = false
            try {
                cameraCaptureSessions?.close()
            } catch (ignored: Exception) {}

            backgroundHandler?.post {
                try {
                    val analysisSurf = analysisReader?.surface
                    val targets = mutableListOf(prevSurf, readerSurface)
                    if (analysisSurf != null) targets.add(analysisSurf)

                    camera.createCaptureSession(targets, object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(s: CameraCaptureSession) {
                            cameraCaptureSessions = s
                            try {
                                val previewBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                                previewBuilder.addTarget(prevSurf)
                                if (analysisSurf != null) previewBuilder.addTarget(analysisSurf)
                                previewBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                                previewBuilder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
                                s.setRepeatingRequest(previewBuilder.build(), null, backgroundHandler)
                            } catch (_: Exception) {}
                        }

                        override fun onConfigureFailed(s: CameraCaptureSession) {}
                    }, backgroundHandler)
                } catch (_: Exception) {}
            }
        }
    }

    fun takePicture(resultCallback: (Boolean, String?) -> Unit) {
        val camera = cameraDevice
        val reader = imageReader
        if (camera == null || reader == null) {
            resultCallback(false, "Camera not opened")
            return
        }

        try {
            val outputSurface = reader.surface

            val captureRequestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
            captureRequestBuilder.addTarget(outputSurface)
            captureRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            setFlashMode(captureRequestBuilder, torchEnabled)

            reader.setOnImageAvailableListener({ r ->
                val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                val buffer: ByteBuffer = image.planes[0].buffer
                val bytes = ByteArray(buffer.remaining())
                buffer.get(bytes)

                val time = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
                val file = File(activity.cacheDir, "IMG_$time.jpg")
                try {
                    FileOutputStream(file).use { fos ->
                        try {
                            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            val matrix = Matrix().apply { postRotate(90f) }
                            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
                            rotated.compress(Bitmap.CompressFormat.JPEG, 90, fos)
                            rotated.recycle()
                            bmp.recycle()
                        } catch (e: Exception) {
                            fos.write(bytes)
                        }
                    }
                    resultCallback(true, file.absolutePath)
                } catch (e: Exception) {
                    resultCallback(false, e.message)
                } finally {
                    image.close()
                    restorePreviewSession(camera, reader.surface)
                }
            }, backgroundHandler)

            val stillTargets = mutableListOf(outputSurface)
            camera.createCaptureSession(stillTargets, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    try {
                        session.capture(captureRequestBuilder.build(), object : CameraCaptureSession.CaptureCallback() {
                            override fun onCaptureFailed(session: CameraCaptureSession, request: CaptureRequest, failure: CaptureFailure) {
                                resultCallback(false, "Capture failed: ${failure.reason}")
                            }
                        }, backgroundHandler)
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

    fun closeCamera() {
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
    }

    fun setTorch(enabled: Boolean, resultCallback: (Boolean, String?) -> Unit) {
        val cam = cameraDevice
        val session = cameraCaptureSessions
        val surface = previewSurface

        if (cam == null || session == null || surface == null) {
            resultCallback(false, "Camera not ready")
            return
        }

        try {
            val previewBuilder = cam.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            previewBuilder.addTarget(surface)
            analysisReader?.surface?.let { previewBuilder.addTarget(it) }
            previewBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            previewBuilder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
            setFlashMode(previewBuilder, enabled)

            session.setRepeatingRequest(previewBuilder.build(), null, backgroundHandler)
            torchEnabled = enabled
            resultCallback(true, null)
        } catch (e: Exception) {
            resultCallback(false, e.message)
        }
    }

    fun focusAt(normX: Float, normY: Float, resultCallback: (Boolean, String?) -> Unit) {
        val cam = cameraDevice
        val session = cameraCaptureSessions
        val surface = previewSurface
        if (cam == null || session == null || surface == null) {
            resultCallback(false, "Camera not ready")
            return
        }

        try {
            val characteristics = cameraManager.getCameraCharacteristics(currentCameraId!!)
            val sensorArray = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
            if (sensorArray == null) {
                resultCallback(false, "No active array")
                return
            }

            val cx = (sensorArray.left + normX * sensorArray.width()).toInt()
            val cy = (sensorArray.top + normY * sensorArray.height()).toInt()
            val regionSize = (Math.max(sensorArray.width(), sensorArray.height()) * 0.08).toInt()

            val left = (cx - regionSize / 2).coerceIn(sensorArray.left, sensorArray.right - regionSize)
            val top = (cy - regionSize / 2).coerceIn(sensorArray.top, sensorArray.bottom - regionSize)

            val mr = MeteringRectangle(left, top, regionSize, regionSize, 1000)

            val captureBuilder = cam.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            captureBuilder.addTarget(surface)
            analysisReader?.surface?.let { captureBuilder.addTarget(it) }
            captureBuilder.set(CaptureRequest.CONTROL_AF_REGIONS, arrayOf(mr))
            captureBuilder.set(CaptureRequest.CONTROL_AE_REGIONS, arrayOf(mr))
            captureBuilder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
            captureBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_AUTO)
            captureBuilder.set(CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_START)
            setFlashMode(captureBuilder, torchEnabled)

            session.capture(captureBuilder.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
                    try {
                        val previewBuilder = cam.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                        previewBuilder.addTarget(surface)
                        analysisReader?.surface?.let { previewBuilder.addTarget(it) }
                        previewBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                        setFlashMode(previewBuilder, torchEnabled)
                        session.setRepeatingRequest(previewBuilder.build(), null, backgroundHandler)
                    } catch (e: CameraAccessException) { }
                    resultCallback(true, null)
                }
            }, backgroundHandler)

        } catch (e: Exception) {
            resultCallback(false, e.message)
        }
    }
}