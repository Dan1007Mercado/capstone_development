import 'dart:math' as math;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../layout/domain/page_layout.dart';
import '../../preprocessing/domain/pixel_images.dart';
import '../domain/bubble_registration.dart';
import '../domain/canonical_bubble_roi.dart';
import 'bubble_registration_fit.dart';
import 'printed_bubble_locator.dart';

final class BubbleRegistrationEngine {
  const BubbleRegistrationEngine({
    this.config = const BubbleRegistrationConfig(),
    this.locator = const PrintedBubbleLocator(),
  });
  final BubbleRegistrationConfig config;
  final PrintedBubbleLocator locator;

  EngineResult<BubbleRegistration> refine(
    PageLayout page,
    GrayImage image,
    List<CanonicalBubbleRoi> expected,
  ) {
    final watch = Stopwatch()..start();
    EngineResult<BubbleRegistration> failure(
      String reason, [
      Map<String, Object?> details = const {},
    ]) => EngineResult.failure(
      EngineError(
        code: 'BUBBLE_REGISTRATION_UNTRUSTWORTHY',
        message: 'Printed bubble registration requires a rescan: $reason',
        details: details,
      ),
    );
    if (!config.valid || expected.length != page.bubbleRegions.length) {
      return failure('invalid registration configuration');
    }
    final groups = <int?, List<int>>{};
    final observations = <BubbleCenterObservation>[];
    final byQuestion = {
      for (final q in page.questionRegions) q.questionId: q.columnIndex,
    };
    for (var i = 0; i < expected.length; i++) {
      final bubble = page.bubbleRegions[i];
      groups.putIfAbsent(byQuestion[bubble.questionId], () => []).add(i);
      final o = locator.locate(
        image,
        expected[i],
        i,
        bubble.questionId.value,
        config,
      );
      if (o != null) observations.add(o);
    }
    final refined = List<CanonicalBubbleRoi>.of(expected);
    final diagnostics = <Map<String, Object?>>[];
    for (final entry in groups.entries) {
      final indices = entry.value;
      final landmarks = observations
          .where((o) => indices.contains(o.index))
          .toList();
      final radius = indices
          .map((i) => expected[i].printedRadius)
          .reduce(math.min);
      final tolerance = radius * config.fitErrorRatio;
      final translations = _rowTranslations(
        landmarks,
        indices,
        expected,
        tolerance,
      );
      // A verified already-aligned region needs no fitted displacement model.
      if (landmarks.length == indices.length &&
          landmarks.every(
            (o) => o.expected.distanceTo(o.observed) <= tolerance,
          )) {
        diagnostics.add({
          'column': entry.key,
          'method': 'verifiedBaseline',
          'landmarks': landmarks.length,
        });
        continue;
      }
      if (translations.length == indices.length) {
        for (final i in indices) {
          refined[i] = expected[i].withCenter(translations[i]!);
        }
        diagnostics.add({
          'column': entry.key,
          'method': 'rowTranslations',
          'landmarks': landmarks.length,
        });
        continue;
      }
      final fit = BubbleRegistrationFit.robust(landmarks, tolerance, config);
      final rows = landmarks.map((o) => o.question).toSet().toList()
        ..sort((a, b) {
          final ay = landmarks.firstWhere((o) => o.question == a).expected.y;
          final by = landmarks.firstWhere((o) => o.question == b).expected.y;
          return ay == by ? a.compareTo(b) : ay.compareTo(by);
        });
      if (fit == null || rows.length < 4) {
        return failure('insufficient distributed outline support', {
          'column': entry.key,
          'landmarks': landmarks.length,
          'targets': indices.length,
          'observations': [
            for (final o in landmarks)
              {'index': o.index, 'x': o.observed.x, 'y': o.observed.y},
          ],
        });
      }
      final errors = <double>[];
      for (var fold = 0; fold < 2; fold++) {
        final train = landmarks
            .where((o) => rows.indexOf(o.question) % 2 == fold)
            .toList();
        final test = landmarks.where(
          (o) => rows.indexOf(o.question) % 2 != fold,
        );
        final heldFit = BubbleRegistrationFit.robust(train, tolerance, config);
        if (heldFit == null) {
          return failure('held-out rows lack fitting support');
        }
        // Evaluate all reliable held-out outlines, including proposals rejected
        // by the full fit. No held-out point participates in its fold's fit.
        for (final o in test) {
          errors.add(heldFit.project(o.expected).distanceTo(o.observed));
        }
      }
      errors.sort();
      if (errors.isEmpty ||
          errors[(errors.length * .95).ceil() - 1] >
              radius * config.validationErrorRatio) {
        return failure('held-out registration error exceeds sampling budget', {
          'errors': errors,
        });
      }
      for (final i in indices) {
        if (translations.containsKey(i)) {
          refined[i] = expected[i].withCenter(translations[i]!);
          continue;
        }
        if (!fit.supports(expected[i].center)) {
          return failure('target outside observed support', {
            'index': i,
            'landmarks': [
              for (final o in landmarks)
                {'index': o.index, 'x': o.observed.x, 'y': o.observed.y},
            ],
            'inliers': fit.inliers.map((o) => o.index).toList(),
          });
        }
        final original = expected[i];
        final center = fit.project(original.center);
        if (center.distanceTo(original.center) >
                radius * config.maximumShiftRatio ||
            center.x - original.baselineOuterRadius < 0 ||
            center.y - original.baselineOuterRadius < 0 ||
            center.x + original.baselineOuterRadius > image.size.width ||
            center.y + original.baselineOuterRadius > image.size.height) {
          return failure('corrected ROI outside safe bounds');
        }
        refined[i] = original.withCenter(center);
      }
      diagnostics.add({
        'column': entry.key,
        'method': 'affine',
        'landmarks': landmarks.length,
        'inliers': fit.inliers.length,
        'rejected': landmarks.length - fit.inliers.length,
        'heldOutMean': errors.reduce((a, b) => a + b) / errors.length,
        'heldOutP95': errors[(errors.length * .95).ceil() - 1],
        'heldOutMaximum': errors.last,
        'independentlyValidatedRowTranslationTargets': translations.keys
            .toList(),
      });
    }
    // Association cannot cross a neighboring target's expected Voronoi boundary
    // or bring two printed circles into contact after correction.
    for (var i = 0; i < refined.length; i++) {
      final shift = refined[i].center.distanceTo(expected[i].center);
      final roi = refined[i];
      if (shift > expected[i].printedRadius * config.maximumShiftRatio ||
          roi.center.x - roi.baselineOuterRadius < 0 ||
          roi.center.y - roi.baselineOuterRadius < 0 ||
          roi.center.x + roi.baselineOuterRadius > image.size.width ||
          roi.center.y + roi.baselineOuterRadius > image.size.height) {
        return failure('sampling plan exceeds image or displacement bounds');
      }
      for (var j = 0; j < i; j++) {
        final spacing = expected[i].center.distanceTo(expected[j].center);
        if (shift >= spacing / 2 ||
            refined[j].center.distanceTo(expected[j].center) >= spacing / 2 ||
            refined[i].center.distanceTo(refined[j].center) <
                refined[i].printedRadius + refined[j].printedRadius) {
          return failure('corrected targets violate association or spacing');
        }
      }
    }
    return EngineResult.success(
      BubbleRegistration(
        rois: refined,
        observations: observations,
        regions: diagnostics,
        duration: watch.elapsed,
      ),
    );
  }

