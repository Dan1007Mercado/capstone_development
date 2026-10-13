# Bubble ROI Sampling

Bubble positions are already known from PageLayout.

For each BubbleRegion:

1. map normalized geometry into canonical image pixels
2. validate ROI bounds
3. extract outer ROI
4. calculate an inner measurement ROI
5. exclude most printed outline pixels
6. calculate measurements

Potential measurements:

- dark pixel ratio
- average intensity
- median intensity
- local foreground percentage
- center darkness
- local background difference
- contrast
- edge contamination
- ROI quality

## Inner ROI

An empty printed bubble is not visually blank because its outline is dark.

Therefore full-circle darkness alone is insufficient.

Use an inset measurement region.

The inset ratio must be configurable and later calibrated using actual printed sheets.

## Diagnostics

A development/debug mode should eventually display:

- expected ROI
- measured inner ROI
- score
- classification
- threshold
- quality indicators
