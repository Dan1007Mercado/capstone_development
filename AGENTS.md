# capstone_Development Engineering Rules

capstone_Development is the engineering repository for developing and validating the TalaanScan dynamic template and Optical Mark Recognition system.

The primary objective of this repository is to build reliable engines.

UI polish is secondary.

This repository is not a prototype.

A feature is not complete merely because it compiles or visually appears to work.

---

## 1. Engineering Priority

Work in this priority order:

1. domain correctness
2. deterministic geometry
3. image-processing correctness
4. recognition accuracy
5. camera reliability
6. performance
7. diagnostics
8. automated testing
9. integration
10. minimal functional UI

Do not spend substantial effort on visual polish until the core engines have been validated.

---

## 2. Core Architecture

The required architecture is:

TemplateDefinition
→ TemplateValidator
→ LayoutEngine
→ PageLayout

PageLayout
→ PDF Engine

PageLayout
→ Scanner Engine

Scanner Engine
→ Template Identification
→ ArUco Detection
→ Alignment Validation
→ Homography
→ Canonical Page
→ Image Preprocessing
→ Bubble ROI Sampling
→ Bubble Measurements
→ Mark Classification
→ Scan Validation
→ ScanResult

Camera Engine supplies images and live alignment information to the scanner pipeline.

---

## 3. Single Source of Geometry

PageLayout is the single source of truth for printable and scanner geometry.

The PDF engine and scanner must consume the same PageLayout.

Never implement separate bubble-position algorithms for printing and recognition.

Never manually duplicate marker positions between modules.

Never rely on UI widget locations as scanner geometry.

---

## 4. Logical and Physical Separation

TemplateDefinition represents survey meaning.

It contains:

- template identity
- template version
- sections
- questions
- options
- question types
- response rules
- ordering

TemplateDefinition must not contain raw camera-pixel coordinates.

LayoutEngine converts semantic structure into deterministic page geometry.

---

## 5. Coordinate Spaces

The system distinguishes:

- logical survey space
- physical page space
- normalized page space
- canonical image space
- raw camera image space

Do not treat these spaces as interchangeable.

Coordinate conversions must be centralized.

Do not scatter conversion formulas throughout the repository.

---

## 6. OMR Layout

TalaanScan owns the printable OMR format.

Therefore the system uses constrained layouts.

Do not implement unrestricted drag-and-drop placement of scannable bubbles.

Researchers may configure:

- questions
- options
- sections
- ordering
- question types

LayoutEngine determines final printable geometry.

---

## 7. ArUco Alignment

The initial OMR system uses four unique ArUco markers:

- top-left
- top-right
- bottom-left
- bottom-right

Marker IDs and dictionary must be configurable.

Do not rely on detector output ordering.

Assign logical location using marker ID.

Do not assume marker center equals page corner.

PageLayout explicitly defines the canonical marker reference points used for homography.

Failure to establish trustworthy alignment must stop normal recognition.

---

## 8. Deterministic Recognition

The initial recognition engine is deterministic.

Do not add:

- YOLO
- CNN models
- neural-network classifiers
- handwriting OCR
- arbitrary AI inference

unless a later architectural decision explicitly approves it.

Do not use "pick the darkest bubble" as the complete classification algorithm.

Recognition states must support:

- MARKED
- BLANK
- MULTIPLE
- AMBIGUOUS
- INVALID

Never silently guess uncertain responses.

---

## 9. Bubble Measurements

Recognition should support deterministic measurements including:

- inner ROI fill ratio
- mean intensity
- local contrast
- background comparison
- page-relative blank baseline
- strongest option score
- second strongest option score
- score separation
- ROI quality
- image quality

The printed bubble outline should not dominate the measured fill score.

Use an inset/inner ROI where appropriate.

---

## 10. Question Semantics

The architecture must support:

- single choice
- multiple choice
- Likert scale
- yes/no
- numeric grid

Non-recognized content may include:

- section headers
- instructions
- human-readable text

Do not attempt unrestricted handwriting recognition.

---

## 11. Camera Engine

Camera preview and computer-vision analysis are separate workloads.

Do not process every preview frame using the full OMR pipeline.

A typical design is:

Camera
→ live preview

Camera
→ throttled analysis frames
→ ArUco tracking
→ quality checks
→ stability tracking
→ auto capture

