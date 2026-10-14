# Phase 7 Bubble Measurement ExecPlan

### Goal

Measure every `PageLayout.bubbleRegions` entry directly from a
`PreprocessedPage`, preserving order and semantic identity without classifying
responses.

### Existing State

P3 owns deterministic physical/normalized bubble geometry. P6 provides exact
canonical-size normalized grayscale and binary row-major buffers.

### Architectural Constraints

- `PageLayout` remains the only bubble-location authority.
- Centralize physical-to-canonical conversion.
- Sample buffers read-only and never search image content for bubbles.
- Retain grayscale, binary, baseline, and quality evidence for P8.
- Do not aggregate or classify question responses.

### Proposed Design

A canonical mapper converts physical bubble center and diameter using page
pixel scales. The measurement engine samples pixel centers inside an inset
circle and a surrounding annulus, masks known neighboring bubbles and optional
binary foreground from the baseline, estimates paper with an upper percentile,
and returns immutable ordered measurements with structured quality metadata.

### Files

Add recognition measurement domain/application modules, focused contract
documentation, synthetic tests, and this plan.

### Tests

Cover mapping and pixel-center membership, outline exclusion, blank/full/faint
and partial marks, gradients, robust baselines, neighbor masking, identities,
ordering, failures, immutability, and determinism.

### Performance

Read P6 buffers directly with bounded per-bubble sample lists. Do not copy
images or decode encoded data.

### Risks

Inset and baseline defaults are provisional until physical-sheet calibration.
Text near bubbles can contaminate rings, so contamination remains visible in
quality metadata even when robust exclusion succeeds.

### Completion Criteria

Every valid bubble yields deterministic intensity, foreground, local baseline,
darkness, and sampling-quality evidence in layout order with exact identity.
