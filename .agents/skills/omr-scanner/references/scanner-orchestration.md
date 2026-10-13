# Scanner Orchestration

Expected pipeline:

Input Image
→ identify template/page
→ obtain PageLayout
→ detect ArUco
→ validate alignment
→ calculate homography
→ create canonical page
→ validate image quality
→ preprocess
→ sample bubble regions
→ calculate bubble measurements
→ classify question responses
→ validate scan
→ create ScanResult

## Fail Fast

Examples:

unknown template
→ TEMPLATE_NOT_FOUND

missing required marker
→ ALIGNMENT_FAILED

bad homography
→ ALIGNMENT_FAILED

unusable image
→ IMAGE_QUALITY_FAILED

invalid PageLayout
→ LAYOUT_INVALID

Do not continue downstream if an upstream stage invalidates the result.

## ScanResult

Should eventually contain:

- template ID
- template version
- page ID
- capture metadata
- alignment diagnostics
- image-quality diagnostics
- bubble measurements
- question results
- scan status
- review-required flag
- timing diagnostics

## Rule

Scanner Engine coordinates.

It does not own PDF layout logic or camera hardware configuration.
