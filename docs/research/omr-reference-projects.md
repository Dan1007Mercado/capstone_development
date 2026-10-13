# OMR Reference Projects

These repositories are architectural and algorithmic references.

Do not blindly copy source code.

Licenses must be checked before direct reuse.

## SheetScanner

Useful concepts:

- generated OMR sheets
- four ArUco markers
- perspective alignment
- known bubble geometry
- fill-ratio measurements
- blank/multiple/ambiguous handling
- shared geometry concepts

Particularly relevant to TalaanScan because the system controls both generation and recognition.

## OMRChecker

Useful concepts:

- template-driven recognition
- configurable page dimensions
- bubble dimensions
- field blocks
- configurable spacing
- preprocessing pipeline
- marker-assisted alignment

Important lesson:

recognition behavior can be data-driven rather than hard-coded per form.

## omr-system

Useful conceptual architecture:

PREPROCESS
→ ALIGN
→ SAMPLE
→ DECIDE

Useful ideas:

- alignment confidence
- rejection of bad alignment
- page-relative/adaptive classification

## Answer Sheet OMR

Useful concepts:

- diagnostics
- aligned-image artifacts
- bubble overlays
- bubble score output
- explicit review/uncertainty handling

## OMRSuite

Useful concepts:

- fiducial-based alignment
- homography
- canonical page
- known ROI sampling

## LazyOMR

Useful as a mobile/offline OMR workflow reference.

## DepEd OMR Scanner

Useful concepts:

- mobile camera workflow
- fiducial guidance
- canonical coordinate normalization
- offline scanning

## selfcal-omr

Future research only.

Potential use:

self-calibration if generated geometry needs a fallback.

Not required in the initial architecture.

## flutter_omr

Useful reference for separating Flutter UI from native/OpenCV processing.

## YOLO-based OMR Projects

Useful for comparison only.

The initial TalaanScan design does not require YOLO because it controls its own template geometry.

Machine learning should only be reconsidered if measured failures demonstrate a specific classification problem that deterministic processing cannot solve acceptably.
