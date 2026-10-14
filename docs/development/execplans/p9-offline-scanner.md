# Phase 9 Offline Scanner ExecPlan

### Goal

Connect one encoded page image and its supplied `TemplateDefinition` and
`PageLayout` through alignment, preprocessing, measurement, classification,
and an immutable `ScanResult` without camera, network, or persistence work.

### Existing State

Phases 5–8 expose typed `EngineResult` boundaries for ArUco alignment,
preprocessing, bubble measurement, and mark classification. `PageLayout` owns
all scanner geometry and P8 preserves its question order.

### Architectural Constraints

- Orchestration must not duplicate child-engine algorithms or geometry.
- Every stage is mandatory and failure stops all downstream work.
- The supplied template and layout must be checked before image processing.
- Required blanks are submission-level review findings; P8 mark states remain
  unchanged.
- Scanner tests must not require native OpenCV.

### Proposed Design

Add narrow injectable stage ports with adapters for the accepted P5–P8
engines. `OfflineScannerEngine` validates identity, executes stages in order,
wraps child failures while retaining their code/message/details, validates the
final page contract, and derives page state, structured review reasons,
question IDs, counts, and stage timings. A composition helper wires the real
engines while leaving native backend choice to the caller.

### Files

- `lib/engines/scanner/domain/`: config, ports, and immutable results
- `lib/engines/scanner/application/`: orchestration
- `lib/engines/scanner/infrastructure/`: P5–P8 adapters/composition
- `test/engines/scanner/`: orchestration and pure-pipeline coverage
- focused architecture documentation

### Tests

Use fake stages for ordering, fail-fast behavior, identity validation, page
state priority, ordering, immutability, diagnostics, determinism, and source
byte safety. Use fake P5 with real P6–P8 for marked, blank, double-mark, and
faint-mark synthetic canonical images where practical.

### Performance

Record total and per-stage elapsed durations. Timings are diagnostic and are
excluded from semantic comparisons.

### Risks

- Fake stage output could violate page identity or ordering; validate before
  creating a result.
- P5 native availability varies by host; keep native execution outside the CI
  requirement and preserve the pre-P10 native gate.
- Synthetic marks may not represent physical print/camera behavior; retain
  physical and regression-image validation for later gates.

### Completion Criteria

One static image deterministically reaches `ScanResult`, child errors retain
their causes, page review rules are explicit, orchestration tests run without
OpenCV, and formatting, analysis, and the full test suite pass.
