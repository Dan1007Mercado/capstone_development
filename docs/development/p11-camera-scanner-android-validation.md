# P11 camera scanner Android validation

P11 connects the P10.3 camera workflow to the P9 offline scanner. Live preview
and low-resolution analysis remain separate from final recognition:

```text
native CameraPreview
  -> throttled Y-plane analysis at an 800-pixel maximum long edge
  -> ArUco tracking and readiness

high-quality takePicture still
  -> owned encoded bytes at the captured resolution
  -> P9 OfflineScannerEngine
  -> alignment, preprocessing, measurement, classification, ScanResult
```

The coordinator stops the image-analysis stream before `takePicture`, keeps the
camera initialized, runs the final scanner with the authoritative template and
`PageLayout`, and restarts analysis after success or failure when the screen is
still active. It permits only one capture/scan operation. P10 supplies the
auto-capture readiness and cooldown signal; P11 adds no stability algorithm.

The Flutter backend reads the temporary plugin `XFile` before returning the
captured bytes and then attempts to delete that temporary file. Deletion is
best effort and never converts an otherwise valid capture into a failure. P11
does not save images to the gallery or retain a captured path between attempts.

P9 currently exposes a synchronous scanner boundary. P11 publishes a visible
`scanning` state and keeps all scanner calls outside widget code, but full P9
work still executes on the calling isolate. Moving a complete native scanner
composition to a dedicated isolate is deferred because native OpenCV ownership
must be designed without sharing native objects across isolates.

## Infinix X6711 procedure

Use `debug_output/p10_camera_test_sheet.pdf`. It is generated through
`TemplateDefinition -> LayoutEngine -> PageLayout -> PdfEngine`, includes the
authoritative marker and yes/no bubble geometry, and must be printed on A4 at
100% / Actual Size. A bubble may be filled by hand for a marked-result check.

1. Run `flutter devices`.
2. Run `flutter run -d <device-id>`.
3. Open **P11 Camera Scanner Diagnostics**.
4. Confirm the native preview opens and remains responsive.
5. Point the camera at the authoritative printed sheet.
6. Confirm detected marker IDs are `[10, 11, 12, 13]`.
7. Wait for readiness `ready` and the required stable-frame count.
8. Allow auto capture or press **Capture & Scan** while ready.
9. Confirm `capturing` and then `scanning` appear.
10. Confirm a real `ScanResult` appears with template ID
    `p5-native-validation`, version `1`, and the displayed page ID.
11. Confirm capture, byte-load, P9 scanner, and total timings are nonzero where
    measurable.
12. Confirm the final scan uses the high-quality still; the displayed live
    analysis resolution must not be treated as scanner input.
13. Press **Retry / Scan Another**, wait for a newly processed readiness
    observation, and scan again.
14. Repeat several scans and confirm no double capture or overlapping scan.
15. Confirm the camera remains reusable without repeated reinitialization.
16. Exercise a failed alignment, then retry successfully without restarting
    the app.
17. Exit and reopen the screen; confirm camera resources release and reopen.
18. Inspect `adb logcat` for continuous `BLASTBufferQueue` errors, native
    crashes, large-object GC churn, blocking GC waits, or repeated camera
    initialization.

Record preview/analysis resolution, analysis FPS, readiness/stability, marker
IDs, capture/load/scanner/total durations, result counts, review-required state,
retry outcome, and any structured error code/message/details.

Manual P11 Android validation status: **NOT RUN**.

P11 subsequently passed its functional Infinix X6711 gate. P11.1 performance
and richer-sheet validation are tracked separately in
`p11-1-final-scanner-android-validation.md`; the original procedure and timing
baseline remain preserved here for history.
