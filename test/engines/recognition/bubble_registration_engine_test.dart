import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_codec.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/preprocessing/domain/pixel_images.dart';
import 'package:capstone_development/engines/recognition/application/bubble_registration_engine.dart';
import 'package:capstone_development/engines/recognition/application/bubble_registration_fit.dart';
import 'package:capstone_development/engines/recognition/application/canonical_bubble_mapper.dart';
import 'package:capstone_development/engines/recognition/application/printed_bubble_locator.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement_config.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_registration.dart';
import 'package:capstone_development/engines/recognition/domain/canonical_bubble_roi.dart';

PageLayout fixture({bool columns = false}) {
  final data =
      jsonDecode(
            File(
              'test/fixtures/p15_6/published_manifest.json',
            ).readAsStringSync(),
          )
          as Map;
  if (columns) {
    void change(Object? value) {
      if (value is List) {
        for (final item in value) {
          change(item);
        }
      }
      if (value is Map) {
        final id = value['questionId'];
        if (id is String && int.parse(id.split('-')[1]) >= 7) {
          if (value.containsKey('columnIndex')) value['columnIndex'] = 1;
          if (value['physicalCenter'] is Map) {
            value['physicalCenter']['x'] += 54.5;
          }
          if (value['physicalBounds'] is Map) {
            value['physicalBounds']['left'] += 54.5;
          }
        }
        for (final child in value.values) {
          change(child);
        }
      }
    }

    change(data['artifact']['layout']);
  }
  return const PublishedTemplateArtifactCodec()
      .decode((data['artifact'] as Map).cast<String, Object?>())
      .layout
      .pages
      .single;
}

List<CanonicalBubbleRoi> rois(PageLayout page) => [
  for (final b in page.bubbleRegions)
    const CanonicalBubbleMapper().map(b, page, const BubbleMeasurementConfig()),
];

ImagePoint displaced(ImagePoint p) => ImagePoint(
  p.x + 4 + .005 * (p.x - 345),
  p.y + 10 - .018 * (p.y - 510) + .03 * (p.x - 345),
);

GrayImage painted(
  List<CanonicalBubbleRoi> expected,
  ImagePoint Function(ImagePoint) transform, {
  Set<int> missing = const {},
  int background = 245,
  bool labelsOnly = false,
  String? style,
}) {
  final size = ImageSize(width: 2100, height: 2970);
  final pixels = Uint8List(size.area)..fillRange(0, size.area, background);
  for (var index = 0; index < expected.length; index++) {
    if (missing.contains(index)) continue;
    final roi = expected[index];
    final center = transform(roi.center);
    for (var y = (center.y - 28).floor(); y <= (center.y + 28).ceil(); y++) {
      for (var x = (center.x - 28).floor(); x <= (center.x + 28).ceil(); x++) {
        final dx = x + .5 - center.x, dy = y + .5 - center.y;
        final radius = math.sqrt(dx * dx + dy * dy);
        if ((!labelsOnly && (radius - 25).abs() < 1.3) ||
            (dx.abs() < 2 && dy.abs() < 9)) {
          pixels[y * 2100 + x] = 25;
        }
        if (index == 17 && radius < 24 && style != null) {
          final marked = switch (style) {
            'full' || 'faint' => true,
            'half' => dx < 0,
            'crescent' => dx < -10,
            'dots' => x % 7 < 3 && y % 7 < 3,
            'X' => (dx - dy).abs() < 3 || (dx + dy).abs() < 3,
            _ => false,
          };
          if (marked) {
            pixels[y * 2100 + x] = style == 'faint' ? background - 35 : 25;
          }
        }
      }
    }
  }
  return GrayImage.owned(size: size, pixels: pixels);
}

