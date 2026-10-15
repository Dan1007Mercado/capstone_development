# P11.1 Final Scanner Runtime Hardening ExecPlan

## Goal

Move final still scanning off the Flutter UI isolate into one persistent worker,
add actionable per-stage timings, remove demonstrated image conversion waste,
and provide a richer authoritative scanner validation sheet.

## Existing State

P11 coordinates a high-quality camera still into P9, but its adapter invokes
the synchronous scanner on the main isolate. The native P5 backend decodes with
the Dart image package, converts to an OpenCV Mat, then PNG-encodes the canonical
page for P6 to decode again. Android measured P9 at about 9272.6 ms.

## Architectural Constraints

- `PageLayout` remains the only PDF/scanner geometry source.
- Native OpenCV objects are created, used, and disposed in the scanner worker.
- Isolate messages contain only Dart domain data and transferable byte buffers.
- Camera preview/live analysis remain P10.3 behavior and final scans stay
  single-flight.
- Recognition thresholds and semantics do not change.

## Proposed Design

Use a persistent `IsolateOfflineScannerRunner`. It transfers encoded still
bytes with `TransferableTypedData`, supplies the immutable template, layout,
and scanner config, and returns a pure-Dart result envelope. The worker creates
its P5-P9 composition and reuses the isolate across scans. The coordinator
restarts live analysis as soon as capture bytes are owned while keeping the
final-scan latch active.

Add P5 timing boundaries for native decode, detection, correspondence,
homography, and warp. Use OpenCV `imdecode` directly. Return an owned canonical
grayscale buffer from the native warp so P6 avoids a PNG encode/decode cycle;
retain PNG input support for existing pure-Dart fixtures.

Create a ten-question validation template through TemplateValidator,
LayoutEngine, PageLayout, and PdfEngine, plus deterministic tests and a checked
in generated PDF.

## Tests

Cover worker reuse/disposal/failure/transfer contracts, coordinator camera
restart and single flight, timing consistency, raw canonical preprocessing,
authoritative rich-sheet semantics/geometry, and the existing P6-P9 synthetic
integration path.

## Performance

Preserve the P11 Android baseline (capture 832.7 ms, P9 9272.6 ms, total
10214.3 ms). Automated tests prove boundaries and eliminate known redundant
conversions; only repeated Infinix measurements may establish improvement.

## Risks

OpenCV FFI libraries must load independently in the worker isolate. Large
messages must not be copied repeatedly. Camera analysis may resume only after
the still buffer is owned, while auto-capture remains disarmed.

## Completion Criteria

The UI isolate never invokes the production native final scanner, one worker
supports repeated scans and clean disposal, detailed timings reach diagnostics,
the richer PDF is authoritative, all repository gates pass, and Android
performance remains explicitly manual.
