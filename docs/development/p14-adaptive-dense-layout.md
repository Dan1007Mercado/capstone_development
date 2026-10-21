# p14 — Adaptive Dense OMR Layout

## Previous behavior

The dense profile used one fixed two-column configuration. The flow engine
already supported column cursors, multipage output, continuation fragments,
atomic question placement, and full-width fallback, but it did not compare
alternative safe column geometries. Question prompts were also inferred by the
PDF layer from the first bubble rather than exposed explicitly by PageLayout.

## Adaptive candidate strategy

Dense A4 layout now simulates fixed two-, three-, and four-column candidates.
Each candidate runs the normal deterministic measurement, flow, pagination,
materialization, and geometry-validation path. No PDF rendering, camera work,
OpenCV work, or rasterization occurs during selection.

Candidates are rejected when their columns are below the readable physical
width, bubbles violate the scanner-safe size, configuration is invalid, or a
question exceeds the allowed prompt wrapping. Valid candidates are ranked by:

1. page count,
2. unused content area,
3. excessive prompt wrapping,
4. full-width/mode fallbacks,
5. continuation fragments,
6. distance from the preferred three-column profile.

The page penalty dominates all secondary penalties. Selection is stable and
uses no random or input-order-dependent tie breaking. One column count is used
throughout the complete document.

`LayoutSelectionDiagnostics` exposes the selected column count and, for every
candidate, page count, unused area, rejected reasons, wrapping and fallback
counts, section fragments, inline/stacked counts, and final cost.

## Centralized constraints

`LayoutSelectionPolicy` owns adaptive tuning. Current initial values are:

- minimum column width: 34 mm,
- minimum inter-column gap: 4 mm (dense profile uses 6 mm),
- minimum bubble diameter: 5 mm,
- minimum bubble clearance: 1 mm,
- preferred/allowed prompt lines: 2/6,
- maximum horizontal option label length: 12 characters,
- page penalty: 10,000,
- unused-area penalty: 100,
- wrapping penalty: 100,
- full-width fallback penalty: 500,
- continuation-fragment penalty: 25,
- preferred-column deviation penalty: 25.

These are physical-layout policy values, not scanner classifier thresholds.

## Flow and measured blocks

Section leads and questions are measured before placement. A question plan
contains required height, prompt geometry and line count, render mode, bubble
offsets, option-cell width, and width validity. The flow state either places
the complete measured question or advances to the next column/page. Prompts,
options, and numeric grids are never split.

Sections do not reserve a whole-column rectangle. A section may produce
multiple `SectionRegion` fragments. Only the first fragment contains the title,
instructions, and human-readable field; continuations preserve `sectionId` and
do not repeat those leads.

## Question render modes

`QuestionRegion` now records its authoritative `promptRegion`, line count, and
one of these render modes:

- `inlineHorizontal`: compact Likert and yes/no prompt plus option row,
- `stackedHorizontal`: prompt above short horizontal options,
- `stackedVertical`: prompt above readable wrapped option rows,
- `numericGrid`: unsplit grid geometry.

Long labels deterministically select vertical mode. Wide numeric grids may use
the existing full-width question representation (`columnIndex == null`) or may
cause selection of a wider document profile. The PDF renderer consumes the
stored prompt, bubble, and render-mode geometry and does not repeat layout
decisions.

## Multipage behavior

Questions flow in template order through column 1, column 2, and subsequent
columns before a new page is added. Page IDs, marker signatures, zero-based page
indices, and final `totalPageCount` remain deterministic. The 12-question flow
fixture currently selects three columns and one page. The 60-question mixed
fixture selects two columns and two pages.

The existing `templateIdentityRegion` remains the deterministic reserved area
for template/page identity and future respondent metadata. p14 does not add a
respondent identifier or print-batch format.

## Geometry guarantees

Generated documents validate:

- page index and total-page consistency,
- safe, non-overlapping columns,
- section/question assignment and overlap,
- prompt and bubble containment,
- marker, header, and identity exclusion,
- minimum bubble diameter and clearance,
- unique questions in exact template order,
- section order and continuation identity,
- complete template question coverage.

PageLayout remains the sole geometry source for the PDF and scanner.

## Automated coverage

The p14 suite covers adaptive selection, safe three/four-column candidates,
long-prompt rejection, atomic placement, column/page continuation, a 60-question
mixed multipage form, mixed question semantics, vertical long-option fallback,
numeric grids, bubble safety, order/uniqueness, determinism, shared PDF/scanner
geometry, A4/ArUco exclusions, candidate safety, continuation identity, and
page-count metadata. Existing layout, PDF, artifact persistence, scanner, and
recognition suites remain regression gates.

## Remaining physical validation

Print the winning layouts at actual size and verify text readability, 5 mm
bubble usability, inter-column separation, marker quiet zones, and recognition
on multiple printers and Android devices. In particular, validate the inline
Likert/yes-no mode, vertically wrapped long options, page edges, and the future
identity reservation under real printer scaling. Automated geometry tests do
not replace physical print/scan validation.
