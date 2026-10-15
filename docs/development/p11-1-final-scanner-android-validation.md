# P11.1 final scanner Android validation

P11.1 keeps the P11 high-quality still contract but transfers owned encoded
bytes to one persistent final-scanner isolate. That isolate owns P5-P9 and all
native OpenCV resources. After the still bytes are owned, P10 live analysis
resumes while the final scan continues; the coordinator remains single-flight
and auto capture remains latched until reset.

The native path now decodes the still directly with OpenCV and carries an owned
canonical grayscale buffer into P6. It does not PNG-encode and immediately
decode the canonical page. The 800-pixel P10.3 live-analysis path is unchanged.

## Preserved baseline

P11 Android baseline on Infinix X6711:

- capture: about 832.7 ms
- byte load: about 0.1 ms
- P9 scanner: about 9272.6 ms
- capture-to-result: about 10214.3 ms

Do not replace these values. Record P11.1 results beside them only after real
device testing.

## Validation sheet and answer simulation

Use `debug_output/p11_1_scanner_validation_sheet.pdf`. Its ten questions
paginate naturally across three A4 pages under the accepted layout rules. The
deterministic fixture is generated through
`TemplateDefinition -> TemplateValidator -> LayoutEngine -> PageLayout ->
PdfEngine`; neither the PDF nor scanner hand-places bubbles.

Suggested marks:

- Q1 Likert: 4
- Q2 Likert: 2
- Q3 Likert: blank
- Q4 single choice: B
- Q5 single choice: mark two options to exercise MULTIPLE
- Q6 checklist: A, C, E
- Q7 checklist: B, D
- Q8 yes/no: YES
- Q9 yes/no: NO
- Q10 numeric grid: one digit per column, for example 4-2-7

Optionally use one faint or partial mark for a future AMBIGUOUS calibration
observation. Do not change recognition thresholds in this phase.

## Infinix X6711 procedure

1. Run `flutter devices` and `flutter run -d <device-id>`.
2. Open **P11 Camera Scanner Diagnostics**.
3. Display the PDF on another screen, then repeat with A4 printed at 100% /
   Actual Size when available; printed paper is the primary gate.
4. Wait for marker IDs `[10, 11, 12, 13]` and readiness `ready`.
5. Start with page 1, which is the page selected by the current debug
   composition. Capture and confirm `scanning` appears immediately while preview and UI
   remain responsive.
6. Confirm live analysis resumes without another capture while the worker is
   scanning.
7. Confirm `scanCompleted` and inspect the response states against the physical
   marks without tuning thresholds.
8. Record source/canonical dimensions and capture, transfer/load, decode,
   ArUco, correspondence, homography, warp, preprocessing, measurement,
   classification, validation, worker-total, isolate-overhead, and total times.
9. Repeat at least five scans and record minimum, average, and maximum final
   scan time.
10. Reset and scan again without restarting the camera; verify worker status
    changes from newly started to reused.
11. Force an alignment failure, retry, and confirm recovery.
12. Inspect logcat for BLASTBufferQueue errors, native crashes, GC churn, OOM,
    and isolate errors.

Record results without claiming the 2-3 second target unless the device
measurements demonstrate it.

Manual P11.1 Android validation status: **NOT RUN**.
