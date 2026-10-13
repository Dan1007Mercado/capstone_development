# Printable Sheet Reference

Initial target:

A4 portrait

210 mm × 297 mm

## Sheet Contents

A page may contain:

- survey title
- template/version identity
- page identity
- QR code
- four ArUco markers
- question text
- option labels
- OMR bubbles
- basic instructions

## Geometry

Every scannable position comes from PageLayout.

The PDF engine only converts PageLayout physical geometry into PDF drawing units.

## Bubbles

Bubbles should have:

- consistent dimensions
- adequate writable area
- adequate separation
- predictable outline thickness

## Markers

ArUco markers require:

- known marker ID
- known dictionary
- stable printed dimensions
- appropriate quiet zone
- placement defined by PageLayout

## Printing

Validate using:

- actual-size printing
- multiple printers
- different quality settings
- minor printer scaling differences

Do not assume printers are geometrically perfect.
