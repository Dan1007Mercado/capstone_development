# P15 Production Scanner Workflow

## Problem

The p14 live analyzer ran ArUco on every accepted analysis frame, including
frames that were plainly dark, bright, blurred, too distant, or moving. Final
recognition results could also reach session and packet persistence before a
workflow-level rescan decision.

## Two-stage live pipeline

```text
camera preview (independent platform texture)
  |
  +-- throttled Y/luma frames -- drop while busy
                                |
                         480-640 px preparation
                                |
                    document contour + local quality
                         /                  \
          persistent visual tracker     usable candidate
                      |                       |
               immediate outline       640-800 px ArUco
                                              |
                                page identity + registration
                                              |
                                recent confirmation required
                                              |
                                            READY
                                              |
                                         auto capture
                                              |
                                  original high-resolution still
                                              |
                         full ArUco -> PageLayout -> OMR
                                              |
                                  ScanAcceptancePolicy
                                     /              \
                                  rescan           accept
                                                    |
                                      record page, then claim packet
```

The document polygon is guidance geometry only. ArUco remains authoritative for
page identity, registration, homography, and the final scan. The final scanner
still detects ArUco directly on the original captured image; there is no
contour-derived pre-warp.

Document contour detection is best-effort. Native contour failures and
document-local quality edge cases are recorded as developer diagnostics and
treated as a missing contour for that frame. They do not stop preview or move
the camera lifecycle to `error`; the periodic ArUco fallback remains active.

## SEARCH/ACTIVE acquisition

The persistent analysis isolate downsamples luma to the configured
`documentGateMaxDimension`, smooths it, runs Canny edge detection, finds
external contours, approximates polygons, and retains the largest convex
four-corner candidate. Corners are always ordered top-left, top-right,
bottom-right, bottom-left. Brightness and Laplacian variance are measured
inside the detected paper polygon; whole-frame values are the fallback.

SEARCH uses generic full-frame document detection and periodic ArUco probes.
Any document candidate, any detected ArUco marker, or resolved identity enters
ACTIVE. ACTIVE runs ArUco on every accepted analysis frame and tolerates three
complete evidence misses before returning to SEARCH. A single marker is enough
to wake ACTIVE; four markers are required only by authoritative geometry and
readiness checks.

The live gate skips only clearly unusable dark, overexposed, or severely
blurred frames. Contour size, contour perspective, and ordinary capture-quality
failures do not throttle ArUco. When markers exist but the generic contour is
weak, their expanded bounds constrain a second physical-edge search. Marker
geometry is only a search hint: the final outline is still the detected paper
edge and no marker-derived crop or pre-warp is used.

## Stability and readiness

P15.0.2 separates two concurrent live phases. `DocumentTracker` acquires,
associates, and lightly smooths physical-paper geometry for immediate preview
feedback. It retains that visual geometry for at most three missed analysis
frames, but marks it stale so it cannot authorize capture.

In parallel, every active frame runs ArUco immediately.
Document stability no longer has to complete before marker analysis begins;
this removes the serial document-stability then marker-stability delay. Cheap
document brightness, sharpness, size, and gross-skew checks only decide whether
heavy live ArUco work is worthwhile. Resolved page identity, registration
geometry, and marker stability remain the single authoritative READY path.

READY requires acceptable frame quality, resolved page identity, usable
registration geometry, marker stability, and an ArUco confirmation no older
than `arucoConfirmationMaxAge` (450 ms by default).

When no contour is available, a successful fallback probe may instead use the
p14 marker-based readiness path. Stability is accumulated only from successful
authoritative probes, expires after a bounded probe gap, and resets on page or
marker identity changes, failed probes, analysis stop/suspend, and scanner
reset.

The high-contrast dual-stroke preview overlay maps contour corners through the same orientation and
`BoxFit.cover` center-crop transform as the camera preview. When the contour is
missing, four valid marker registration points provide a thinner fallback
quadrilateral; this cue is not treated as a detected paper edge.

## Acceptance and persistence ordering

`ScanAcceptancePolicy` is evaluated after the high-resolution scanner returns
and before `ScannerValidationSession.recordResult()` or
`PacketResponseService.claim()`.

- A wholly blank page requires rescan; an optional blank among valid answers is
  allowed.
- Ambiguous or invalid questions require rescan.
- Multiple marks in exclusive types require rescan.
- A valid `multipleChoice` result remains `marked` with several option IDs and
  is accepted.
- Incomplete or uncertain numeric grids require rescan.
- Existing required-question review outcomes require rescan.

Rejected results never enter completed page IDs and never claim a packet page,
so a corrected retry remains eligible. In a multi-page packet an accepted page
can remain partial while another page is rejected and later rescanned.

## Diagnostics

Developer diagnostics retain existing timings and add document detection,
quality, stability, ArUco, and total live-analysis timing. Counters include
received, accepted, processed, dropped, document-detected, document-rejected,
document-detector-failed, temporary-document-loss, recoverable-analysis-failed,
ArUco-attempted, ArUco-skipped, fallback-probe, and ready frames. Derived output
includes ArUco attempt/avoidance ratios, dropped-frame ratio,
first-document-to-identity, first-document-to-ready, first-marker,
first-identity, and time-to-ready durations. SEARCH/ACTIVE frame counts and the
ACTIVE ArUco attempt ratio show whether ArUco began
with acquisition rather than after document stabilization. Device performance
goals are measurements, not CI wall-clock assertions.

## Manual physical test matrix

Record time to first document, time to READY, auto-capture success, ArUco
attempts, final scan duration, and answer correctness for each case:

| Case | Sheet/condition |
|---|---|
| A | Good straight sheet |
| B | Moderately tilted |
| C | Too far |
| D | Very close |
| E | Motion blur |
| F | Dim indoor light |
| G | Strong glare |
| H | Dark background |
| I | White paper on white/light background |
| J | Partially occluded paper |
| K | Wrong sheet |
| L | SH1 and SH2 identity |
| M | Multi-page same packet, including out-of-order retry |
| N | Dense sheet |
| O | All bubbles filled |
| P | Blank page |
| Q | Faint marks |
| R | Erased marks |
| S | Two marks in single-choice |
| T | Valid multiple-choice marks |

Dense/all-filled anomalies must be diagnosed for ROI cross-talk, baseline
contamination, neighbor interference, and duration before any classification
threshold is changed.

## Known limitations

Contour detection can be weak when page and background contrast are similar;
periodic SEARCH probes and marker-assisted edge search are the deliberate
fallbacks. Thresholds require calibration on multiple Android devices and
printers. Document contours are not used as final OMR coordinates.
