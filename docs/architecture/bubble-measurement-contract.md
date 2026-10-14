# Bubble Measurement Contract

Phase 7 consumes `PageLayout` and `PreprocessedPage`. It does not relocate,
detect, or classify bubbles. Physical centers map with the page's independent
pixels-per-millimeter scales. A physical circular radius maps using the smaller
scale so the canonical sampling region remains circular and inside the printed
geometry.

The default interior radius is 0.68 of the printed radius. Integer pixels are
included when their centers `(x + 0.5, y + 0.5)` satisfy the circle equation.
This excludes most printed outline pixels without coordinate rounding.

The local paper baseline is an annulus from 1.25 to 2.0 printed radii. Pixels
inside other known bubble circles are masked. Binary foreground is excluded by
default, then the 70th percentile of remaining normalized grayscale values is
used as a robust nearby-paper estimate. Foreground contamination before
exclusion remains in quality diagnostics.

Binary fill ratio is `foreground interior pixels / sampled interior pixels`.
Grayscale darkness contrast is `local baseline - interior mean`; normalized
darkness divides that value by `max(local baseline, epsilon)`. These are raw
measurement signals, not classification scores or probabilities.