void main() {
  late PageLayout page;
  late List<CanonicalBubbleRoi> expected;
  setUp(() {
    page = fixture();
    expected = rois(page);
  });
  test('affine centers use held-out rows and preserve every mask radius', () {
    final result = const BubbleRegistrationEngine().refine(
      page,
      painted(expected, displaced),
      expected,
    );
    expect(
      result.isSuccess,
      isTrue,
      reason: result.isFailure ? result.error.toString() : null,
    );
    for (var i = 0; i < expected.length; i++) {
      final roi = result.value.rois[i];
      expect(roi.center.distanceTo(displaced(expected[i].center)), lessThan(1));
      expect(roi.interiorRadius, expected[i].interiorRadius);
      expect(roi.centerExclusionRadius, expected[i].centerExclusionRadius);
      expect(roi.baselineInnerRadius, expected[i].baselineInnerRadius);
      expect(roi.baselineOuterRadius, expected[i].baselineOuterRadius);
    }
  });
  test('every mask moves together at pixel-center precision', () {
    final a = expected.first,
        b = a.withCenter(ImagePoint(a.center.x + 7, a.center.y - 4));
    for (var y = 450; y < 570; y++) {
      for (var x = 280; x < 410; x++) {
        expect(
          b.containsInteriorPixel(x + 7, y - 4),
          a.containsInteriorPixel(x, y),
        );
        expect(
          b.containsBaselinePixel(x + 7, y - 4),
          a.containsBaselinePixel(x, y),
        );
        expect(
          b.containsPrintedPixel(x + 7, y - 4),
          a.containsPrintedPixel(x, y),
        );
      }
    }
  });
  test(
    'missing interior outline interpolates only within observed support',
    () {
      final result = const BubbleRegistrationEngine().refine(
        page,
        painted(expected, displaced, missing: {17}),
        expected,
      );
      expect(result.isSuccess, isTrue);
      expect(
        result.value.rois[17].center.distanceTo(displaced(expected[17].center)),
        lessThan(1),
      );
      expect(result.value.observations.any((o) => o.index == 17), isFalse);
    },
  );
  test('missing outer support never extrapolates a correction', () {
    final result = const BubbleRegistrationEngine().refine(
      page,
      painted(expected, displaced, missing: {4}),
      expected,
    );
    expect(result.isFailure, isTrue);
    expect(result.error.code, 'BUBBLE_REGISTRATION_UNTRUSTWORTHY');
  });
  test('labels without outlines cannot establish registration', () {
    final result = const BubbleRegistrationEngine().refine(
      page,
      painted(expected, displaced, labelsOnly: true),
      expected,
    );
    expect(result.isFailure, isTrue);
  });
  test('unverified blank pixels cannot silently fall back', () {
    final gray = GrayImage.owned(
      size: ImageSize(width: 2100, height: 2970),
      pixels: Uint8List(2100 * 2970)..fillRange(0, 2100 * 2970, 255),
    );
    expect(
      const BubbleRegistrationEngine().refine(page, gray, expected).isFailure,
      isTrue,
    );
  });
  test('verified already aligned outlines preserve baseline coordinates', () {
    final result = const BubbleRegistrationEngine()
        .refine(page, painted(expected, (p) => p), expected)
        .value;
    expect(result.regions.single['method'], 'verifiedBaseline');
    expect(result.rois.map((r) => r.center), expected.map((r) => r.center));
  });
  test('robust fit rejects a false circle proposal without fitting it', () {
    final points = [
      for (var i = 0; i < expected.length; i++)
        BubbleCenterObservation(
          index: i,
          question: page.bubbleRegions[i].questionId.value,
          expected: expected[i].center,
          observed: i == 17
              ? ImagePoint(expected[i].center.x - 20, expected[i].center.y + 15)
              : displaced(expected[i].center),
          radius: 25,
          outlineCoverage: 1,
        ),
    ];
    final fit = BubbleRegistrationFit.robust(
      points,
      3,
      const BubbleRegistrationConfig(),
    )!;
    expect(fit.inliers.length, 31);
    expect(fit.inliers.any((p) => p.index == 17), isFalse);
    expect(
      fit
          .project(expected[17].center)
          .distanceTo(displaced(expected[17].center)),
      lessThan(1e-6),
    );
  });
  test('two independent columns do not share displacement coefficients', () {
    page = fixture(columns: true);
    expected = rois(page);
    ImagePoint transform(ImagePoint p) =>
        p.x > 800 ? ImagePoint(p.x - 7, p.y + 6) : displaced(p);
    final result = const BubbleRegistrationEngine().refine(
      page,
      painted(expected, transform),
      expected,
    );
    expect(
      result.isSuccess,
      isTrue,
      reason: result.isFailure ? result.error.toString() : null,
    );
    expect(result.value.regions.length, 2);
    for (var i = 0; i < expected.length; i++) {
      expect(
        result.value.rois[i].center.distanceTo(transform(expected[i].center)),
        lessThan(1),
      );
    }
  });
  for (final paper in [140, 220, 255]) {
    test('local contrast handles paper intensity $paper deterministically', () {
      final gray = painted(expected, displaced, background: paper);
      const engine = BubbleRegistrationEngine();
      final a = engine.refine(page, gray, expected).value,
          b = engine.refine(page, gray, expected).value;
      expect(a.rois.map((r) => r.center), b.rois.map((r) => r.center));
    });
  }
  test('a neighboring circle cannot be reassigned to a missing target', () {
    final gray = painted(expected, (p) => p, missing: {0});
    expect(
      const PrintedBubbleLocator().locate(
        gray,
        expected[0],
        0,
        'question-1',
        const BubbleRegistrationConfig(),
      ),
      isNull,
    );
  });
  for (final style in ['full', 'half', 'crescent', 'dots', 'X', 'faint']) {
    test('printed outline association survives $style marking', () {
      final result = const BubbleRegistrationEngine().refine(
        page,
        painted(expected, displaced, style: style),
        expected,
      );
      expect(result.isSuccess, isTrue);
      expect(
        result.value.rois[17].center.distanceTo(displaced(expected[17].center)),
        lessThan(1),
      );
    });
  }
}
