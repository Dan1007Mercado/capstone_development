import 'dart:collection';

import 'aruco_alignment_config.dart';
import 'image_geometry.dart';
import 'page_alignment_result.dart';

enum HomographyEstimationStatus { succeeded, failed }

enum HomographyValidationStatus { accepted, rejected, notRun }

/// Immutable diagnostics for one attempted estimator, including rejected and
/// pre-validation failures. It contains only already-computed scalar data.
final class HomographyAttemptDiagnostics {
  HomographyAttemptDiagnostics({
    required this.method,
    required this.estimationStatus,
    required this.validationStatus,
    required this.estimationDuration,
    required this.validationDuration,
    required this.effectiveReprojectionThresholdPixels,
    required this.effectiveRansacThresholdPixels,
    required this.effectiveRejectedCornerThresholdPixels,
    this.estimationFailureCode,
    this.estimationFailureMessage,
    this.homography,
    this.rejectionReason,
    this.meanResidual,
    this.medianResidual,
    this.percentile95Residual,
    this.maximumResidual,
    Iterable<double> cornerResiduals = const [],
    Iterable<bool> inlierMask = const [],
    this.inlierCount = 0,
    Iterable<int> inliersPerMarker = const [],
    this.geometryValidationResult,
    this.numericalValidationResult,
  }) : cornerResiduals = UnmodifiableListView(List.of(cornerResiduals)),
       inlierMask = UnmodifiableListView(List.of(inlierMask)),
       inliersPerMarker = UnmodifiableListView(List.of(inliersPerMarker));

  final AlignmentHomographyMethod method;
  final HomographyEstimationStatus estimationStatus;
  final HomographyValidationStatus validationStatus;
  final String? estimationFailureCode;
  final String? estimationFailureMessage;
  final HomographyMatrix? homography;
  final String? rejectionReason;
  final double? meanResidual;
  final double? medianResidual;
  final double? percentile95Residual;
  final double? maximumResidual;
  final List<double> cornerResiduals;
  final List<bool> inlierMask;
  final int inlierCount;
  final List<int> inliersPerMarker;
  final String? geometryValidationResult;
  final String? numericalValidationResult;
  final double effectiveReprojectionThresholdPixels;
  final double effectiveRansacThresholdPixels;
  final double effectiveRejectedCornerThresholdPixels;
  final Duration estimationDuration;
  final Duration validationDuration;

  Map<String, Object?> toMap() => {
    'method': method.name,
    'estimationStatus': estimationStatus.name,
    'validationStatus': validationStatus.name,
    'estimationFailureCode': estimationFailureCode,
    'estimationFailureMessage': estimationFailureMessage,
    'homography': homography?.values,
    'rejectionReason': rejectionReason,
    'meanResidual': meanResidual,
    'medianResidual': medianResidual,
    'percentile95Residual': percentile95Residual,
    'maximumResidual': maximumResidual,
    'cornerResiduals': cornerResiduals,
    'inlierMask': inlierMask,
    'inlierCount': inlierCount,
    'inliersPerMarker': inliersPerMarker,
    'geometryValidationResult': geometryValidationResult,
    'numericalValidationResult': numericalValidationResult,
    'effectiveReprojectionThresholdPixels':
        effectiveReprojectionThresholdPixels,
    'effectiveRansacThresholdPixels': effectiveRansacThresholdPixels,
    'effectiveRejectedCornerThresholdPixels':
        effectiveRejectedCornerThresholdPixels,
    'estimationDurationMicros': estimationDuration.inMicroseconds,
    'validationDurationMicros': validationDuration.inMicroseconds,
  };

