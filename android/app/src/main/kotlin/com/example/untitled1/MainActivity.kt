package com.example.untitled1

import android.app.Activity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Camera callbacks arrive on the camera thread and some (open/disconnect) can fire more than once.
 * Flutter requires exactly one reply per call, on the main thread.
 */
private class MainThreadResult(private val activity: Activity, private val result: MethodChannel.Result) {
	private var replied = false // touched on the main thread only

	fun success(value: Any?) = post { result.success(value) }

	fun error(code: String, message: String?) = post { result.error(code, message ?: "unknown", null) }

	private fun post(block: () -> Unit) = activity.runOnUiThread {
		if (!replied) {
			replied = true
			block()
		}
	}
}

class MainActivity : FlutterActivity() {
	private var cameraHandler: CameraHandler? = null
	private var sharpnessSink: EventChannel.EventSink? = null
	private var previewTexture: TextureRegistry.SurfaceTextureEntry? = null

	// ขนาด preview ในแนวเซนเซอร์ ฝั่ง Dart ใช้ 720x1280 (แนวตั้ง) จัดสัดส่วน Texture ต้องตรงกัน
	private val previewW = 1280
	private val previewH = 720

	private fun releasePreviewTexture() {
		previewTexture?.release()
		previewTexture = null
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		cameraHandler = CameraHandler(this)

		// EventChannel — stream คุณภาพภาพในกรอบตรวจจับไป Flutter ต่อเนื่อง
		EventChannel(flutterEngine.dartExecutor.binaryMessenger, "dart_camera2api/sharpness")
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					sharpnessSink = events
					cameraHandler?.onSharpness = { q ->
						sharpnessSink?.success(
							mapOf(
								"sharpness" to q.sharpness,
								"isSharp" to q.isSharp,
								"edgePixels" to q.edgePixels,
								"density" to q.density,
								"tooDark" to q.tooDark
							)
						)
					}
				}

				override fun onCancel(arguments: Any?) {
					sharpnessSink = null
					cameraHandler?.onSharpness = null
				}
			})

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dart_camera2api/camera").setMethodCallHandler { call, rawResult ->
			val result = MainThreadResult(this, rawResult)
			when (call.method) {
				"init" -> {
					try {
						// เปิดซ้ำโดยไม่ได้ปิด: คืน texture เดิมก่อน กันรั่ว
						releasePreviewTexture()
						val entry = flutterEngine.renderer.createSurfaceTexture()
						previewTexture = entry
						val st = entry.surfaceTexture()
						st.setDefaultBufferSize(previewW, previewH)
						val surface = android.view.Surface(st)

						cameraHandler?.openCameraWithPreview(surface, android.util.Size(previewW, previewH)) { ok, error ->
							if (ok) {
								result.success(entry.id())
							} else {
								result.error("OPEN_FAILED", error)
							}
						} ?: result.error("NO_HANDLER", "CameraHandler not initialized")
					} catch (e: Exception) {
						result.error("INIT_ERROR", e.message)
					}
				}
				"focusAt" -> {
					// x, y: จุดบน preview ที่แสดงตั้งตรง normalized 0..1 (หัก crop/letterbox ฝั่ง Dart แล้ว)
					val args = call.arguments as? Map<*, *>
					val x = (args?.get("x") as? Number)?.toFloat() ?: 0.5f
					val y = (args?.get("y") as? Number)?.toFloat() ?: 0.5f
					cameraHandler?.focusAt(x, y) { ok, error ->
						if (ok) result.success(true) else result.error("FOCUS_FAILED", error)
					} ?: result.error("NO_HANDLER", "CameraHandler not initialized")
				}
				"takePicture" -> {
					cameraHandler?.takePicture { ok, path ->
						if (ok) result.success(path) else result.error("CAPTURE_FAILED", path)
					} ?: result.error("NO_HANDLER", "CameraHandler not initialized")
				}
				"close" -> {
					cameraHandler?.closeCamera()
					releasePreviewTexture()
					result.success(true)
				}
				else -> rawResult.notImplemented()
			}
		}
	}
}
