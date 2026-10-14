# Phase 8 Mark Classification ExecPlan

### Goal

Transform ordered P7 measurements into deterministic question-level mark
semantics for every supported question type without reading image data.

### Existing State

P7 provides identity-preserving fill, darkness, baseline, clipping, and sample
quality evidence for every `PageLayout` bubble. No interpretation exists.

### Architectural Constraints

- Match measurements to layout by semantic identity, never position or index.
- Use multiple evidence signals and retain their components in diagnostics.
- Preserve uncertainty; never select an argmax without absolute evidence.
- Keep thresholds centralized and provisional.
- Do not implement scanner orchestration or access image buffers.

### Proposed Design

A pure evidence evaluator produces transparent fill/darkness/contrast components
and quality-aware bubble categories. The application engine validates exact
template/layout/measurement structure, restores layout order, then applies
exclusive, multiple-choice, and numeric-column rules. Exclusive decisions use
absolute evidence plus top-versus-second separation.

### Files

Add classification domain/application modules, focused contract documentation,
synthetic measurement tests, and this plan.

### Tests

Cover blank/marked/multiple/ambiguous/invalid outcomes, signal conflicts,
quality, all question types, numeric columns and leading zeros, structural
matching, ordering, determinism, immutability, and threshold boundaries.

### Performance

Operate on small measurement collections with no image work. Group and match
identities in linear time, with only small per-question score sorts.

### Risks

Defaults are engineering starting points, not production calibration. Physical
scan datasets must tune thresholds later without changing state semantics.

### Completion Criteria

Valid P7 evidence deterministically yields all five required states across all
supported question types, with raw component diagnostics and no silent guesses.
