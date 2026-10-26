# P15.2.7 replay and Android validation

## Export and replay

Build a debug APK with failed-capture export explicitly enabled:

```powershell
flutter run --dart-define=ENABLE_FAILED_SCAN_CAPTURE_EXPORT=true
```

After a rejected final capture, open Scanner Diagnostics and select **Export
Failed Still**. The ZIP contains the unchanged captured image, exact published
template and `PageLayout`, full scanner configuration, original structured
failure, schema version, and SHA-256/length records for every payload.

Replay it locally:

```powershell
dart run tool/replay_failed_scan.dart --bundle "C:\path\failed_capture.zip"
```

Useful options:

```powershell
dart run tool/replay_failed_scan.dart --bundle "C:\path\failed_capture.zip" --compare-resolution --json
dart run tool/replay_failed_scan.dart --bundle "C:\path\failed_capture.zip" --ground-truth "C:\path\bubble_centers.json"
dart run tool/replay_failed_scan.dart --bundle "C:\path\failed_capture.zip" --expected-answers "C:\path\answers.json"
```

`--compare-resolution` compares the recorded 1400-pixel detection setting with
full-resolution detection. It does not change production configuration. The
report labels legacy four-point, current four-point, current 16-point RANSAC,
and actual production selection separately. If native OpenCV is unavailable,
the command fails; that run is not evidence of scanner success.

Ground-truth annotations use original-image pixels:

```json
{
  "annotations": [
    {"questionId":"q1","targetLabel":"q1-a","sourceX":123.5,"sourceY":456.5}
  ]
}
```

Expected answers use the JSON emitted by `PhysicalValidationPlan.toJson()`.
Without annotations, printed-outline evidence may be `measured` or
`inconclusive`; it is never presented as a calibrated production pass. Without
expected answers, OMR correctness is explicitly `UNVERIFIED_NO_EXPECTED_ANSWERS`.

## Infinix X6711 acceptance run

Use the development scanner only; results are not submitted or saved as student
responses. Import or enter one known-answer plan, then collect five attempts for
each scenario:

| Scenario | Attempts |
|---|---:|
| Flat A4, evenly lit | 5 |
| A4, moderate tilt | 5 |
| A4, mild directional shadow | 5 |
| Letter, Fit to Page | 5 |
| Readably reduced printed sheet | 5 |

Record each result with `AndroidOmrAcceptanceAttempt`, using device model
`Infinix X6711`, the scenario, attempt number, elapsed capture-to-result time,
the scan or structured failure, expected-answer plan, and any independently
measured outline evidence. Export `AndroidOmrAcceptanceReport.toJson()` after
all 25 attempts. `matrixComplete` stays false unless all scenarios have at
least five attempts on that device.

Review accepted-answer accuracy separately from rejected attempts. The summary
includes false marks, false blanks, false multiple classifications, P50/P95
latency, estimator selection frequency, and rejection reasons. Do not claim
physical accuracy until this matrix has been collected from printed sheets.
