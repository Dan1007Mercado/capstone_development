# P12.1 PDF Export and Unicode Manual Validation

## Run

```text
flutter devices
flutter run -d <device-id>
```

Open **P12 Template Builder** from the debug home.

## Procedure

1. Create a template named `Résumé – Survey`.
2. Add a section named `Impormasyon ng Respondent`.
3. Add a question `Masaya ka ba sa serbisyo? ✓`.
4. Set option labels including `Oo – mahusay`, `Hindi — café`, and smart
   quotes such as `“tama”`.
5. Press **Validate** and confirm the template is valid.
6. Press **Preview Layout** and record the page count.
7. Press **Generate Preview PDF**.
8. Confirm the screen reports export success, file name, full saved path, byte
   count, and page count. The path is selectable.
9. Locate the file at the displayed path. On Android the debug exporter writes
   beneath the app cache at `Directory.systemTemp/talaan_scan/exports`; this
   requires no broad storage permission. Re-exporting the same template and
   version predictably overwrites the same file.
10. Copy the file from the device if needed and open it in a PDF viewer.
11. Confirm accented characters, Filipino text, smart punctuation, dashes, and
    the check mark render without missing glyphs.
12. Confirm all marker IDs, bubbles, page count, and content placement match the
    authoritative preview and no geometry shifted.

## Expected Filename

The name is lowercased, common Latin accents are folded, unsafe runs become a
single hyphen, the template version is appended, and `.pdf` is enforced. For
example, `Résumé – Survey` version 1 becomes `resume-survey-v1.pdf`.

## Record

- File name and full saved path
- Byte count and page count
- Unicode strings inspected
- Marker and bubble geometry result
- Any `EngineError` code, message, and details

Manual Android validation remains required until this procedure is completed
on a physical device.
