import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/camera/application/document_tracker.dart';
import 'package:capstone_development/engines/camera/domain/live_frame_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('smooths physical paper edges for visual continuity', () {
    final tracker = DocumentTracker();
    tracker.update(_document(offset: 0));

    final update = tracker.update(_document(offset: 10));

    expect(update.phase, DocumentTrackingPhase.tracking);
    expect(update.isFresh, isTrue);
    expect(update.document!.geometry.corners.first.x, closeTo(6.5, 0.001));
  });

  test('retains short visual grace without inventing fresh detection', () {
    final tracker = DocumentTracker();
    tracker.update(_document(offset: 0));

    final throttled = tracker.retain();
    final missed = tracker.update(null);

    expect(throttled.phase, DocumentTrackingPhase.tracking);
    expect(throttled.isFresh, isFalse);
    expect(missed.phase, DocumentTrackingPhase.temporarilyLost);
    expect(missed.document, isNotNull);
  });

  test('drops paper visualization after bounded misses', () {
    final tracker = DocumentTracker();
    tracker.update(_document(offset: 0));

    for (var index = 0; index < 3; index++) {
      expect(tracker.update(null).document, isNotNull);
    }
    expect(tracker.update(null).document, isNull);
  });
}

DetectedDocument _document({required double offset}) => DetectedDocument(
  geometry: DocumentGeometry(
    corners: [
      ImagePoint(offset, 0),
      ImagePoint(100 + offset, 0),
      ImagePoint(100 + offset, 100),
      ImagePoint(offset, 100),
    ],
    areaRatio: 0.5,
    centroid: ImagePoint(50 + offset, 50),
    perspectiveRatio: 1,
  ),
  confidence: 0.8,
);
