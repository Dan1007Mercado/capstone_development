# Phase 3 Layout Engine ExecPlan

### Goal

Transform a validated `TemplateDefinition` into a deterministic, multi-page
`LayoutDocument` whose physical and normalized geometry is authoritative for
future PDF rendering and scanning.

### Existing State

Phase 1 provides typed IDs, geometry, conversion, errors, and results. Phase 2
provides immutable template semantics and `TemplateValidator`. No layout
contracts or placement engine exist yet.

### Architectural Constraints

- `PageLayout` is the single source of printable and scanner geometry.
- Physical geometry uses millimeters; normalized geometry uses
  `GeometryConverter`.
- Placement is constrained, deterministic, platform-independent, and pure Dart.
- Invalid templates/configuration and unplaceable questions return structured
  failures.

### Proposed Design

Add immutable layout/configuration contracts and a flow-based `LayoutEngine`.
Each page reserves markers, identity/header space, and safe content bounds.
Questions remain whole during pagination; numeric-grid cells use deterministic
column-major ordering. Marker registration uses each marker's inner corner.

### Files

- `lib/engines/layout/domain/`
- `lib/engines/layout/application/layout_engine.dart`
- `test/engines/layout/`
- `docs/architecture/page-layout-contract.md`

### Tests

Verify determinism, marker/normalized geometry, semantic bubble mapping,
collision-free placement, pagination, failure codes, ordering, and immutability.

### Performance

Placement is linear in sections, questions, and generated bubbles. No benchmark
is required until representative large templates exist.

### Risks

- Provisional dimensions may require physical print/scan calibration.
- Very large questions must fail rather than clip.
- Pagination must preserve semantic order and stable page identity.

### Completion Criteria

Valid templates produce structurally equal `LayoutDocument` values with all
scanner-relevant geometry in physical and normalized forms; invalid or
unplaceable input returns a structured `EngineError`; all tests and analysis
pass.
