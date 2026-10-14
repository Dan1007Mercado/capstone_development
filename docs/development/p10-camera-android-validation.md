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

## Infinix manual validation

1. Run `flutter devices`.
2. Run `flutter run -d <device-id>`.
3. Open **P10 Camera Diagnostics**.
4. Confirm the native preview remains responsive while analysis values update.
5. Watch `adb logcat` during normal diagnostics use. Confirm
   `Can't acquire next buffer. Already acquired max frames` is absent or does
   not repeat continuously.
6. Record preview resolution, analysis FPS, processing time, received frames,
   accepted frames, processed frames, and dropped frames.
7. Show a page with marker IDs 10, 11, 12, and 13; confirm all IDs appear.
8. Move the phone/page and confirm readiness reports `unstable`.
9. Hold the page still and confirm readiness becomes `ready` after the stable
   frame requirement.
10. Tap **Capture High-Quality Still** and confirm a non-empty still is
    reported.
11. Leave and reopen the screen; confirm the camera is released and reopens.

Manual acceptance requires responsive preview, bounded dropped frames with no
backlog, functioning marker analysis and capture, clean camera/worker disposal,
and no continuous native buffer-acquisition errors on the Infinix X6711.

Manual P10.1 Android validation status: **NOT RUN**.
