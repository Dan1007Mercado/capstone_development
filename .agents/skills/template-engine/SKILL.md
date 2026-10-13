---
name: template-engine
description: Use when implementing TemplateDefinition, supported question types, validation, ordering, immutable publishing, template versions, template identity, or logical template editing behavior.
---

# Template Engine Skill

Read:

- references/template-rules.md
- references/template-versioning.md

The Template Engine owns semantics.

It does not decide final bubble pixel positions.

LayoutEngine owns page geometry.

Keep template models independent from Flutter UI.

Do not couple template domain models directly to Firebase.