  factory HomographyAttemptDiagnostics.fromMap(
    Map<Object?, Object?> value,
  ) => HomographyAttemptDiagnostics(
    method: AlignmentHomographyMethod.values.byName(value['method'] as String),
    estimationStatus: HomographyEstimationStatus.values.byName(
      value['estimationStatus'] as String,
    ),
    validationStatus: HomographyValidationStatus.values.byName(
      value['validationStatus'] as String,
    ),
    estimationFailureCode: value['estimationFailureCode'] as String?,
    estimationFailureMessage: value['estimationFailureMessage'] as String?,
    homography: value['homography'] == null
        ? null
        : HomographyMatrix(
            (value['homography'] as Iterable).map(
              (item) => (item as num).toDouble(),
            ),
          ),
    rejectionReason: value['rejectionReason'] as String?,
    meanResidual: (value['meanResidual'] as num?)?.toDouble(),
    medianResidual: (value['medianResidual'] as num?)?.toDouble(),
    percentile95Residual: (value['percentile95Residual'] as num?)?.toDouble(),
    maximumResidual: (value['maximumResidual'] as num?)?.toDouble(),
    cornerResiduals: _doubles(value['cornerResiduals']),
    inlierMask: _bools(value['inlierMask']),
    inlierCount: (value['inlierCount'] as num).toInt(),
    inliersPerMarker: _ints(value['inliersPerMarker']),
    geometryValidationResult: value['geometryValidationResult'] as String?,
    numericalValidationResult: value['numericalValidationResult'] as String?,
    effectiveReprojectionThresholdPixels:
        (value['effectiveReprojectionThresholdPixels'] as num).toDouble(),
    effectiveRansacThresholdPixels:
        (value['effectiveRansacThresholdPixels'] as num).toDouble(),
    effectiveRejectedCornerThresholdPixels:
        (value['effectiveRejectedCornerThresholdPixels'] as num).toDouble(),
    estimationDuration: Duration(
      microseconds: (value['estimationDurationMicros'] as num).toInt(),
    ),
    validationDuration: Duration(
      microseconds: (value['validationDurationMicros'] as num).toInt(),
    ),
  );
}

final class AlignmentFailureDiagnostics {
  AlignmentFailureDiagnostics({
    required this.sourceSize,
    required this.detectionSize,
    required this.detectionScaleX,
    required this.detectionScaleY,
    required Iterable<int> expectedMarkerIds,
    required Iterable<int> detectedRegistrationMarkerIds,
    required Iterable<Map<String, Object?>> markerSideLengths,
    required Iterable<Map<String, Object>> detectedCorners,
    required Iterable<Map<String, Object>> expectedCorners,
    required this.selectionPolicy,
    required this.selectionReason,
    required this.fourPoint,
    required this.multiPoint,
    required this.decodeDuration,
    required this.detectionPreparationDuration,
    required this.detectionDuration,
    required this.coordinateRemapDuration,
    required this.pageResolutionDuration,
    required this.correspondenceDuration,
    required this.totalDuration,
  }) : expectedMarkerIds = UnmodifiableListView(List.of(expectedMarkerIds)),
       detectedRegistrationMarkerIds = UnmodifiableListView(
         List.of(detectedRegistrationMarkerIds),
       ),
       markerSideLengths = UnmodifiableListView(List.of(markerSideLengths)),
       detectedCorners = UnmodifiableListView(List.of(detectedCorners)),
       expectedCorners = UnmodifiableListView(List.of(expectedCorners));

  static const detailsKey = 'alignmentFailureDiagnostics';

  final ImageSize sourceSize;
  final ImageSize? detectionSize;
  final double detectionScaleX;
  final double detectionScaleY;
  final List<int> expectedMarkerIds;
  final List<int> detectedRegistrationMarkerIds;
  final List<Map<String, Object?>> markerSideLengths;
  final List<Map<String, Object>> detectedCorners;
  final List<Map<String, Object>> expectedCorners;
  final HomographySelectionPolicy selectionPolicy;
  final String selectionReason;
  final HomographyAttemptDiagnostics fourPoint;
  final HomographyAttemptDiagnostics multiPoint;
  final Duration decodeDuration;
  final Duration detectionPreparationDuration;
  final Duration detectionDuration;
  final Duration coordinateRemapDuration;
  final Duration pageResolutionDuration;
  final Duration correspondenceDuration;
  final Duration totalDuration;

