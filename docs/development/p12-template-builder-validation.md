# P12 Template Builder Manual Validation

## Run

```text
flutter devices
flutter run -d <device-id>
```

Open **P12 Template Builder** from the debug home.

## Mixed-Type Workflow

1. Enter a template name and description.
2. Add Section 1 and add two Likert questions.
3. Set one Likert scale to 1-5 and the other to 1-7.
4. Add Section 2 with one Multiple Choice checklist and one Single Choice
   question; edit, add, remove, and reorder their options.
5. Add Section 3 with one Likert and one Yes / No question.
6. Add Section 4 with one Numeric Grid question and change its column count.
7. Reorder sections and questions with the arrow controls.
8. Switch one question through Likert, Multiple Choice, Yes / No, and back to
   Likert. Confirm its prompt remains and only relevant controls are displayed.
9. Press **Validate** and confirm the draft is valid. Clear a required prompt,
   validate again, and confirm the structured issue is visible; restore it.
10. Press **Preview Layout**. Confirm page count, page IDs, section order,
    question order, question types, and natural pagination are shown.
11. Press **Generate Preview PDF**. Confirm a non-zero in-memory byte count and
    the same page count are reported.
12. Optionally press **Load Mixed-Type Demo** to load the required P12 fixture
    containing all seven mixed questions.

## Geometry and Print Checks

- The builder must not expose arbitrary bubble placement.
- Generated pages must use marker IDs 10, 11, 12, and 13.
- Pagination must follow `LayoutEngine`; do not manually squeeze questions.
- Inspect a generated PDF through a development export/print integration when
  available and print at 100% / Actual Size. Confirm ArUco markers, bubbles, and
  labels use the standard printable contract.

## Record

- Supported type controls exercised
- Section/question/option reorders completed
- Repeated type switch completed
- Validation result
- Preview page count
- Generated PDF byte count and page count
- Any layout/PDF error code, message, and details

Manual validation is not complete until performed on a running Flutter target.
