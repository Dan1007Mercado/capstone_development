# OMR Architecture Reference

## Principle

TalaanScan creates the sheet it later recognizes.

Therefore the scanner already knows the expected document structure.

The scanner does not need to discover the survey from arbitrary paper.

It knows:

- template identity
- page identity
- question identity
- option identity
- marker locations
- bubble locations
- expected geometry

Its primary geometric problem is transforming a photographed sheet into the same coordinate system used when that sheet was generated.

## Engine Separation

### Template Engine

Represents survey semantics.

### Layout Engine

Turns semantics into deterministic page geometry.

### PDF Engine

Draws PageLayout.

### Camera Engine

Acquires and evaluates camera frames.

### ArUco Engine

Detects registration markers and estimates page alignment.

### Preprocessing Engine

Normalizes image data for stable measurements.

### Recognition Engine

Samples known bubble regions and classifies responses.

### Scanner Engine

Coordinates all engines and emits ScanResult.

## Responsibility Rule

ArUco answers:

WHERE IS THE PAGE?

Template identity answers:

WHICH PAGE IS THIS?

PageLayout answers:

WHERE SHOULD EACH BUBBLE BE?

Preprocessing answers:

HOW CAN THIS IMAGE BE MEASURED RELIABLY?

Bubble sampling answers:

WHAT DOES EACH EXPECTED ROI LOOK LIKE?

Classification answers:

WHAT RESPONSE DOES THE EVIDENCE SUPPORT?

Persistence answers:

WHERE SHOULD RESULTS BE STORED?

Do not collapse these into one large scanner service.
