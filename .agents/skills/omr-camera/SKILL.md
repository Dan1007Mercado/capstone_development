---
name: omr-camera
description: Use when implementing camera initialization, rear-camera selection, preview resolution, FPS selection, focus, exposure, frame streaming, frame throttling, scan guidance, stability checks, auto capture, capture quality, or camera lifecycle.
---

# OMR Camera Skill

Read:

- references/camera-pipeline.md
- references/camera-quality.md

The Camera Engine is separate from the OMR Recognition Engine.

Preview performance and analysis performance are separate.

Do not process every preview frame with the full recognition pipeline.

Use real image-quality measurements.

Do not implement simulated document detection.

Handle camera lifecycle correctly.

Prefer engine reliability over UI effects.
