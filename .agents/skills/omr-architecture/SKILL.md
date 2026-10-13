---
name: omr-architecture
description: Use when modifying engine boundaries, cross-engine contracts, domain interfaces, dependency direction, scanner orchestration, or overall TalaanScan OMR architecture.
---

# OMR Architecture Skill

Read `references/architecture.md` when a task affects multiple engines.

Preserve:

TemplateDefinition
→ TemplateValidator
→ LayoutEngine
→ PageLayout

PageLayout
→ PDF Engine

PageLayout
→ Scanner Engine

Scanner
→ Alignment
→ Preprocessing
→ Sampling
→ Classification
→ Validation

Do not allow PDF and scanner modules to create independent geometry.

Keep Flutter presentation outside the computer-vision domain.

Keep cloud persistence outside the core scanner pipeline.

Use immutable values and typed results where practical.

Do not introduce machine learning without an explicit architectural decision.
