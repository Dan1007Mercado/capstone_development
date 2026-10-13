# Phase 4 PDF Engine ExecPlan

### Goal

Render `TemplateDefinition` plus `LayoutDocument` into valid printable PDF bytes without recalculating page geometry.

### Existing State

The template domain owns semantic text and IDs. `LayoutEngine` produces immutable physical and normalized geometry for pages, markers, identity, headers, sections, questions, and bubbles.

### Architectural Constraints

- `PageLayout` remains the only source of print/scanner geometry.
- The renderer may only convert millimeters to PDF points.
- Template/layout identity must match before rendering.
- Failures cross the public boundary as `EngineResult` / `EngineError`.
- No Flutter widgets, native CV, scanner, or persistence dependencies.

### Proposed Design

- Add a centralized physical-to-PDF converter.
- Add a stable `TS1` page-identity codec.
- Encode OpenCV `DICT_4X4_50` markers in pure Dart.
- Build immutable render plans directly from template semantics and `PageLayout` geometry.
- Paint those plans with the pure-Dart `pdf` package.

### Files

Add PDF domain/application/infrastructure modules, focused tests, protocol documentation, and the minimum `pdf` dependency.

### Tests

Verify conversion, identity, markers, semantic mappings, exact copied geometry, page counts, mismatch failures, immutability, diagnostics defaults, and parseable non-empty output.

### Performance

No performance claim. Vector markers and bubbles avoid large raster allocations.

### Risks

PDF coordinate conventions, accidental widget overflow, marker-bit compatibility, and secondary geometry calculations.

### Completion Criteria

Single- and multi-page layouts render successfully with exact PageLayout-derived regions, stable machine identity, and passing format/analyze/test gates.
