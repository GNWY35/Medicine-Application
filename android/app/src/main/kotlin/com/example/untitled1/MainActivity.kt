package com.example.untitled1

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private var cameraHandler: CameraHandler? = null
	private var sharpnessSink: EventChannel.EventSink? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		cameraHandler = CameraHandler(this)

		// EventChannel — stream ค่าความคมชัดจาก preview ไป Flutter ต่อเนื่อง
		EventChannel(flutterEngine.dartExecutor.binaryMessenger, "dart_camera2api/sharpness")
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					sharpnessSink = events
					cameraHandler?.onSharpness = { variance, isSharp ->
						sharpnessSink?.success(
							mapOf(
								"sharpness" to variance,
								"isSharp" to isSharp
							)
						)
					}
				}

				override fun onCancel(arguments: Any?) {
					sharpnessSink = null
					cameraHandler?.onSharpness = null
				}
			})

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dart_camera2api/camera").setMethodCallHandler { call, result ->
			when (call.method) {
				"init" -> {
					try {
						val entry = flutterEngine.renderer.createSurfaceTexture()
						val st = entry.surfaceTexture()
						val previewW = 1280
						val previewH = 720
						st.setDefaultBufferSize(previewW, previewH)
						val surface = android.view.Surface(st)

						cameraHandler?.openCameraWithPreview(surface, android.util.Size(previewW, previewH)) { ok, error ->
							if (ok) {
								result.success(entry.id())
							} else {
								result.error("OPEN_FAILED", error ?: "unknown", null)
							}
						} ?: result.error("NO_HANDLER", "CameraHandler not initialized", null)
					} catch (e: Exception) {
						result.error("INIT_ERROR", e.message, null)
					}
				}
				"setFlash" -> {
					val enabled = when (val arg = call.arguments) {
						is Boolean -> arg
						is java.lang.Boolean -> arg.booleanValue()
						else -> false
					}
					cameraHandler?.setTorch(enabled) { ok, error ->
						if (ok) result.success(true) else result.error("FLASH_FAILED", error ?: "unknown", null)
					} ?: result.error("NO_HANDLER", "CameraHandler not initialized", null)
				}
				"focusAt" -> {
					val args = call.arguments as? Map<*, *>
					val x = when (val vx = args?.get("x")) {
						is Double -> vx.toFloat()
						is Float -> vx
						is Int -> vx.toFloat()
						else -> 0f
					}
					val y = when (val vy = args?.get("y")) {
						is Double -> vy.toFloat()
						is Float -> vy
						is Int -> vy.toFloat()
						else -> 0f
					}
					cameraHandler?.focusAt(x, y) { ok, error ->
						if (ok) result.success(true) else result.error("FOCUS_FAILED", error ?: "unknown", null)
					} ?: result.error("NO_HANDLER", "CameraHandler not initialized", null)
				}
				"takePicture" -> {
					cameraHandler?.takePicture { ok, path ->
						if (ok) result.success(path) else result.error("CAPTURE_FAILED", path ?: "unknown", null)
					} ?: result.error("NO_HANDLER", "CameraHandler not initialized", null)
				}
				"close" -> {
					cameraHandler?.closeCamera()
					result.success(true)
				}
				else -> result.notImplemented()
			}
		}
	}
}