# ArUco Static-Image Alignment Contract

## Backend

Phase 5 uses `opencv_dart` for OpenCV ArUco detection, projective homography,
and perspective warp. The package supports Android and desktop targets and
keeps the engine independent of Flutter widgets. The repository pins the
pre-Native-Assets 1.2.5 line because the current 2.x line requires a host C++
toolchain even for pure Dart tests; 1.2.5 uses the same OpenCV-facing APIs and
prebuilt platform-library model. The root app includes only the relevant
OpenCV module groups. Upgrading to 2.x is appropriate once CI and developer
hosts provide the required native build toolchains.

The public application boundary accepts encoded image bytes. The production
adapter decodes those bytes once as grayscale. Final-still marker detection may
use a configured reduced long edge; detected corners are scaled back to the
original source coordinate space before correspondence and homography. The
original full-resolution grayscale `Mat` is always the warp source. A
persistent worker may reuse its dictionary, parameters, and detector, but owns
and disposes them inside that isolate. Sessions and temporary Mats/vectors are
disposed deterministically. The returned canonical image is owned grayscale
Dart bytes and has no native ownership requirement.

## Dictionary and Corner Order

Detection uses exactly OpenCV `DICT_4X4_50`, matching the PDF engine. OpenCV's
marker-local corner order is normalized once at the backend boundary as:

1. top-left
2. top-right
3. bottom-right
4. bottom-left

Detector list order has no semantic meaning. Marker IDs from `PageLayout`
determine the four page roles; unrelated IDs are ignored by default, missing
required IDs fail, and duplicate required IDs are ambiguous failures.

## P4.1 Registration Correspondence

Detection targets the inner 6x6 ArUco marker, not its printable 8x8 region with
quiet zone. The page-facing detected corner mapping is centralized:

- page top-left marker -> detected bottom-right
- page top-right marker -> detected bottom-left
- page bottom-left marker -> detected top-right
- page bottom-right marker -> detected top-left

Each destination is the matching `MarkerRegion.physicalRegistrationPoint`
converted to canonical pixels using the physical `PageSpec` dimensions and the
exact `CanonicalPageSpec` width and height. No marker center or quiet-zone
corner participates in homography.

## Homography and Output

The projective transform maps source-image registration points to canonical
registration points. `warpPerspective` produces a grayscale image with exactly
the width and height in `PageLayout.canonicalPageSpec`. Results expose canonical
grayscale pixels, the 3x3
homography, source and destination correspondences, semantic marker
observations, quality metrics, reprojection errors, and processing duration.

## Quality Gate

Provisional defaults are centralized in `ArucoAlignmentConfig`. Validation
requires all four expected IDs exactly once, corners inside the source image,
minimum marker side length, valid convex marker quadrilaterals, non-reflected
convex page topology, usable page-area ratio, plausible spacing and perspective,
finite homography values, and reprojection within tolerance. Rotations of 90,
180, and 270 degrees preserve semantic ID topology and are accepted; mirrored
topology is rejected. Thresholds require later physical printer/device
calibration and are not production accuracy claims.

## Scope

This engine performs static-image registration only. QR layout selection,
camera capture, recognition preprocessing, bubble measurement, classification,
scanner orchestration, persistence, and UI remain outside Phase 5.
