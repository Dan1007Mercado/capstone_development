# PDF Rendering Contract

The PDF engine consumes `LayoutDocument` as the sole source of page geometry.
It does not paginate or calculate marker, bubble, question, section, header, or
identity positions.

## Units

Physical millimeters convert centrally to PDF points using
`points = millimeters x 72 / 25.4`. Each PDF page uses the exact physical width
and height from `PageLayout.pageSpec`.

## Marker Protocol

The fixed dictionary is OpenCV `DICT_4X4_50`. Each marker is rendered over the
full `MarkerRegion.physicalBounds` as an 8x8 module grid: one white quiet-zone
module, the inner 6x6 detectable ArUco marker, its one-module black border, and
its 4x4 dictionary payload. `physicalMarkerBounds` is therefore inset by one
eighth of the printable width on every edge. Registration points are the
page-facing corners of that detectable 6x6 bound. Layout owns this geometry;
the encoder exposes matching `quietZoneModules`, `markerModules`, and
`totalModules` metadata, and the PDF engine validates rather than recalculates
the contract.

## Page Identity

The QR payload is `TS1|<templateId>|<templateVersion>|<pageId>`. `TS1` versions
the printable identity protocol. Text fields are encoded as URI components, so
delimiter characters, spaces, and Unicode round-trip without ambiguity. Decode
returns a typed `TemplatePageIdentity` result or a structured protocol failure.

## Bubbles

Every printed bubble is a circle inscribed in its exact square
`BubbleRegion.physicalBounds`. The renderer never resizes or relocates a bubble
for its label. The visual label offset is configured by
`PdfRenderStyle.optionLabelGapMm` and defaults to 1.0 mm.

## Text and Diagnostics

Header and section lead text use only their supplied content regions.
Continuation fragments with null lead regions do not repeat headings.
Diagnostic outlines are disabled by default and never cross marker or bubble
regions.
