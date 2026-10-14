# Mark Classification Contract

Phase 8 consumes only `BubbleMeasurementSet`, `PageLayout`, and template
semantics. Measurements are matched by full option or numeric-cell identity;
missing, duplicate, or unknown targets are structural engine failures.

Each usable bubble receives three bounded evidence components: binary fill,
normalized grayscale darkness, and raw local darkness contrast. The default
combined score weights are 0.40, 0.35, and 0.25. A mark candidate must satisfy
at least two independent minimum signals, so one strong but contradictory
signal cannot create a confident mark. All component values and categories are
retained in `BubbleMarkDecision`.

Exclusive questions require an absolute candidate and a default 0.12 score gap
from the next competitor. Two independently strong marks mean `MULTIPLE`;
close or conflicting evidence means `AMBIGUOUS`. Multiple-choice questions may
return several strong selections normally. Numeric grids apply exclusive rules
per column and preserve every column, including leading zero selections.

Severely deficient sample quality produces `INVALID`. Recoverable baseline or
contamination concerns produce uncertainty instead of a guess. All defaults in
`MarkClassificationConfig` are provisional pending physical-sheet calibration;
scores are evidence scores, not probabilities or accuracy claims.
