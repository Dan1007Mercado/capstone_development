---
name: omr-preprocessing
description: Use when implementing grayscale conversion, illumination correction, denoising, thresholding, contrast normalization, or preparation of canonical scan images for measurement.
---

# OMR Preprocessing Skill

Read `references/preprocessing.md`.

Preprocessing exists to improve measurement repeatability.

Do not add transformations merely because they look visually better.

Each preprocessing step should eventually be justified by regression results.

Keep parameters configurable.

Do not scatter thresholds or kernel sizes throughout scanner code.
