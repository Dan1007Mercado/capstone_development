---
name: omr-aruco
description: Use when implementing ArUco marker generation, detection, marker-ID mapping, corner extraction, geometry validation, homography, perspective correction, or canonical page alignment.
---

# OMR ArUco Skill

Read:

- references/aruco-homography.md
- references/alignment-quality.md

Use four unique markers.

Resolve marker role by ID.

Do not rely on detector array order.

Use PageLayout-defined canonical registration points.

Return structured alignment failures.

Do not classify bubbles when alignment is invalid.
