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
                                |
                       contour stability tracker
                         /                  \
                    reject                 promising
                      |                       |
                  guidance             640-800 px ArUco
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

## Document gate

The persistent analysis isolate downsamples luma to the configured
`documentGateMaxDimension`, smooths it, runs Canny edge detection, finds
external contours, approximates polygons, and retains the largest convex
four-corner candidate. Corners are always ordered top-left, top-right,
bottom-right, bottom-left. Brightness and Laplacian variance are measured
inside the detected paper polygon; whole-frame values are the fallback.

The gate rejects dark, overexposed, blurred, too-small, overly skewed, and
unstable frames before ArUco. A usable frame with no confident contour receives
an ArUco fallback probe every configured number of frames. This avoids a
white-paper-on-light-background deadlock. Setting `documentGateEnabled` to
`false` restores the p14-style unconditional live ArUco path.

## Stability and readiness

`FrameStabilityTracker` compares normalized document corners, centroid, and
area between observations. This cheap stability gate does not replace the
existing marker-based confirmation. READY requires acceptable document
quality, document stability, resolved page identity, usable registration
geometry, marker stability, and an ArUco confirmation no older than
`arucoConfirmationMaxAge` (450 ms by default).

When no contour is available, a successful fallback probe may instead use the
p14 marker-based readiness path. Stability is accumulated only from successful
authoritative probes, expires after a bounded probe gap, and resets on page or
marker identity changes, failed probes, analysis stop/suspend, and scanner
reset.

The preview overlay maps contour corners through the same orientation and
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
document-detector-failed, recoverable-analysis-failed, ArUco-attempted,
ArUco-skipped, fallback-probe, and ready frames. Derived output includes ArUco
avoidance, dropped-frame ratio, first-document-to-ready, and
first-identity-to-ready durations. Device performance goals are measurements,
not CI wall-clock assertions.

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
the periodic ArUco probe is the deliberate fallback. Thresholds require
calibration on multiple Android devices and printers. Document contours are not
used as final OMR coordinates, and the optional ArUco ROI crop is intentionally
deferred until it can be benchmarked without correctness risk.
