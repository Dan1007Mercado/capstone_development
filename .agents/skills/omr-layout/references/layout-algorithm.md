# Layout Algorithm Reference

The layout engine should implement constrained flow layout.

## Inputs

TemplateDefinition

Page specification

Layout configuration

## Responsibilities

Calculate:

- printable region
- marker exclusion zones
- identity/header area
- section layout
- question placement
- option placement
- bubble placement
- vertical spacing
- page overflow
- pagination

## Constraints

Do not place content:

- outside printable area
- inside marker exclusion zones
- over another scannable element
- inside QR exclusion zones where inappropriate

## Question Flow

Questions normally flow vertically.

Options may flow:

- horizontally
- vertically
- as a fixed grid

depending on question type and available width.

## Multi-page

If insufficient space remains:

move the complete question/group to the next page where possible.

Do not split a small logical question across pages unnecessarily.

## Rule

The user controls survey semantics.

LayoutEngine controls printable OMR geometry.
