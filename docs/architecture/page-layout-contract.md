# PageLayout Contract

`LayoutEngine` transforms a valid semantic `TemplateDefinition` and explicit
`LayoutConfig` into an ordered `LayoutDocument`. Each `PageLayout` is the single
source of truth for future PDF rendering and scanner sampling; neither consumer
may recalculate bubble positions.

## Coordinate Contract

All authoritative print geometry is stored in millimeters. Every
scanner-relevant region also stores normalized page geometry produced through
`GeometryConverter`. The origin is top-left, with x increasing right and y
increasing down.

## Markers

Four configurable marker IDs map to semantic corner roles. Homography reference
points use each marker's page-facing inner corner:

- top-left: bottom-right corner
- top-right: bottom-left corner
- bottom-left: top-right corner
- bottom-right: top-left corner

The marker center is not the registration point.

## Page Identity

Page IDs are deterministic and use the form
`<template-id>-v<version>-p<one-based-page-number>`. `pageIndex` remains
zero-based in the layout contract.

## Flow and Pagination

Sections and questions preserve semantic order and flow vertically. A question
that does not fit moves whole to the next page. A question that cannot fit on a
fresh page returns `QUESTION_TOO_LARGE`; generated content is never clipped.

Normal option bubbles preserve option order. Numeric-grid bubbles use
column-major ordering: allowed digits run top-to-bottom within a column before
the next digit-position column.

## Defaults

`LayoutConfig.a4Default()` contains explicit initial A4 engineering values.
They are provisional until verified with physical printers, sheets, cameras,
and regression scans.
