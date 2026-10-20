import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel _cameraChannel = MethodChannel('dart_camera2api/camera');

class FullScreenCameraPreview extends StatefulWidget {
  const FullScreenCameraPreview({
    required this.textureId,
    super.key,
  });

  final int textureId;

  @override
  State<FullScreenCameraPreview> createState() =>
      _FullScreenCameraPreviewState();
}

class _FullScreenCameraPreviewState extends State<FullScreenCameraPreview> {
  bool _isCapturing = false;
  bool _flashOn = false;
  Offset? _focusPoint;
  double _focusOpacity = 0.0;
  Timer? _focusTimer;

  Future<void> _closeCamera() async {
    try {
      await _cameraChannel.invokeMethod('close');
    } catch (_) {}
  }

  Future<void> _capture() async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);
    try {
      final path = await _cameraChannel.invokeMethod<String>('takePicture');
      await _closeCamera();
      if (!mounted) return;
      Navigator.of(context).pop<String?>(path);
    } catch (error) {
      await _closeCamera();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $error')),
      );
      Navigator.of(context).pop<String?>(null);
    }
  }

  Future<void> _focusAt(TapDownDetails details, BoxConstraints constraints) async {
    final dx = details.localPosition.dx;
    final dy = details.localPosition.dy;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final normalizedX = (dx / width).clamp(0.0, 1.0);
    final normalizedY = (dy / height).clamp(0.0, 1.0);

    try {
      await _cameraChannel.invokeMethod('focusAt', {
        'x': normalizedX,
        'y': normalizedY,
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Focus failed: $error')),
      );
    }

    _focusTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _focusPoint = details.localPosition;
      _focusOpacity = 1.0;
    });
    _focusTimer = Timer(
      const Duration(milliseconds: 700),
      () {
        if (!mounted) return;
        setState(() => _focusOpacity = 0.0);
      },
    );
  }

  Future<void> _toggleFlash() async {
    try {
      final success = await _cameraChannel.invokeMethod<bool>(
        'setFlash',
        !_flashOn,
      );
      if (!mounted) return;
      if (success == true) {
        setState(() => _flashOn = !_flashOn);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Flash toggle failed: $error')),
      );
    }
  }

  Future<void> _closePreview() async {
    await _closeCamera();
    if (!mounted) return;
    Navigator.of(context).pop<String?>(null);
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, __) async {
        await _closeCamera();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _focusAt(details, constraints),
                    child: Texture(textureId: widget.textureId),
                  );
                },
              ),
            ),
            if (_focusPoint != null)
              Positioned(
                left: (_focusPoint!.dx - 24).clamp(0.0, double.infinity),
                top: (_focusPoint!.dy - 24).clamp(0.0, double.infinity),
                child: AnimatedOpacity(
                  opacity: _focusOpacity,
                  duration: const Duration(milliseconds: 120),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              top: 40,
              child: IconButton(
                color: Colors.white,
                icon: const Icon(Icons.close),
                onPressed: _closePreview,
              ),
            ),
            Positioned(
              right: 16,
              top: 40,
              child: IconButton(
                color: Colors.white,
                icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
                onPressed: _toggleFlash,
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton(
                  onPressed: _capture,
                  child: _isCapturing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(Icons.camera_alt),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
