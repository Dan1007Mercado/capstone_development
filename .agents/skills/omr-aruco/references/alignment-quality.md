# Alignment Quality

Marker detection alone does not guarantee a trustworthy scan.

Evaluate alignment quality before recognition.

Potential checks include:

- required marker count
- expected IDs
- unique IDs
- plausible ordering
- quadrilateral convexity
- minimum page area
- no self-intersection
- plausible aspect ratio
- marker size consistency
- perspective severity
- reprojection error
- transform validity

## Failure

Alignment failure should produce a structured result.

Examples:

MISSING_MARKERS

DUPLICATE_MARKER

INVALID_GEOMETRY

PAGE_TOO_SMALL

EXTREME_PERSPECTIVE

HOMOGRAPHY_FAILED

POOR_REPROJECTION

Do not continue normal answer extraction after failed alignment.
