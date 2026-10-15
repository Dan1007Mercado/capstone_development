import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/geometry/normalized_geometry.dart';
import '../engines/layout/domain/page_layout.dart';

const omrPortraitViewportAspectRatio = 3 / 4;

double omrPageGuideAspectRatio(PageLayout pageLayout) =>
    pageLayout.pageSpec.size.width.millimeters /
    pageLayout.pageSpec.size.height.millimeters;

double omrDisplayedPreviewAspectRatio({
  required double cameraAspectRatio,
  required Orientation orientation,
}) => orientation == Orientation.portrait
    ? 1 / cameraAspectRatio
    : cameraAspectRatio;

/// Display-only center-cropped preview. CameraPreview retains responsibility
/// for the platform texture rotation; this widget applies no extra rotation.
class OmrCameraPreview extends StatelessWidget {
  const OmrCameraPreview({
    required this.controller,
    required this.pageLayout,
    required this.isReady,
    super.key,
  });

  final CameraController controller;
  final PageLayout pageLayout;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    final viewportAspect = orientation == Orientation.portrait
        ? omrPortraitViewportAspectRatio
        : 4 / 3;
    final previewAspect = omrDisplayedPreviewAspectRatio(
      cameraAspectRatio: controller.value.aspectRatio,
      orientation: orientation,
    );
    return AspectRatio(
      key: const ValueKey('omr-preview-viewport'),
      aspectRatio: viewportAspect,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: SizedBox(
                width: previewAspect * 1000,
                height: 1000,
                child: CameraPreview(controller),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: OmrPageGuidePainter(
                  pageLayout: pageLayout,
                  isReady: isReady,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OmrPageGuidePainter extends CustomPainter {
  const OmrPageGuidePainter({required this.pageLayout, required this.isReady});

  final PageLayout pageLayout;
  final bool isReady;

  @override
  void paint(Canvas canvas, Size size) {
    final pageAspect = omrPageGuideAspectRatio(pageLayout);
    var guideWidth = size.width * 0.86;
    var guideHeight = guideWidth / pageAspect;
    if (guideHeight > size.height * 0.9) {
      guideHeight = size.height * 0.9;
      guideWidth = guideHeight * pageAspect;
    }
    final pageRect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: guideWidth,
      height: guideHeight,
    );
    final statusColor = isReady ? Colors.greenAccent : Colors.orangeAccent;
    canvas.drawRect(
      pageRect,
      Paint()
        ..color = statusColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawRect(
      _normalizedRect(pageRect, pageLayout.normalizedSafeBounds),
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final markerPaint = Paint()
      ..color = statusColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final marker in pageLayout.markerRegions) {
      canvas.drawRect(
        _normalizedRect(pageRect, marker.normalizedBounds),
        markerPaint,
      );
    }
  }

  Rect _normalizedRect(Rect page, NormalizedRect normalized) => Rect.fromLTWH(
    page.left + normalized.left.value * page.width,
    page.top + normalized.top.value * page.height,
    normalized.width.value * page.width,
    normalized.height.value * page.height,
  );

  @override
  bool shouldRepaint(OmrPageGuidePainter oldDelegate) =>
      oldDelegate.pageLayout != pageLayout || oldDelegate.isReady != isReady;
}
