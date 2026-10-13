---
name: omr-recognition
description: Use when implementing bubble ROI extraction, inner ROI measurement, fill scoring, page calibration, question-level classification, blank/multiple detection, ambiguity handling, or recognition diagnostics.
---

# OMR Recognition Skill

Read:

- references/roi-sampling.md
- references/mark-classification.md

Use expected BubbleRegions from PageLayout.

Do not use contour discovery as the primary method for locating known bubbles.

Measure inner bubble content so the printed outline does not dominate fill scores.

Classification occurs at question level.

Retain intermediate measurements for diagnostics and tests.

Do not introduce ML.
