# P11.2 final scanner performance and diagnostics

P11.2 keeps the persistent P11.1 final-scanner worker and the 800-pixel P10
live-analysis path. The final scanner decodes the still directly as grayscale,
detects ArUco markers on a configurable 1400-pixel long-edge image, remaps every
detected corner to full-source coordinates, and warps the original
full-resolution grayscale Mat. The worker reuses its detector and uses the
native OpenCV P6 backend; the Dart P6 backend remains the CI/reference oracle.

The portrait 3:4 viewport is display-only. It uniformly center-crops the native
`CameraPreview` and adds an A4/page guide derived from the selected
`PageLayout`. The guide does not mathematically alter camera analysis,
homography, canonical coordinates, or bubble geometry. It only helps the
operator frame a reproducible physical capture.

## Preserved measured baselines

P11 on Infinix X6711:

- capture: about 832.7 ms
- scanner: about 9272.6 ms
- capture-to-result: about 10214.3 ms

P11.1 visible diagnostics on Infinix X6711:

- capture: about 654.7 ms
- decode: about 48.9 ms
- ArUco detection: about 115.6 ms
- correspondence: about 0.4 ms
- homography: about 0.3 ms
- warp: about 244.8 ms

These are baselines, not P11.2 claims. P11.2 performance and recognition gains
remain unverified until measured on the same device and printed fixture.

## Infinix X6711 procedure

Use `debug_output/p11_1_scanner_validation_sheet.pdf`, printed A4 at 100% /
Actual Size.

1. Run `flutter devices`, then `flutter run -d <device-id>`.
2. Open **P11 Camera Scanner Diagnostics**.
3. Verify the portrait preview is natural, unstretched, center-cropped, and the
   PageLayout-derived A4 guide has natural proportions.
4. Confirm source preview remains 1920x1080 (or the device-selected high
   quality), live analysis remains 800x450, markers are `[10, 11, 12, 13]`,
   readiness becomes `ready`, and stability reaches the configured count.
5. Select Page 1, Page 2, and Page 3 in turn. Confirm PageId and question list
   match the physical page before capture.
6. Capture each page. Confirm live analysis resumes while the final worker
   continues, duplicate capture remains blocked, and a retry reuses the worker.
7. For every unexpected blank, ambiguous, or multiple result, expand the
   question and record each bubble's fill ratio, normalized darkness, contrast,
   mean, median, local baseline, foreground count, evidence category, score,
   decision, clipping, quality usability, and baseline foreground ratio.
8. Confirm camera suspend/resume, reset, repeated capture, and disposal remain
   reliable. Observe logcat for BLASTBufferQueue errors, GC churn, blocking GC,
   native crashes, and isolate failures.
9. Confirm high-quality still capture remains unchanged.

## Warm-scan measurements

Record at least five warm scans and calculate minimum, average, and maximum for:

- capture
- source decode
- detection resize/preparation
- ArUco detection
- coordinate remap
- correspondence
- homography
- canonical warp
- preprocessing total, denoise, illumination, threshold, and statistics
- bubble measurement
- classification
- validation/result
- worker total
- isolate overhead
- scanner request
- capture-to-result

Also record source still dimensions, final detection dimensions and scale,
canonical dimensions, expected page, marker IDs, page status, and whether the
worker was cold or reused.

Manual P11.2 Android validation status: **NOT RUN**.
