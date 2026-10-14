# Phase 6 Preprocessing ExecPlan

### Goal

Convert an exact-size `CanonicalPageImage` into deterministic, pixel-aligned
grayscale, normalized grayscale, and adaptive binary buffers with diagnostics
and structured quality failures.

### Existing State

P5 returns a defensively copied canonical PNG and declared `ImageSize`. No
page-wide preprocessing or measurement-ready pixel buffer exists.

### Architectural Constraints

- Preserve the canonical dimensions; never resize, align, or re-layout.
- Keep codec/backend details outside domain models.
- Return row-major Dart buffers with explicit polarity.
- Keep all tunables in one immutable configuration object.
- Do not inspect bubble regions or classify marks.

### Proposed Design

An application engine validates bytes and configuration, invokes an injected
backend, verifies its structural contract, calculates page statistics, applies
a conservative low-contrast gate, and returns `PreprocessedPage`. The initial
pure-Dart backend decodes PNG once, converts to 8-bit luminance, optionally
applies a small mean denoise, subtracts a large local background estimate, and
creates an adaptive local-mean binary image.

### Files

Add preprocessing domain/application/infrastructure modules, focused contract
documentation, synthetic tests, and this plan. Update the roadmap with the P5
native-validation gate required before P10.

### Tests

Cover buffers and indexing, config validation, input failures, dimensions,
determinism, statistics, binary polarity, low-contrast rejection, gradients,
faint/dark mark preservation, noise, and input immutability.

### Performance

Decode once and use linear-time summed-area local means. Record processing
duration as a diagnostic only; no performance claim is made in this phase.

### Risks

Provisional kernels and thresholds require later calibration against physical
scans. Conservative smoothing and normalization must not erase faint marks.

### Completion Criteria

Valid canonical PNG input produces exact-size measurement-ready buffers and
diagnostics deterministically; invalid bytes, dimensions, configuration, and
near-uniform pages return stable structured failures.
