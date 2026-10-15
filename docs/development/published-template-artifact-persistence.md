# Published Template Artifact Persistence

## Required Flow

```text
Publish Dense Template v1
  -> validate the draft
  -> build LayoutDocument with LayoutConfig.a4Dense()
  -> render the PDF from that exact LayoutDocument
  -> atomically save template + LayoutDocument + PDF bytes

Restart application
  -> reconstruct the file repository from application-support storage
  -> load Dense Template v1 without invoking LayoutEngine
  -> give the stored PageLayout directly to CameraScanContext
```

## Artifact Boundary

`PublishedTemplateArtifact` is the immutable aggregate for one
`TemplateId + TemplateVersion`. It contains:

- the published `TemplateDefinition`;
- the complete `LayoutDocument`, including physical and normalized geometry;
- the exact PDF bytes rendered from that layout.

`PublishedTemplateArtifactService` is the only application publication flow
for these durable artifacts. Validation, dense layout, and PDF rendering finish
before the aggregate is handed to the repository.

The file repository writes `artifact.json` and `template.pdf` into a staging
directory and renames that directory to its final version path. Existing
versions are never overwritten. SHA-256 values detect accidental modification
of the stored semantic/geometry manifest or PDF.

## Geometry Guarantee

PDF generation and scanning do not independently calculate geometry:

- the PDF stored in the artifact was rendered from the artifact's
  `LayoutDocument`;
- the scanner resolver loads the serialized `LayoutDocument` directly;
- `ScannerValidationSession` places each stored `PageLayout` into
  `CameraScanContext` by object identity;
- application restart does not run `LayoutEngine` for stored artifacts.

This prevents a future layout-engine or default-configuration change from
moving scanner ROIs away from already printed sheets.

## Local Storage

Production composition stores artifacts below the platform application-support
directory in `published_template_artifacts`. The repository boundary remains
independent of Flutter and can later be backed by another local store without
changing PDF or scanner engines.

The current schema version is `1`. Unknown schemas and corrupt artifacts fail
with structured errors rather than being silently regenerated.

## Debug Validation

1. Open **P12/P13 Template Builder**.
2. Press **Publish Dense Template v1**.
3. Confirm the screen reports that the exact PDF and PageLayout were saved.
4. Fully restart the application.
5. Open **Real Scanner Validation**.
6. Select `P13.6 Dense A4 Validation · v1`.
7. Confirm one page is available and begin scanning the previously saved PDF.

Automated coverage recreates the repository after publication and verifies the
reloaded template, PDF bytes, complete layout, and scanner page are equal to
the pre-restart artifact.

## Deferred Work

Cloud synchronization, artifact signing against malicious tampering, schema
migrations, and physical print/camera validation remain separate work. SHA-256
checks here provide corruption detection, not origin authentication.
