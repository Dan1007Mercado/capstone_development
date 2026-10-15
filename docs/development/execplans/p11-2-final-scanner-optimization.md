# P11.2 Final Scanner Optimization ExecPlan

### Goal

Reduce demonstrated final-scanner waste, correct the portrait debug viewfinder,
support exact expected-page selection, and expose mark evidence without changing
PageLayout geometry or recognition semantics.

### Existing State

P11.1 already owns final scanning in a persistent isolate and resumes P10 live
analysis after still bytes are owned. Remaining costs include color decode/warp,
full-still ArUco detection, Dart P6 local-mean passes, repeated detector setup,
an encoded-byte copy, and a full-JPEG diagnostic checksum. The debug workflow
selects page 1 and exposes only question states.

### Architectural Constraints

- Keep PageLayout authoritative for print, overlay, alignment, and bubbles.
- Keep native OpenCV objects inside the persistent final-scanner worker.
- Detect on reduced grayscale, remap to full-source coordinates, and warp the
  original full-resolution grayscale source.
- Preserve P10's 800-pixel live analysis and high-quality still capture.
- Do not change recognition thresholds or semantic rules.
- Keep failures typed and evidence inspectable.

### Proposed Design

Use a reusable `OpenCvArucoVisionBackend` owned by the worker. Decode final
stills as grayscale, resize only the detection Mat to a configurable 1400-pixel
long edge, scale detected corners independently by source/detection width and
height, and retain the source Mat for canonical warp.

Add `OpenCvPreprocessingBackend` with clipped-window local means matching the
Dart oracle, native normalization/threshold/statistics operations, explicit
timings, and deterministic Mat disposal. Return backend statistics so the
application engine does not rescan full pages. Keep the Dart backend unchanged
as the reference and CI fallback/oracle.

Pass transferred JPEG bytes as a read-only view, gate checksum work to injected
protocol tests, and label cold worker startup separately. Add a display-only
orientation-aware center-crop preview and PageLayout guide, exact page-context
selection, and question/bubble evidence diagnostics.

### Files

Changes are limited to P5/P6/P9/P11.1 contracts and adapters, the P11 debug
composition/screen, focused architecture/manual-validation documentation, and
their tests. P10 acquisition configuration and P12 integration remain outside
scope.

### Tests

Cover reduced-detection coordinate remap, grayscale/no-PNG production source,
detector lifetime, no encoded-image copy, checksum gating, native/Dart P6 pixel
and downstream classification parity, timing consistency, preview aspect,
authoritative page guide, exact three-page distribution/context, and all-page
known-answer P6-P9 results.

### Performance

Automated tests establish removed work and timing boundaries only. Preserve the
P11/P11.1 Infinix baselines and require five warm physical scans before claiming
P11.2 improvement or the 2-3 second target.

### Risks

OpenCV border and rounding behavior can differ from Dart; parity tests require
exact binary output and at most one grayscale level before downstream equality.
The Windows host lacks the native OpenCV DLL, so those cases skip explicitly and
remain an Android gate. Display crop must never affect CV coordinates.

### Completion Criteria

All Dart/Flutter gates pass, the full synthetic ten-question fixture classifies
deterministically across its three authoritative pages, and the documented
Infinix validation remains explicitly not run until physical testing occurs.