Final OMR recognition may then use a high-quality captured image.

Do not block Flutter's UI isolate with expensive image processing.

---

## 12. Preview Performance

60 FPS preview is desirable where supported.

It is not mandatory for correct OMR recognition.

Prefer:

1080p60 when genuinely supported
1080p30 when 60 FPS is unavailable
720p60 only when useful
720p30 as fallback

Actual configuration must depend on device capabilities.

Do not sacrifice required recognition detail merely to claim 60 FPS.

---

## 13. Quality Gates

Auto capture should eventually evaluate real measurements such as:

- four required markers visible
- marker geometry valid
- page sufficiently large in frame
- blur acceptable
- exposure acceptable
- perspective acceptable
- page stable
- motion acceptable

Do not simulate production quality checks using timers.

---

## 14. Template Versioning

Published templates are immutable.

Stable concepts include:

- TemplateId
- TemplateVersion
- PageId
- QuestionId
- OptionId

Editing a published template creates a new version.

Printed sheets must eventually identify the exact published version.

---

## 15. Multi-page Support

Architecture must support multiple pages.

Initial physical testing may focus on one-page A4 sheets.

Do not design contracts that make multi-page templates impossible.

---

## 16. Offline Operation

Core OMR processing must work without internet connectivity.

Do not make recognition depend on Firebase, cloud APIs, or external ML services.

Persistence and synchronization are separate concerns.

---

## 17. Backend and Persistence

Domain engines must not depend directly on Firebase.

Persistence belongs behind repositories/interfaces.

Core scanner tests must be runnable without cloud services.

---

## 18. Flutter UI Policy

Flutter UI in this repository is intentionally minimal.

UI exists only to exercise and diagnose the engines.

Do not create:

- decorative dashboards
- chart systems
- complex animations
- elaborate navigation
- marketing pages
- UI redesigns unrelated to engine testing

Prefer simple:

- forms
- buttons
- camera preview
- debug overlays
- diagnostic panels
- result lists
- test controls

Engine quality has priority over visual design.

---

## 19. Diagnostics

Computer-vision development requires visibility.

Development builds should eventually be able to inspect:

- detected marker IDs
- detected marker corners
- canonical warp
- image-quality values
- bubble ROIs
- inner measurement ROIs
- per-bubble scores
- thresholds
- question classification
- alignment confidence
- processing duration

Do not hide useful measurements inside private algorithm code when they can support diagnostics and tests.

---

## 20. Testing

A feature is not complete because it compiles.

Testing should eventually include:

- unit tests
- geometry tests
- layout determinism tests
- PDF geometry tests
- synthetic perspective tests
- blur tests
- brightness tests
- shadow tests
- rotation tests
- known-answer regression images
- physical printed sheets
- multiple printers
- multiple Android devices
- performance measurements

Do not delete valid tests just to make the suite pass.

---

## 21. Performance Measurements

Do not make performance claims without measurement.

Measure where relevant:

- preview FPS
- analysis FPS
- marker detection duration
- homography duration
- preprocessing duration
- ROI sampling duration
- complete scan duration
- memory usage

Optimize only after identifying meaningful bottlenecks.

---

## 22. Codex Token Discipline

Read AGENTS.md once when beginning a task.

Then load only the directly relevant skill.

Do not automatically read every SKILL.md.

Detailed reference documents should only be opened when needed.

Do not repeatedly reread unchanged documentation within the same task.

Do not inspect unrelated modules without a concrete reason.

---

## 23. Development Style

Prefer:

- small cohesive modules
- immutable domain objects
- explicit interfaces
- typed results
- structured errors
- deterministic algorithms
- measurable behavior

Avoid:

- god services
- god widgets
- giant utility files
- hidden global state
- duplicated geometry
- unexplained magic numbers
- fake scanner logic
- premature abstractions
- unnecessary dependencies

---

## 24. Magic Numbers

Computer-vision constants must not be scattered through code.

Thresholds and tunable parameters belong in explicit configuration objects.

Document their meaning.

Where possible, validate them through regression testing.

---

## 25. Completion Reports

Codex implementation reports should normally contain only:

- files changed
- functionality implemented
- tests added
- commands run
- analyze/test results
- blockers
- intentionally deferred work

Avoid verbose narration.
