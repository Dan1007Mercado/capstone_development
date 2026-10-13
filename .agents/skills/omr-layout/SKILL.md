---
name: omr-layout
description: Use for TemplateDefinition geometry, LayoutEngine, PageLayout, physical dimensions, normalized coordinates, marker regions, bubble regions, page flow, pagination, or coordinate conversion.
---

# OMR Layout Skill

When implementing layout read:

- references/coordinate-system.md
- references/page-layout-contract.md
- references/layout-algorithm.md

LayoutEngine must be deterministic.

Identical semantic input and layout configuration must produce equivalent geometry.

Use physical page units for print geometry.

Use normalized coordinates for scanner-independent geometry.

Never use raw camera pixels as template geometry.

Validate all generated geometry.

Prevent collisions with marker exclusion areas.
