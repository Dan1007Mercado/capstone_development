# PDF Rendering Contract

The PDF engine consumes `LayoutDocument` as the sole source of page geometry. It does not paginate or calculate marker, bubble, question, section, header, or identity positions.

## Units

Physical millimeters convert centrally to PDF points using `points = millimeters × 72 / 25.4`. Each PDF page uses the exact physical width and height from `PageLayout.pageSpec`.

## Marker Protocol

The fixed dictionary is OpenCV `DICT_4X4_50`. Each `MarkerRegion` is divided into an 8×8 module grid: one white quiet-zone module, one black ArUco border module, and the 4×4 dictionary payload. Thus the region bounds include the quiet zone. Existing registration points remain the inner-facing corners of the supplied `MarkerRegion`; rendering does not alter them.

## Page Identity

The QR payload is `TS1|<templateId>|<templateVersion>|<pageId>`. `TS1` versions the printable identity protocol.

## Bubbles

Every printed bubble is a circle inscribed in its exact square `BubbleRegion.physicalBounds`. The renderer never resizes or relocates a bubble for its label.

## Text and Diagnostics

Header and section lead text use only their supplied content regions. Continuation fragments with null lead regions do not repeat headings. Diagnostic outlines are disabled by default and never cross marker or bubble regions.
