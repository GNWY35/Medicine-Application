import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gal/gal.dart';

import '../../services/scan_api_service.dart';
import 'scan_result_page.dart';

/// Quality of the area inside the detection frame, computed natively.
@immutable
class _FrameQuality {
  const _FrameQuality({
    this.edgePixels = 0,
    this.density = 0,
    this.sharpness = 0,
    this.isSharp = false,
    this.tooDark = false,
  });

  final int edgePixels;

  /// edgePixels / analysed pixels, 0..1.
  final double density;
  final double sharpness;
  final bool isSharp;
  final bool tooDark;
}

class RealtimeDetectionPage extends StatefulWidget {
  const RealtimeDetectionPage({super.key});

  @override
  State<RealtimeDetectionPage> createState() =>
      _RealtimeDetectionPageState();
}

class _RealtimeDetectionPageState
    extends State<RealtimeDetectionPage> {
  /// Native Camera2 API
  static const _ch =
      MethodChannel('dart_camera2api/camera');

  /// Realtime sharpness stream
  static const _sharpnessStream =
      EventChannel('dart_camera2api/sharpness');

  int? _textureId;

  bool _capturing = false;
  String? _error;

  /// Detection frame as a fraction of the preview. Must match
  /// CameraHandler.ROI_WIDTH_FRACTION / ROI_HEIGHT_FRACTION on Android.
  /// The captured photo is cropped natively to this frame (+ CROP_MARGIN).
  static const double _roiWidthFactor = 0.65;
  static const double _roiHeightFactor = 0.40;

  /// Upright size of the native preview buffer. MainActivity sets it to
  /// 1280x720 in sensor orientation; keep the two in sync.
  static const Size _previewPortraitSize = Size(720, 1280);

  /// ROI / Sharpness data. Kept out of setState so the Texture does not
  /// rebuild on every analysed frame.
  final ValueNotifier<_FrameQuality> _quality =
      ValueNotifier(const _FrameQuality());
  StreamSubscription<dynamic>? _sharpnessSub;

  final ValueNotifier<Offset?> _focusPoint = ValueNotifier(null);
  Timer? _focusTimer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  /// Initialize native camera
  Future<void> _initCamera() async {
    try {
      final id = await _ch.invokeMethod('init');

      if (!mounted) return;

      if (id is int) {
        setState(() {
          _textureId = id;
        });

        _listenSharpness();
      } else {
        setState(() {
          _error = 'เปิดกล้องไม่สำเร็จ';
        });
      }
    } on PlatformException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  /// Listen realtime sharpness from native
  void _listenSharpness() {
    _sharpnessSub?.cancel();
    _sharpnessSub = _sharpnessStream.receiveBroadcastStream().listen(
      (event) {
        if (!mounted || event is! Map) return;

        _quality.value = _FrameQuality(
          edgePixels: (event['edgePixels'] as num?)?.toInt() ?? 0,
          density: (event['density'] as num?)?.toDouble() ?? 0,
          sharpness: (event['sharpness'] as num?)?.toDouble() ?? 0,
          isSharp: event['isSharp'] as bool? ?? false,
          tooDark: event['tooDark'] as bool? ?? false,
        );
      },
      onError: (e) {
        debugPrint('sharpness stream error: $e');
      },
    );
  }

  /// Tap to focus/meter on a point. The preview box has the camera's exact
  /// aspect ratio, so the tap maps 1:1 to the camera image.
  Future<void> _onTapFocus(TapDownDetails details, Size viewSize) async {
    final point = Offset(
      (details.localPosition.dx / viewSize.width).clamp(0.0, 1.0),
      (details.localPosition.dy / viewSize.height).clamp(0.0, 1.0),
    );

    _focusTimer?.cancel();
    _focusPoint.value = details.localPosition;
    _focusTimer = Timer(const Duration(milliseconds: 800), () {
      _focusPoint.value = null;
    });

    try {
      await _ch.invokeMethod('focusAt', {'x': point.dx, 'y': point.dy});
    } catch (e) {
      debugPrint('focusAt failed: $e');
    }
  }

  /// Capture image
  Future<void> _onCapture() async {
    if (_capturing || !_quality.value.isSharp) return;

    setState(() {
      _capturing = true;
    });

    try {
      /// Native capture
      final path =
          await _ch.invokeMethod('takePicture');

      if (!mounted) return;

      if (path is! String || path.isEmpty) {
        throw Exception('ถ่ายภาพไม่สำเร็จ');
      }

      /// Send to AI API
      final result = await analyzeImage(File(path));

      if (!mounted) return;

      if (!result.isSuccess) {
        _showSnack(result.errorMessage!);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScanResultPage(
              imageFile: File(path),
              detectedNames: result.detectedNames,
              detectedBboxes: result.detectedBboxes,
              autosave: true,
            ),
          ),
        );
      }

      /// Save to gallery only if found medicine
      if (result.isSuccess) {
        try {
          await Gal.putImage(
            path,
            album: 'ยาของฉัน',
          );
        } catch (_) {}
      }
    } on PlatformException catch (e) {
      _showSnack(
        'เกิดข้อผิดพลาด: ${e.message}',
      );
    } catch (e) {
      _showSnack(
        'เกิดข้อผิดพลาด: $e',
      );
    }

    if (mounted) {
      setState(() {
        _capturing = false;
      });
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.kanit(),
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  void dispose() {
    _sharpnessSub?.cancel();
    _focusTimer?.cancel();
    _quality.dispose();
    _focusPoint.dispose();
    _ch.invokeMethod('close').catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    if (_textureId == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,

        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: Text(
          'Realtime Scan',
          style: GoogleFonts.kanit(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),

        centerTitle: true,
      ),

      body: Column(
        children: [
          Expanded(
            child: Center(
              // Same aspect ratio as the camera buffer: no stretching, and the
              // detection frame covers exactly the area analysed natively.
              child: AspectRatio(
                aspectRatio: _previewPortraitSize.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _onTapFocus(d, constraints.biggest),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        /// Native Camera Preview
                        Texture(
                          textureId: _textureId!,
                        ),

                        /// Detection Frame
                        Align(
                          alignment: Alignment.center,
                          child: FractionallySizedBox(
                            widthFactor: _roiWidthFactor,
                            heightFactor: _roiHeightFactor,
                            child: ValueListenableBuilder<_FrameQuality>(
                              valueListenable: _quality,
                              builder: (context, q, _) => AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 250),

                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: q.isSharp
                                        ? const Color(0xFF00E676)
                                        : Colors.red,
                                    width: 3,
                                  ),

                                  borderRadius:
                                      BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),

                        /// Tap-to-focus indicator
                        ValueListenableBuilder<Offset?>(
                          valueListenable: _focusPoint,
                          builder: (context, p, _) {
                            if (p == null) return const SizedBox.shrink();
                            return Positioned(
                              left: p.dx - 24,
                              top: p.dy - 24,
                              child: IgnorePointer(
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          /// Bottom Panel
          Container(
            color: Colors.black,
            padding:
                const EdgeInsets.fromLTRB(24, 16, 24, 32),

            child: ValueListenableBuilder<_FrameQuality>(
              valueListenable: _quality,
              builder: (context, q, _) => _buildBottomPanel(q),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(_FrameQuality q) {
    final isSharp = q.isSharp;

    final statusText = isSharp
        ? 'ภาพชัด พร้อมถ่าย'
        : (q.tooDark
            ? 'กรุณาอยู่ในที่ที่มีแสงเพียงพอ'
            : 'ถือกล้องให้นิ่ง วางยาเพียง 1 ชนิดไว้ในกรอบ');

    final statusColor = isSharp
        ? const Color(0xFF00E676)
        : Colors.redAccent;

    return Column(
      children: [
        Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              isSharp
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,

              color: statusColor,
              size: 18,
            ),

            const SizedBox(width: 8),

            Flexible(
              child: Text(
                statusText,
                style: GoogleFonts.kanit(
                  color: statusColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        Text(
          'Sharpness: ${q.sharpness.toStringAsFixed(1)}'
          '  ·  Density: ${(q.density * 100).toStringAsFixed(1)}%',

          style: GoogleFonts.kanit(
            color: Colors.white38,
            fontSize: 11,
          ),
        ),

        const SizedBox(height: 20),

        GestureDetector(
          onTap: (!_capturing && isSharp)
              ? _onCapture
              : null,

          child: AnimatedContainer(
            duration:
                const Duration(milliseconds: 250),

            width: 76,
            height: 76,

            decoration: BoxDecoration(
              shape: BoxShape.circle,

              color: _capturing
                  ? Colors.white24
                  : (isSharp
                      ? const Color(0xFF00C853)
                      : Colors.red.withValues(
                          alpha: 0.25,
                        )),

              border: Border.all(
                color: isSharp
                    ? const Color(0xFF00E676)
                    : Colors.red,

                width: 3,
              ),

              boxShadow:
                  isSharp && !_capturing
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF00E676)
                                    .withValues(
                              alpha: 0.45,
                            ),

                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ]
                      : [],
            ),

            child: _capturing
                ? const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor:
                          AlwaysStoppedAnimation(
                        Colors.white,
                      ),
                    ),
                  )
                : Icon(
                    Icons.camera_alt_rounded,

                    color: isSharp
                        ? Colors.white
                        : Colors.red.withValues(
                            alpha: 0.5,
                          ),

                    size: 32,
                  ),
          ),
        ),
      ],
    );
  }
}