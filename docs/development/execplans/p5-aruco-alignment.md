# Phase 5 ArUco Alignment ExecPlan

### Goal

Align an encoded static image to its supplied `PageLayout` using the four
expected `DICT_4X4_50` markers and return a canonical PNG plus diagnostics, or
a structured failure.

### Existing State

`PageLayout` owns printable and detectable marker bounds, page-facing physical
registration points, and canonical dimensions. The PDF marker encoder uses
OpenCV `DICT_4X4_50`; no scan-side image engine exists yet.

### Architectural Constraints

- Preserve `PageLayout` as the only page-geometry authority.
- Resolve page roles by marker ID, never detector order.
- Match detected corners to the P4.1 detectable-marker convention.
- Keep widget, camera, preprocessing, recognition, and persistence concerns out.
- Return typed results and structured errors; never estimate missing markers.

### Proposed Design

- Immutable pixel-space, detection, correspondence, homography, quality, and
  result models under `engines/aruco/domain`.
- A pure-Dart correspondence/quality service validates exact marker matches,
  corner bounds and size, convex non-reflected topology, area, spacing, and
  perspective.
- An application engine coordinates a disposable backend session, validates
  finite homography and reprojection error, and returns the canonical image.
- An `opencv_dart` 1.2.5 infrastructure adapter decodes once, detects
  `DICT_4X4_50`, normalizes OpenCV's TL/TR/BR/BL order, computes a projective
  transform, warps to `CanonicalPageSpec`, encodes PNG, and releases native
  resources deterministically.

### Files

Add ArUco domain/application/infrastructure modules, tests, alignment contract
documentation, and this plan. Update dependency configuration and lockfile.

### Tests

Pure tests cover role mapping, detector-order independence, P4.1 corner
selection, canonical conversion, rotation, extra/missing/duplicate IDs,
reflection, degeneracy, tiny markers, and reprojection. Native integration
tests generate deterministic marker sheets and cover frontal, perspective,
rotated, translated/scaled, missing-marker, and exact output dimensions.

### Performance

Record alignment duration in diagnostics. Decode the source once per alignment
and dispose native matrices explicitly. Phase 5 establishes correctness, not a
production performance claim.

### Risks

Native Assets availability can vary by host; backend failures must remain
structured and pure tests must stay runnable. Quality defaults are provisional
and may require physical-sheet calibration.

The current Windows host has no Visual Studio C++ toolchain/native OpenCV DLL,
so backend integration tests self-skip with `ARUCO_BACKEND_UNAVAILABLE`; their
generated frontal, perspective, rotation, translation, scale, missing,
duplicate, degeneracy, and output-dimension cases run when the native library
is installed.

### Completion Criteria

An encoded static page completes detection, semantic matching, validated P4.1
correspondence, homography, and exact-size canonical warp, with deterministic
failure codes for unsafe inputs.
