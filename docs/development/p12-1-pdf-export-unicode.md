# P12.1.1 User-Accessible PDF Export and Unicode Manual Validation

## Export Approach

The debug builder uses `file_picker` for one purpose: pass the generated PDF
bytes to the platform save dialog. On Android this provides the system document
picker and a user-selected destination without broad storage permissions. The
internal IO exporter remains available for deterministic tests and internal
temporary-file workflows, but it is not the Android screen's default exporter.

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
8. Confirm the screen reports generation success, file name, byte count, and
   page count.
9. Press **Save PDF**.
10. In the Android system document picker, choose a user-accessible location
    such as **Downloads** or **Documents**, then confirm the save.
11. Confirm the screen reports **PDF saved successfully**. A returned Android
    content URI may be shown for diagnostics; it is not a filesystem path.
12. Open the Android **Files** app, locate the saved PDF, and open it in a PDF
    viewer.
13. Confirm accented characters, Filipino text, smart punctuation, dashes, and
    the check mark render without missing glyphs.
14. Confirm all marker IDs, bubbles, page count, and content placement match the
    authoritative preview and no geometry shifted.

Closing the system picker is a normal cancellation. The screen should keep the
generated PDF available and allow **Save PDF** to be pressed again without
showing an engine failure.

## Expected Filename

The name is lowercased, common Latin accents are folded, unsafe runs become a
single hyphen, the template version is appended, and `.pdf` is enforced. For
example, `Résumé – Survey` version 1 becomes `resume-survey-v1.pdf`.

## Record

- File name and chosen destination (or returned URI, when shown)
- Byte count and page count
- Unicode strings inspected
- Marker and bubble geometry result
- Any `EngineError` code, message, and details

Manual Android validation remains required until this procedure is completed
on a physical device.
