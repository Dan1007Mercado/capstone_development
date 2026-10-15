# P13 Template Publication and Versioning

## Lifecycle

Templates follow one explicit lifecycle:

```text
Draft v1 -> validate -> publish -> Published v1
Published v1 -> create revision -> Draft v2 -> edit -> publish -> Published v2
```

A published `TemplateId` and `TemplateVersion` pair is immutable. Publishing
creates a frozen `TemplateDefinition`; it never changes the source draft and
never regenerates section, question, or option IDs. Editing requires a new
higher-version draft.

## Application Boundary

`TemplatePublicationService` coordinates:

- draft-status enforcement;
- `TemplateValidator` validation;
- next-version and duplicate checks;
- the explicit draft-to-published domain transition;
- persistence through `TemplateRepository`.

Expected lifecycle failures return `EngineResult` with structured
`EngineError` details. Widgets do not perform publication rules.

## Repository Contract

`TemplateRepository` stores and retrieves the current draft and exact
published versions. It supports lookup by `TemplateId + TemplateVersion`,
ordered published history, atomic non-overwrite of published versions, and
existence checks.

P13 uses `InMemoryTemplateRepository`. Its published history is ordered by
version and returned through unmodifiable collections. The stored domain graph
is immutable, so callers cannot mutate repository history through a retrieved
definition. Cloud synchronization is intentionally deferred.

The production dense-template path now persists the stronger
`PublishedTemplateArtifact` aggregate (definition, exact `LayoutDocument`, and
exact PDF bytes) in application-support storage. See
`published-template-artifact-persistence.md`. The original in-memory semantic
repository remains for draft/revision validation and legacy debug coverage.

## Revision Behavior

`TemplatePublicationService.createRevision` returns an editable draft while:

- preserving `TemplateId`;
- preserving section, question, and option IDs and content;
- changing status to `draft`;
- requiring a version strictly greater than the published source;
- choosing source version + 1 by default.

The default revision is sequential (`v1` creates `v2`). An explicitly selected
revision may be higher, but publication cannot go backward relative to stored
history. Existing published versions cannot be overwritten.

## Printed and Scanner Identity

LayoutEngine remains the only source of `PageId`. For the same published
definition and layout configuration, page identity remains deterministic:

```text
employee-survey + v1 -> employee-survey-v1-p1
employee-survey + v2 -> employee-survey-v2-p1
```

The PDF engine receives the exact published `TemplateDefinition` and matching
`LayoutDocument`. Marker IDs, registration geometry, bubble geometry, and
canonical dimensions are unchanged by P13.

## Manual Debug Validation

1. Open **P12 Template Builder** from the debug home.
2. Create a valid template.
3. Confirm the diagnostics show `Status: draft` and `Version: 1`.
4. Press **Publish Template**.
5. Confirm `Status: published`, `Version: 1`, and
   `Published successfully: v1`.
6. Try the semantic editor controls. They must remain disabled and must not
   modify the published definition.
7. Press **Create Revision**.
8. Confirm the same Template ID, `Status: draft`, and `Version: 2`.
9. Edit the revision and publish it.
10. Confirm the history shows `Published versions: v1, v2`.
11. Use **View Published v1** and **View Published v2**, preview each layout,
    and confirm their page IDs contain the corresponding version.
12. Confirm v1 content remains unchanged after v2 is published.

Manual debug validation remains required until this flow is exercised on a
running application.

## Non-goals

P13 does not add cloud persistence, synchronization, batch scanning, duplicate
response detection, review queues, or scan sessions. Those workflow concerns,
including P14, remain deferred. P13 does not change LayoutEngine spacing, PDF
geometry, scanner thresholds, ArUco geometry, bubble geometry, or camera logic.
