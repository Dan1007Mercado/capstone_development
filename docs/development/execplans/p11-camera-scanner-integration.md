# P11 Camera Scanner Integration ExecPlan

## Goal

Connect the accepted P10.3 camera engine to the accepted P9 offline scanner so
that a readiness-gated high-quality still produces a real `ScanResult`, with
typed workflow state, retry/reset behavior, diagnostics, and a minimal Android
debug screen.

## Existing State

P10.3 owns native preview, throttled luma analysis, readiness, high-quality
still capture, and camera lifecycle. P9 owns alignment, canonicalization,
preprocessing, bubble measurement, classification, validation, and
`ScanResult`. `PageLayout` is already the sole scanner geometry contract.

## Architectural Constraints

- Live analysis frames never enter the final scanner pipeline.
- P11 coordinates engines but implements no CV, geometry, or thresholds.
- The supplied template, version, page ID, and `PageLayout` remain
  authoritative.
- Only one capture/scan operation may run at a time.
- Camera analysis is stopped for high-quality capture and final scanning, then
  restarted without camera reinitialization when the workflow remains active.
- Scanner failures remain structured and never become empty successful results.
- Widget code consumes coordinator state and does not own scanner stages.

## Proposed Design

`CameraScannerCoordinator` owns a narrow camera port, captured-byte loader, and
offline-scanner port. It maps P10 state into a typed P11 state machine, gates
normal capture on P10 readiness, consumes P10 auto-capture requests once per
armed attempt, measures capture/load/scan/total durations, and supports reset,
suspend/resume, and idempotent disposal.
Reset clears the prior result/error and requires a newly processed P10 analysis
observation before normal capture can become ready again, so stale published
readiness cannot trigger a second scan.

The Flutter composition adapts a `CameraEngine` and the real P9
`OfflineScannerEngine`. `FlutterCameraBackend` reads the plugin `XFile` at its
original resolution and best-effort deletes the temporary file only after the
bytes are owned. P11 does not save captures to the gallery.

At P11 completion, the P9 native OpenCV path remained synchronous on the main
isolate. P11.1 supersedes that runtime limitation with a dedicated persistent
worker; this paragraph is retained as the accepted P11 baseline.

## Files

- `lib/application/camera_scanner/`
- `lib/debug/p11_camera_scanner_composition.dart`
- `lib/debug/p11_camera_scanner_screen.dart`
- `lib/engines/camera/infrastructure/flutter_camera_backend.dart`
- `lib/main.dart`
- `test/application/camera_scanner/`
- `test/debug/p11_camera_scanner_screen_test.dart`
- this ExecPlan

## Tests

Fake camera, byte-loader, and scanner ports cover gating, single-flight
capture, auto-capture latching, structured failures, reset/retry, disposal, and
valid state transitions without Android, native OpenCV, or filesystem access.
An orchestration integration test uses fake alignment with the real P6-P9
pipeline and a synthetic canonical page. A widget test verifies the diagnostics
panel consumes typed state without scanner logic.

## Performance

P11 records capture, byte-load, scanner, and total capture-to-result durations
separately from P10 live-analysis timings. It does not alter the 800-pixel live
analysis default or any camera/recognition thresholds.

## Risks

- Full P9 processing currently executes synchronously after the application
  boundary yields; a dedicated native-scanner isolate requires a later focused
  design.
- Physical still orientation and native OpenCV availability require Android
  validation.
- Temporary-file deletion is best effort because platform ownership can vary.

## Completion Criteria

One ready camera event can produce exactly one high-quality capture and one P9
scan; failures remain structured; retry and repeated scans reuse the camera;
all automated tests and repository validation pass; the Android gate remains
explicitly manual.
