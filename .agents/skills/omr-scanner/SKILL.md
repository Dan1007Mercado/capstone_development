---
name: omr-scanner
description: Use when connecting template identification, alignment, canonical page generation, preprocessing, recognition, validation, diagnostics, or producing final ScanResult objects.
---

# OMR Scanner Skill

Read `references/scanner-orchestration.md`.

Scanner Engine orchestrates other engines.

It should not reimplement their algorithms.

Use typed pipeline results.

Stop processing when a critical stage fails.

Expose diagnostics.

Do not hide failure behind an empty or fabricated response.
