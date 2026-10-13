# Template Versioning

Published templates are immutable.

## Draft

Editable.

Not guaranteed to have been printed.

## Published

Frozen.

May have physical sheets in circulation.

## Editing Published Templates

Never mutate an existing published definition.

Create a new version.

Example:

TemplateId:

research-survey-001

Versions:

1
2
3

## Printed Identity

A printed sheet must eventually encode:

- TemplateId
- TemplateVersion
- PageId

using a machine-readable identifier such as QR.

## Reason

A scanner must always resolve the exact geometry used to create the physical sheet.
