# capstone_Development Execution Plans

Large engine changes use an ExecPlan.

Required for:

- LayoutEngine implementation or major redesign
- PDF geometry engine
- native/OpenCV integration
- ArUco alignment engine
- preprocessing engine
- recognition engine
- camera engine
- scanner orchestration
- template publishing/versioning
- major persistence architecture
- cross-engine refactors

Not required for:

- small model additions
- isolated test fixes
- localized validation
- documentation updates
- minor bug fixes

## ExecPlan Template

### Goal

State the concrete outcome.

### Existing State

Describe only relevant existing code.

### Architectural Constraints

List rules from AGENTS.md that must remain true.

### Proposed Design

Explain module responsibilities and data flow.

### Files

List files expected to change.

### Tests

Define how behavior will be verified.

### Performance

Specify measurements if performance-sensitive.

### Risks

Identify realistic failure modes.

### Completion Criteria

Describe what must demonstrably work.

## Rule

An ExecPlan is a working engineering document.

Update it if implementation discoveries invalidate important assumptions.

Do not preserve a bad plan merely because it was written first.
