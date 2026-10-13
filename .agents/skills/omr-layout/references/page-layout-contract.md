# PageLayout Contract

PageLayout is the authoritative geometric description of a generated page.

It is consumed by:

- PDF Engine
- Scanner Engine
- diagnostics
- geometry tests

## PageLayout

Should eventually identify:

- TemplateId
- TemplateVersion
- PageId
- page index
- total page count
- physical dimensions
- canonical specification
- printable region
- safe region
- marker regions
- marker homography reference points
- QR/template identity region
- question regions
- bubble regions

## BubbleRegion

Must identify:

- PageId
- QuestionId
- OptionId
- physical center/bounds
- normalized center/bounds
- expected bubble radius or dimensions

Each scannable bubble maps to exactly one semantic option.

## MarkerRegion

Must identify:

- marker ID
- semantic corner role
- physical bounds
- normalized bounds
- canonical registration reference point

## Determinism

Equivalent input produces equivalent output.

PDF rendering must not alter PageLayout geometry.

Scanner recognition must not create an alternative layout.
