# P10 camera Android validation

P10 uses the official Flutter `camera` package with CameraX on Android. The
native `CameraPreview` texture remains separate from a throttled image stream.
The requested preview resolution and 60 FPS preference are device targets, not
guarantees. Analysis defaults to 10 FPS and applies its throttle/busy admission
check before copying the native Y plane. Rejected frames return from the camera
callback without materializing a Dart frame. Only one accepted worker task may
be active, so no frame backlog is allowed. Diagnostics publish when accepted
analysis completes rather than rebuilding the Flutter UI for every rejection.

The CameraX plugin copies plane buffers into Dart-owned `CameraImage` data and
closes its native `ImageProxy` after publishing that data. The P10 backend does
not retain `CameraImage` or plane objects: its lazy materializer is valid only
during the synchronous stream callback. Rejected frames return immediately;
accepted frames take one owned luma copy before background-isolate transfer.

The worker isolate uses the luma plane for P5 marker detection, brightness, and
variance-of-Laplacian sharpness. Readiness requires IDs 10-13, sufficient page
and marker size, acceptable perspective and exposure, sharpness, and three
stable observations. Auto-capture requests have a two-second cooldown. Final
capture uses `takePicture`, not a preview screenshot. Automatic focus and
exposure are requested when supported, and flash defaults off.

OEM camera applications may still look cleaner because they can use proprietary
HDR, denoising, and camera tuning unavailable to Flutter applications.

## P10.2 result and P10.3 analysis path

The pre-P10.2 path compacted the full Y plane, created an `image.Image`, encoded
PNG bytes, and decoded those bytes into OpenCV. P10.2 downsamples directly from
the strided Y plane to a compact grayscale buffer with a 960-pixel maximum long
edge, then constructs an OpenCV `CV_8UC1` Mat directly. Native preview and
high-quality still resolutions are unchanged. Detected marker coordinates and
absolute marker sizes are mapped back to source-frame pixels before
readiness/stability logic.

Manual P10.2 validation on the Infinix X6711 succeeded functionally. It used a
1920x1080 preview and 960x540 analysis image, detected IDs 10, 11, 12, and 13,
reached `ready`, and held 5/3 stable frames. Effective analysis was about 4.4
FPS, with a current 92 ms and average 148 ms processing time. Counts were 1679
received, 517 accepted, 517 processed, and 1162 dropped. This showed that the
10 FPS interval was not the only limit: at a 148 ms average, non-overlapping
analysis is capped below 7 FPS even before camera callback alignment.

P10.3 keeps the one-frame/no-backlog policy, makes native dictionary,
parameters, and detector lifetime match the worker isolate, and exposes stage
timings. The provisional default analysis long edge is now 800 pixels; 720,
800, and 960 remain configurable for comparison. Native preview and final still
quality are unchanged. Sharpness continues using the already-downscaled buffer
and a two-pixel sampling stride until physical timing shows it is a meaningful
bottleneck.

Generate the authoritative printable camera sheet from the P5 PageLayout and
P4 PDF renderer:

```text
dart run tool/generate_p10_camera_test_sheet.dart
```

Output: `debug_output/p10_camera_test_sheet.pdf`. Print it on A4 at 100% or
Actual Size; do not use fit-to-page scaling.

## Infinix manual validation

1. Pull/build the P10.3 commit on the Infinix X6711.
2. Run `flutter devices`.
3. Run `flutter run -d <device-id>`.
4. Open **P10 Camera Diagnostics** and use the generated test sheet printed on
   A4 at Actual Size.
5. Confirm the native preview remains responsive and marker IDs 10, 11, 12,
   and 13 are detected.
6. Watch `adb logcat` during normal diagnostics use. Confirm
   `Can't acquire next buffer. Already acquired max frames` is absent or does
   not repeat continuously. Also check for `BLASTBufferQueue` errors,
   large-object GC churn, and blocking GC allocation waits.
7. Record preview resolution, analysis resolution, resize scale, effective
   analysis FPS, current/average total processing time, materialization time,
   preparation/downscale time, sharpness time, ArUco detection time,
   geometry/remap time, and isolate transfer/start wait.
8. Record received, accepted, processed, and dropped frame counts, marker IDs,
   readiness, and stability.
9. Move the phone/page and confirm readiness reports `unstable`.
10. Hold the page still and confirm readiness becomes `ready` after the stable
    frame requirement.
11. Tap **Capture High-Quality Still** and confirm a non-empty still is
    reported.
12. Leave and reopen the screen; confirm the camera is released and reopens.

Manual acceptance requires responsive preview, bounded dropped frames with no
backlog, functioning marker analysis and capture, clean camera/worker disposal,
and no continuous native buffer-acquisition errors on the Infinix X6711.

The 800-pixel analysis limit and sharpness threshold remain provisional pending
physical calibration. Target analysis throughput is approximately 8-10 FPS on
the Infinix X6711 where practical, but the device result and measured bottleneck
must be recorded rather than assumed. Also record preview smoothness, camera
reopen/dispose behavior, and high-quality still capture.

Manual P10.3 Android validation status: **NOT RUN**.
