# P15 Production Scanner Workflow

## Corrected live architecture

Physical testing showed that the original p15 document gate degraded marker
acquisition and time to READY. The gate, SEARCH/ACTIVE state machine, fallback
probe cadence, and confirmation-age dependency have therefore been removed.

ArUco is authoritative and unconditional on every camera frame accepted by the
existing target-analysis-FPS and drop-while-busy scheduler:

```text
camera preview (independent platform texture)
  |
  +-- accepted Y/luma frame
        |
        +-- prepare grayscale analysis image
        +-- measure whole-frame brightness and sharpness
        +-- ArUco detectGray()
        +-- resolve page marker signature
        +-- calculate marker geometry
        +-- evaluate marker readiness and stability
        +-- READY -> auto capture
        |
        +-- optional, lower-cadence paper-edge detector
              +-- best-effort contour extraction
              +-- short smoothing/persistence
              +-- preview coordinate mapping
              +-- high-contrast visual outline
```

There is no arrow from paper-edge detection to ArUco execution, page identity,
readiness, marker stability, capture authorization, perspective correction, or
OMR. If the paper detector returns null forever or throws on every attempt,
ArUco still receives every accepted frame and READY remains reachable.

## Registration and perspective

The responsibilities are deliberately separate:

```text
paper edge                  = physical-sheet visualization only
live ArUco marker geometry = identity, size, tilt, and stability guidance
high-resolution ArUco      = final homography and canonical OMR alignment
```

Paper corners never become registration points and never pre-warp the captured
answer sheet. The final scanner continues to use the existing high-resolution
`OpenCvArucoVisionBackend`, `ArucoAlignmentEngine`, `PageLayout`, homography,
and OMR pipeline unchanged.

## Marker readiness

The marker-based readiness order is:

1. Resolve the selected template's page-marker signature.
2. Require the configured markers and four registration points.
3. Check marker-derived page area and minimum marker side length.
4. Check marker-derived perspective ratio.
5. Check whole-frame brightness and sharpness.
6. Accumulate marker displacement stability for the configured frame count.
7. Report READY and request auto capture.

A page identity change resets marker stability and starts a fresh window. A
single unknown signature reports “Verifying sheet”; three consecutive unknown
signatures confirm the wrong-sheet state. A valid page resets that streak
immediately. SH1/SH2 page-signature resolution remains authoritative.

## Paper-edge visualization

The contour detector consumes grayscale pixels and runs after the authoritative
ArUco pass. It may run at a lower cadence through
`paperEdgeDetectionIntervalFrames`; this cadence never changes ArUco cadence.
The detector keeps a short visual grace polygon and lightly smooths new paper
corners. Detector exceptions are captured as paper-edge diagnostics and treated
as a missing visual result, not a camera-session failure.

The overlay first projects the authoritative `PageLayout` boundary from four
valid ArUco registration points. The resolved page identity must match the
layout used for projection. Physical-paper geometry is a visual fallback only;
the two polygons are not drawn together. Its production styling uses a
semi-transparent dark 4 px outer stroke plus a 2 px inner stroke: white while
tracking, amber when framing guidance is needed, and green when READY. The
existing `PreviewCoordinateMapper` remains responsible for sensor orientation,
device orientation, mirroring, `BoxFit.cover`, and center cropping.

## Recoverable frame failures

Malformed materialization is recorded as
`CAMERA_FRAME_MATERIALIZATION_FAILED`; malformed worker input returns
`CAMERA_FRAME_ANALYSIS_RECOVERABLE`. The bad frame is skipped, marker stability
is reset, and camera analysis continues with the next accepted frame. Camera
initialization, stream startup, native backend availability, and other session
failures remain fatal. Reset generation guards prevent in-flight observations
from restoring stale marker geometry.

## Acceptance and persistence ordering

`ScanAcceptancePolicy` still runs after the high-resolution scanner result and
before `ScannerValidationSession.recordResult()` or
`PacketResponseService.claim()`.

- Wholly blank, ambiguous, invalid, and exclusive-multiple results require a
  rescan.
- Valid multi-selection for `multipleChoice` remains accepted.
- Rejected results do not record a page, claim a packet page, or increment the
  response count.
- `PacketResponseService.claim()` re-evaluates the acceptance policy as
  defense-in-depth.

Packet identity, duplicate protection, partial/complete lifecycle, page-2-first
support, batch PDF output, and response creation after successful scanning are
unchanged.

## Diagnostics

Developer diagnostics report received, accepted, processed, and dropped frames;
analysis FPS; average total and ArUco duration; ArUco opportunities; time to
first marker, identity, and READY; recoverable analysis failures; paper-edge
detections, failures, acquisitions, losses, temporary loss, and average visual
detection duration. They also retain lifecycle transition counts and the latest
camera error code, stage, and root cause. Obsolete document-rejected,
ArUco-skipped/fallback,
SEARCH/ACTIVE, and document-to-readiness metrics were removed.

## Manual physical test matrix

Measure analysis FPS, time to first marker, time to identity, time to READY,
average ArUco duration, dropped frames, paper-outline acquisition, paper visual
failures, final scan duration, and answer correctness for:

| Case | Sheet/condition |
|---|---|
| A | Correct sheet on dark table |
| B | Correct sheet on light patterned cloth |
| C | Correct sheet with no detectable paper contour |
| D | Paper visualization disabled |
| E | SH1 |
| F | SH2 |
| G | Phone moving |
| H | Moderate marker perspective |
| I | Sheet too far away |
| J | Partial marker occlusion |
| K | Wrong sheet |
| L | Blank scan |
| M | Ambiguous double mark |
| N | Dense filled sheet |

Synthetic tests complement this matrix but do not replace printed-sheet tests
across multiple printers and Android devices.
