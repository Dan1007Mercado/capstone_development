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
variance-of-Laplacian sharpness. Readiness requires IDs 10–13, sufficient page
and marker size, acceptable perspective and exposure, sharpness, and three
stable observations. Auto-capture requests have a two-second cooldown. Final
capture uses `takePicture`, not a preview screenshot. Automatic focus and
exposure are requested when supported, and flash defaults off.

OEM camera applications may still look cleaner because they can use proprietary
HDR, denoising, and camera tuning unavailable to Flutter applications.

## P10.2 analysis path

The previous accepted-frame path compacted the full Y plane, created an
`image.Image`, encoded PNG bytes, and then decoded those bytes into OpenCV.
P10.2 downsamples directly from the strided Y plane to a compact grayscale
buffer with a provisional 960-pixel maximum long edge, then constructs an
OpenCV `CV_8UC1` Mat directly. The native preview and high-quality still capture
resolutions are unchanged. Detected marker coordinates and absolute marker
sizes are mapped back to source-frame pixels before readiness/stability logic.

Generate the authoritative printable camera sheet from the P5 PageLayout and
P4 PDF renderer:

```text
dart run tool/generate_p10_camera_test_sheet.dart
```

Output: `debug_output/p10_camera_test_sheet.pdf`. Print it on A4 at 100% or
actual size; do not use fit-to-page scaling.

## Infinix manual validation

1. Pull/build the P10.2 commit on the Infinix X6711.
2. Run `flutter devices`.
3. Run `flutter run -d <device-id>`.
4. Open **P10 Camera Diagnostics** and use the generated test sheet printed on
   A4 at actual size.
5. Confirm the native preview remains responsive and marker IDs 10, 11, 12,
   and 13 are detected.
6. Watch `adb logcat` during normal diagnostics use. Confirm
   `Can't acquire next buffer. Already acquired max frames` is absent or does
   not repeat continuously. Also check for large-object GC churn and blocking
   GC allocation waits.
7. Record preview resolution, effective analysis resolution, resize scale,
   analysis FPS, current/average processing time, and received, accepted,
   processed, and dropped frame counts.
8. Move the phone/page and confirm readiness reports `unstable`.
9. Hold the page still and confirm readiness becomes `ready` after the stable
   frame requirement.
10. Tap **Capture High-Quality Still** and confirm a non-empty still is
    reported.
11. Leave and reopen the screen; confirm the camera is released and reopens.

Manual acceptance requires responsive preview, bounded dropped frames with no
backlog, functioning marker analysis and capture, clean camera/worker disposal,
and no continuous native buffer-acquisition errors on the Infinix X6711.

The 960-pixel analysis limit and sharpness threshold remain provisional pending
physical calibration. Target analysis throughput is approximately 8–15 FPS
where practical, but the device result must be recorded rather than assumed.

Manual P10.2 Android validation status: **NOT RUN**.
