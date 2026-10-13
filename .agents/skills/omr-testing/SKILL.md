---
name: omr-testing
description: Use when creating unit tests, geometry tests, synthetic image tests, regression datasets, physical scan validation, recognition accuracy measurements, performance benchmarks, or scanner acceptance criteria.
---

# OMR Testing Skill

Read:

- references/validation-matrix.md
- references/regression-testing.md

Tests are part of the engine design.

Do not wait until all engines are finished before adding tests.

Prefer deterministic fixtures.

Preserve known failing images as regression cases after bugs are understood.

Measure acceptance accuracy separately from rejection rate.
