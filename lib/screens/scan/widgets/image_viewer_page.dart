import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tappable thumbnail that opens [ImageViewerPage] with a Hero transition.
///
/// [heroTag] must be unique within the current route.
class ZoomableImage extends StatelessWidget {
  const ZoomableImage({
    super.key,
    required this.heroTag,
    required this.semanticLabel,
    required this.thumbnail,
    required this.fullImageBuilder,
    this.borderRadius = BorderRadius.zero,
  });

  final Object heroTag;
  final String semanticLabel;
  final Widget thumbnail;
  final WidgetBuilder fullImageBuilder;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      child: Stack(
        children: [
          ExcludeSemantics(child: Hero(tag: heroTag, child: thumbnail)),
          const Positioned(right: 4, bottom: 4, child: _ZoomBadge()),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: borderRadius,
                onTap: () => ImageViewerPage.open(
                  context,
                  heroTag: heroTag,
                  semanticLabel: semanticLabel,
                  builder: fullImageBuilder,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Signals that the thumbnail can be enlarged.
class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 15),
      ),
    );
  }
}

/// Full-screen image with pinch-to-zoom. Tap, back, Escape or the close
/// button dismisses it.
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({
    super.key,
    required this.heroTag,
    required this.semanticLabel,
    required this.child,
  });

  final Object heroTag;
  final String semanticLabel;
  final Widget child;

  static Future<void> open(
    BuildContext context, {
    required Object heroTag,
    required String semanticLabel,
    required WidgetBuilder builder,
  }) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: duration,
        reverseTransitionDuration: duration,
        pageBuilder: (context, _, __) => ImageViewerPage(
          heroTag: heroTag,
          semanticLabel: semanticLabel,
          child: builder(context),
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// Decode width for full-screen images: one screen width in physical
  /// pixels. Smaller images are never upscaled.
  static int cacheWidthFor(BuildContext context) =>
      (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context))
          .round();

  static Widget errorBuilder(
      BuildContext context, Object error, StackTrace? _) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_rounded,
              color: Colors.white70, size: 48),
          const SizedBox(height: 8),
          Text(
            'โหลดรูปไม่ได้',
            style: GoogleFonts.kanit(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).maybePop();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: close,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Hero(
                        tag: heroTag,
                        child: Semantics(
                          image: true,
                          label: semanticLabel,
                          child: ExcludeSemantics(
                            child: SizedBox.expand(child: child),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconButton(
                        tooltip: 'ปิดรูปขยาย',
                        onPressed: close,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
