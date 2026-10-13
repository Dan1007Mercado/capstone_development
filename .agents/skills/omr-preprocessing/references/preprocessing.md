# Preprocessing Reference

Input:

canonical aligned page image.

Possible pipeline:

canonical image
→ grayscale
→ illumination normalization
→ mild noise reduction
→ thresholding or local normalization
→ measurement-ready representation

## Lighting Problems

Phone captures may contain:

- shadows
- brightness gradients
- hotspots
- low exposure
- white-balance variation

A single global threshold may not perform reliably in all conditions.

Evaluate:

- adaptive thresholding
- local thresholding
- Otsu thresholding
- background normalization
- local contrast measures

through regression tests.

## Noise

Use conservative filtering.

Do not erase light pencil marks.

## Sharpening

Avoid aggressive sharpening unless testing proves it improves measurements.

## Output

Expose diagnostics where useful.

Do not hide the preprocessing result when debugging scan failures.
