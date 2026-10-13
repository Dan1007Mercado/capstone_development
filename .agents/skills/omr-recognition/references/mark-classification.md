# Mark Classification

Classification interprets bubble measurements at question level.

## Required Semantic Outcomes

MARKED

BLANK

MULTIPLE

AMBIGUOUS

INVALID

## Single Choice

Possible result:

one confidently selected bubble
→ MARKED

no sufficiently selected bubble
→ BLANK

multiple sufficiently selected bubbles
→ MULTIPLE

uncertain separation
→ AMBIGUOUS

bad scan/alignment/ROI
→ INVALID

## Multiple Choice

Multiple marks may be valid.

Each option receives a selected/unselected/uncertain interpretation.

Question result may still be AMBIGUOUS if one or more options cannot be reliably classified.

## Evidence

Classification may use:

- absolute fill
- page-relative baseline
- local contrast
- strongest score
- second strongest score
- score difference
- mark threshold
- blank threshold
- quality metrics

## Adaptive Calibration

Page-level statistics may compensate for:

- printer darkness
- paper brightness
- exposure
- pen type
- pencil darkness

Adaptive values must remain bounded and testable.

## Confidence

Do not call a numeric score a probability unless it has actually been probability-calibrated.

Use terms such as:

confidence score

quality score

separation score

when appropriate.

## Rule

Uncertainty is valid information.

Never fabricate an answer to avoid returning AMBIGUOUS.