  Map<String, Object?> toMap() => {
    'sourceSize': _sizeMap(sourceSize),
    'detectionSize': detectionSize == null ? null : _sizeMap(detectionSize!),
    'detectionScaleX': detectionScaleX,
    'detectionScaleY': detectionScaleY,
    'expectedMarkerIds': expectedMarkerIds,
    'detectedRegistrationMarkerIds': detectedRegistrationMarkerIds,
    'markerSideLengths': markerSideLengths,
    'detectedCorners': detectedCorners,
    'expectedCorners': expectedCorners,
    'selectionPolicy': selectionPolicy.name,
    'selectionReason': selectionReason,
    'fourPoint': fourPoint.toMap(),
    'multiPoint': multiPoint.toMap(),
    'timingsMicros': {
      'decode': decodeDuration.inMicroseconds,
      'detectionPreparation': detectionPreparationDuration.inMicroseconds,
      'detection': detectionDuration.inMicroseconds,
      'coordinateRemap': coordinateRemapDuration.inMicroseconds,
      'pageResolution': pageResolutionDuration.inMicroseconds,
      'correspondence': correspondenceDuration.inMicroseconds,
      'total': totalDuration.inMicroseconds,
    },
  };

  factory AlignmentFailureDiagnostics.fromMap(Map<Object?, Object?> value) {
    final timings = value['timingsMicros'] as Map;
    return AlignmentFailureDiagnostics(
      sourceSize: _size(value['sourceSize'] as Map),
      detectionSize: value['detectionSize'] == null
          ? null
          : _size(value['detectionSize'] as Map),
      detectionScaleX: (value['detectionScaleX'] as num).toDouble(),
      detectionScaleY: (value['detectionScaleY'] as num).toDouble(),
      expectedMarkerIds: _ints(value['expectedMarkerIds']),
      detectedRegistrationMarkerIds: _ints(
        value['detectedRegistrationMarkerIds'],
      ),
      markerSideLengths: [
        for (final item in value['markerSideLengths'] as Iterable)
          (item as Map).cast<String, Object?>(),
      ],
      detectedCorners: [
        for (final item in value['detectedCorners'] as Iterable)
          (item as Map).cast<String, Object>(),
      ],
      expectedCorners: [
        for (final item in value['expectedCorners'] as Iterable)
          (item as Map).cast<String, Object>(),
      ],
      selectionPolicy: HomographySelectionPolicy.values.byName(
        value['selectionPolicy'] as String,
      ),
      selectionReason: value['selectionReason'] as String,
      fourPoint: HomographyAttemptDiagnostics.fromMap(
        value['fourPoint'] as Map,
      ),
      multiPoint: HomographyAttemptDiagnostics.fromMap(
        value['multiPoint'] as Map,
      ),
      decodeDuration: _duration(timings, 'decode'),
      detectionPreparationDuration: _duration(timings, 'detectionPreparation'),
      detectionDuration: _duration(timings, 'detection'),
      coordinateRemapDuration: _duration(timings, 'coordinateRemap'),
      pageResolutionDuration: _duration(timings, 'pageResolution'),
      correspondenceDuration: _duration(timings, 'correspondence'),
      totalDuration: _duration(timings, 'total'),
    );
  }

  static AlignmentFailureDiagnostics? findInDetails(
    Map<String, Object?> details,
  ) {
    Object? current = details;
    while (current is Map) {
      final raw = current[detailsKey];
      if (raw is Map) return AlignmentFailureDiagnostics.fromMap(raw);
      current = current['causeDetails'];
    }
    return null;
  }
}

Map<String, int> _sizeMap(ImageSize value) => {
  'width': value.width,
  'height': value.height,
};

ImageSize _size(Map value) => ImageSize(
  width: (value['width'] as num).toInt(),
  height: (value['height'] as num).toInt(),
);

Duration _duration(Map value, String key) =>
    Duration(microseconds: (value[key] as num).toInt());

List<double> _doubles(Object? value) => [
  for (final item in value as Iterable) (item as num).toDouble(),
];

List<int> _ints(Object? value) => [
  for (final item in value as Iterable) (item as num).toInt(),
];

List<bool> _bools(Object? value) => [
  for (final item in value as Iterable) item as bool,
];
