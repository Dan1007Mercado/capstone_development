import '../../aruco/domain/image_geometry.dart';
import '../../layout/domain/layout_regions.dart';
import '../../layout/domain/page_layout.dart';
import '../domain/bubble_measurement_config.dart';
import '../domain/canonical_bubble_roi.dart';

/// Central physical-page to canonical-pixel conversion for bubble sampling.
final class CanonicalBubbleMapper {
  const CanonicalBubbleMapper();

  CanonicalBubbleRoi map(
    BubbleRegion bubble,
    PageLayout page,
    BubbleMeasurementConfig config,
  ) {
    final scaleX =
        page.canonicalPageSpec.widthPixels /
        page.pageSpec.size.width.millimeters;
    final scaleY =
        page.canonicalPageSpec.heightPixels /
        page.pageSpec.size.height.millimeters;
    final radius =
        bubble.physicalDiameter.millimeters /
        2 *
        (scaleX < scaleY ? scaleX : scaleY);
    return CanonicalBubbleRoi(
      center: ImagePoint(
        bubble.physicalCenter.x.millimeters * scaleX,
        bubble.physicalCenter.y.millimeters * scaleY,
      ),
      printedRadius: radius,
      interiorRadius: radius * config.interiorRadiusRatio,
      baselineInnerRadius: radius * config.baselineInnerRadiusRatio,
      baselineOuterRadius: radius * config.baselineOuterRadiusRatio,
    );
  }
}
