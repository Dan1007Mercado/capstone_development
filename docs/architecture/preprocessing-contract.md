# Preprocessing Contract

Phase 6 consumes an already aligned `CanonicalPageImage`. It never detects
markers, changes dimensions, consults layout regions, or makes mark decisions.

Pipeline order:

1. Accept exact-size owned canonical grayscale, or decode legacy canonical PNG.
2. Verify the declared dimensions and retain 8-bit grayscale semantics.
3. Optionally apply a conservative local-mean denoise (default kernel 3).
4. Estimate illumination with a large local-mean background (default kernel
   31) and normalize each pixel as `source - background + 220`.
5. Apply adaptive local-mean thresholding (default block 15, C 7).
6. Calculate page statistics and reject only near-uniform input by default.

`GrayImage` stores one byte per pixel from 0 (black) to 255 (white).
`BinaryImage` stores 1 for foreground/ink and 0 for background/paper. Both are
contiguous row-major buffers with no stride or padding: `index = y * width + x`.
All public buffers are unmodifiable views over defensively copied storage.

The defaults in `PreprocessingConfig` are provisional until physical-scan
calibration. The Dart backend remains the reference/CI oracle. The production
final-scanner worker uses an OpenCV backend with bounded parity against the Dart
implementation and disposes every native Mat before returning Dart-owned
buffers. Low contrast
is evaluated from the decoded grayscale standard deviation and returns
`PREPROCESS_LOW_CONTRAST`; normal pages are not rejected based on printed-text
or foreground ratios.

Before Phase 10 camera integration, the P5 native OpenCV integration tests must
run successfully on at least one supported target environment.
