# Preprocessing Contract

Phase 6 consumes an already aligned `CanonicalPageImage`. It never detects
markers, changes dimensions, consults layout regions, or makes mark decisions.

Pipeline order:

1. Decode the canonical PNG once and verify its declared dimensions.
2. Convert to 8-bit standard image-library luminance.
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
calibration. Native resources are not retained: the initial codec backend is
pure Dart, and every returned page owns Dart-managed buffers only. Low contrast
is evaluated from the decoded grayscale standard deviation and returns
`PREPROCESS_LOW_CONTRAST`; normal pages are not rejected based on printed-text
or foreground ratios.

Before Phase 10 camera integration, the P5 native OpenCV integration tests must
run successfully on at least one supported target environment.
