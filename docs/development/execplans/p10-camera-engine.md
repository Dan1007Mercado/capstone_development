# P10 Camera Engine ExecPlan

## Goal

Provide a platform-neutral camera engine with a native preview path, bounded
background ArUco/quality analysis, deterministic capture readiness, and
high-quality still capture, plus a minimal Android diagnostics screen.

## Existing State

P5 exposes stable marker IDs, detected corners, and structured OpenCV errors.
P9 accepts encoded still-image bytes but is intentionally not invoked by P10.
The app currently contains only debug access to the P5 native harness.

## Architectural Constraints

- Preview rendering and analysis frames remain separate.
- No heavy computer vision runs on the UI isolate.
- At most one analysis task is active; excess frames are dropped.
- Marker roles remain the P5 IDs 10, 11, 12, and 13.
- Readiness uses measured geometry, brightness, sharpness, and stability.
- Final capture uses the camera still-capture API, not an analysis frame.
- P10 does not run preprocessing, recognition, or P9 scanning.

## Proposed Design

`CameraEngine` owns lifecycle, throttling, backpressure, stability history,
diagnostics, readiness, and auto-capture requests. `CameraBackend` abstracts
camera initialization, image streaming, and still capture. The Flutter camera
adapter exposes a native preview controller only to the diagnostics widget.
A persistent worker isolate downsamples accepted luma frames into a compact
grayscale buffer, constructs a native OpenCV grayscale Mat directly, and runs
the shared P5 ArUco detector plus lightweight quality measurements. Detected
geometry is remapped to source-frame coordinates before it reaches the engine.
Fake backends and analyzers drive deterministic CI tests.

The official Flutter `camera` package is selected. Native preview uses
`CameraPreview`; streamed analysis frames use latest-frame delivery; stills use
`takePicture`. Resolution and FPS are requested preferences and remain device
dependent. Automatic focus/exposure and flash-off are requested when supported.

## Files

- `lib/engines/camera/domain/`
- `lib/engines/camera/application/camera_engine.dart`
- `lib/engines/camera/infrastructure/`
- `lib/engines/aruco/infrastructure/opencv_aruco_detector.dart`
- `lib/debug/p10_camera_diagnostics_screen.dart`
- `lib/debug/p10_camera_test_sheet.dart`
- `tool/generate_p10_camera_test_sheet.dart`
- `debug_output/p10_camera_test_sheet.pdf`
- `test/engines/camera/`
- `docs/development/p10-camera-android-validation.md`
- `lib/main.dart`, `pubspec.yaml`, and resolved dependency metadata

## Tests

Use fake camera and analyzer implementations for lifecycle, failures,
throttling, busy-frame drops, readiness reasons, stability, cooldown, capture,
disposal, deterministic sequences, diagnostics counters, analysis resizing,
source-coordinate remapping, and printable marker geometry. Hardware and
native camera permission are not required in CI.

## Performance

Default analysis target is 10 FPS. The preview is never reconstructed from
analysis frames. One worker task is allowed at a time, with drop-while-busy and
no pending frame queue. Diagnostics expose processed/dropped frames, estimated
analysis FPS, and average analysis duration. The native preview resolution is
unchanged while analysis defaults to a maximum 960-pixel long edge. The former
accepted-frame path allocated a compact full-size buffer, image package object,
PNG bytes, and an OpenCV-decoded Mat. P10.2 keeps one compact/downscaled
analysis buffer before direct Mat construction. Device performance and GC
behavior remain manual measurements.

## Risks

- Device resolution/FPS selection may fall back below requested values.
- Camera image row/pixel strides vary by Android device.
- Native OpenCV availability must be validated in the worker isolate.
- OEM camera applications may provide proprietary HDR/noise reduction that the
  Flutter preview does not reproduce.
- Application lifecycle transitions can invalidate plugin controllers.

## Completion Criteria

The engine initializes, streams with deterministic throttling/backpressure,
analyzes outside the UI isolate, exposes measured readiness and auto-capture
signals, captures a still through the backend, disposes all resources, passes
fake-backed CI tests, and has a usable Android diagnostics path.