  // The simplest supported model for a horizontal row. At least three outlines
  // are needed, every point is checked against a fit that excludes itself,
  // and the translation never extrapolates beyond its observed row segment.
  Map<int, ImagePoint> _rowTranslations(
    List<BubbleCenterObservation> observations,
    List<int> indices,
    List<CanonicalBubbleRoi> expected,
    double tolerance,
  ) {
    final result = <int, ImagePoint>{};
    final rows = <String, List<BubbleCenterObservation>>{};
    for (final o in observations) {
      rows.putIfAbsent(o.question, () => []).add(o);
    }
    for (final row in rows.values) {
      if (row.length < 3 ||
          row.any((p) => (p.expected.y - row.first.expected.y).abs() > 1e-6)) {
        continue;
      }
      final meanX =
          row.map((p) => p.observed.x - p.expected.x).reduce((a, b) => a + b) /
          row.length;
      final meanY =
          row.map((p) => p.observed.y - p.expected.y).reduce((a, b) => a + b) /
          row.length;
      var valid = true;
      for (final p in row) {
        final dx =
            (meanX * row.length - (p.observed.x - p.expected.x)) /
            (row.length - 1);
        final dy =
            (meanY * row.length - (p.observed.y - p.expected.y)) /
            (row.length - 1);
        if (ImagePoint(
              p.expected.x + dx,
              p.expected.y + dy,
            ).distanceTo(p.observed) >
            tolerance) {
          valid = false;
          break;
        }
      }
      if (!valid) continue;
      final left = row.map((p) => p.expected.x).reduce(math.min);
      final right = row.map((p) => p.expected.x).reduce(math.max);
      for (final p in row) {
        if (indices.contains(p.index) &&
            expected[p.index].center.x >= left &&
            expected[p.index].center.x <= right) {
          result[p.index] = ImagePoint(
            p.expected.x + meanX,
            p.expected.y + meanY,
          );
        }
      }
    }
    return result;
  }
}
