---
name: omr-pdf
description: Use when implementing printable OMR generation, PageLayout rendering, bubble drawing, marker drawing, QR/template identity, page dimensions, pagination output, or print geometry validation.
---

# OMR PDF Skill

Read `references/printable-sheet.md`.

PDF Engine consumes PageLayout.

It must not perform another independent layout calculation.

Use physical dimensions.

Initial target is A4 portrait.

Preserve marker boundaries and quiet zones.

Printed bubbles must be consistent.

Prefer scanning reliability over visual decoration.
