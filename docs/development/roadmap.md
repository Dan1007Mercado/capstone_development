# Engine Development Roadmap

Development must be incremental.

Do not build all engines simultaneously.

## Phase 0 — Foundation

Establish architecture, skills, documentation, directories, and testing contracts.

No real OMR implementation.

## Phase 1 — Domain and Geometry Primitives

Implement:

- IDs
- physical units
- normalized geometry
- canonical page specification
- validation infrastructure

No Flutter UI beyond required compilation.

## Phase 2 — Template Domain

Implement:

- TemplateDefinition
- sections
- question types
- options
- validation
- immutable model behavior

No visual template builder yet.

## Phase 3 — Layout Engine

Implement:

TemplateDefinition
→ LayoutEngine
→ PageLayout

Test:

- determinism
- marker zones
- bubble coordinates
- page overflow
- pagination
- normalized geometry

This phase is critical.

## Phase 4 — PDF Engine

Render PageLayout exactly.

Implement:

- A4 output
- bubbles
- labels
- marker geometry
- QR/template identity placeholder or implementation
- multipage output where supported

Validate printed geometry.

## Phase 5 — ArUco Engine

Start using static test images before camera integration.

Implement:

- marker generation if needed
- marker detection
- marker ID mapping
- alignment validation
- homography
- canonical page generation
- diagnostics

Do not introduce camera complexity yet.

## Phase 6 — Preprocessing Engine

Implement and compare:

- grayscale
- illumination correction
- thresholding approaches
- conservative denoising

Use test images.

Keep the pipeline configurable.

## Phase 7 — Bubble Measurement Engine

Implement:

- PageLayout ROI mapping
- inner ROI
- fill measurements
- local contrast
- diagnostics

Do not perform final question classification prematurely.

## Phase 8 — Mark Classification Engine

Implement:

- blank detection
- single mark
- multiple mark
- ambiguity
- invalid measurement
- adaptive page calibration

Use known-answer regression images.

## Phase 9 — Full Offline Scanner Engine

Connect:

layout
+ ArUco
+ canonicalization
+ preprocessing
+ measurements
+ classification

Input:

image file

Output:

ScanResult

Still no live camera dependency required.

## Phase 10 — Camera Engine

Implement separately:

- rear camera selection
- preview
- resolution selection
- focus/exposure
- analysis stream
- ArUco live tracking
- quality metrics
- stability
- auto capture
- lifecycle
- actual FPS measurements

## Phase 11 — Camera + Scanner Integration

Camera captures stable page.

Full Scanner Engine processes capture.

Add minimal functional scanner screen.

## Phase 12 — Template Builder

Only after domain/layout are stable.

Build a functional template editor around TemplateDefinition.

No elaborate UI.

Prioritize correctness.

## Phase 13 — Publishing and Versioning

Implement immutable template publication.

Add machine-readable template/page identity.

## Phase 14 — Batch Scanning

Implement:

- scan session
- duplicate prevention
- sequential captures
- result accumulation
- review queue

## Phase 15 — Physical Validation

Build a real printed-sheet dataset.

Test:

- different marks
- lighting
- printers
- angles
- devices

Tune configuration using measured results.

## Phase 16 — Prototype Integration

Only after engines are validated should this repository's engine architecture be integrated into the existing TalaanScan prototype/application.
