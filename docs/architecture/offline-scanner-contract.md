# Offline Scanner Contract

`OfflineScannerEngine` scans one encoded image against one caller-supplied
`TemplateDefinition` and `PageLayout`:

`alignment → preprocessing → measurement → classification → ScanResult`

`PageLayout` remains the only source of scanner geometry. The scanner only
coordinates accepted P5–P8 contracts and never reimplements their algorithms.

## Validation and failures

Template identity, version, page ownership, and question-region membership are
validated before image processing. Every stage is mandatory. A failed stage
stops the pipeline and is wrapped with a scanner stage code while retaining the
child `causeCode`, `causeMessage`, and `causeDetails`.

The scanner never falls back to the unaligned or unprocessed image. It also
validates that classification returns the supplied page and exact PageLayout
question order before constructing a result.

## Page state

- `accepted`: all questions are safely interpreted or legitimately blank.
- `needsReview`: at least one question is `AMBIGUOUS` or `MULTIPLE`, or a
  required question is blank under the default required-question policy.
- `invalid`: at least one question is `INVALID`.

Priority is `invalid > needsReview > accepted`. Required blanks retain P8's
`BLANK` state and add `requiredQuestionBlank` plus the relevant question ID.
Review reasons and question IDs are structured, ordered, and immutable.

## Diagnostics

Results expose total/per-stage durations, P5 alignment diagnostics, P6
preprocessing diagnostics, question-state counts, required-blank count, and
measured-bubble count. Timings are diagnostic and are not semantic result data.
Pixel buffers are not copied into scanner diagnostics.

## Scope and deferrals

Processing is entirely local and has no network, Firebase, backend API, or
persistence dependency. Each call scans one page. Camera capture, QR template
lookup, multi-page sessions, batch scanning, persistence, analytics, and review
UI are deferred. Before camera integration, native P5 OpenCV integration must
still pass on at least one supported target environment.
