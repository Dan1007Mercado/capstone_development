# P10 camera Android validation

P10 uses the official Flutter `camera` package with CameraX on Android. The
native `CameraPreview` texture remains separate from a throttled image stream.
The requested preview resolution and 60 FPS preference are device targets, not
guarantees. Analysis defaults to 10 FPS and drops frames while one worker task
is active, so no frame backlog is allowed.

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
5. Record preview resolution, analysis FPS, processing time, and dropped frames.
6. Show a page with marker IDs 10, 11, 12, and 13; confirm all IDs appear.
7. Move the phone/page and confirm readiness reports `unstable`.
8. Hold the page still and confirm readiness becomes `ready` after the stable
   frame requirement.
9. Tap **Capture High-Quality Still** and confirm a non-empty still is reported.
10. Leave and reopen the screen; confirm the camera is released and reopens.

Manual acceptance requires responsive preview, bounded dropped frames with no
backlog, functioning capture, and clean camera/worker disposal.
