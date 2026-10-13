# Coordinate System

TalaanScan uses distinct coordinate spaces.

## Logical Space

Survey semantics only.

Example:

QuestionId q17  
OptionId q17_c

No image geometry belongs here.

## Physical Page Space

Recommended unit:

millimeters.

Initial page:

A4 portrait

210 mm × 297 mm

Origin:

top-left.

X increases right.

Y increases downward.

## Normalized Space

Resolution-independent page representation.

x ∈ [0, 1]

y ∈ [0, 1]

Origin:

top-left.

Conceptually:

normalizedX = physicalX / pageWidth

normalizedY = physicalY / pageHeight

## Canonical Image Space

The rectified top-down page image.

Its pixel dimensions are configurable.

Normalized geometry maps into canonical pixels.

## Raw Camera Space

The camera sensor/image coordinates.

These values are transient observations.

They must not become authoritative template geometry.

## Rule

Coordinate conversion belongs in centralized geometry/value classes.

Never duplicate conversion formulas across engines.
