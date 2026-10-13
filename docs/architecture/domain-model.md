# Domain Model

Core semantic identities:

TemplateId

TemplateVersion

PageId

SectionId

QuestionId

OptionId

## Template Domain

TemplateDefinition

TemplateSection

TemplateQuestion

TemplateOption

QuestionType

## Layout Domain

PageSpec

PageMargins

PageLayout

MarkerRegion

QuestionRegion

BubbleRegion

NormalizedPoint

NormalizedRect

PhysicalPoint

PhysicalRect

CanonicalPageSpec

## Recognition Domain

BubbleMeasurement

OptionMeasurement

QuestionScanResult

MarkClassification

ScanResult

ScanFailure

AlignmentResult

ImageQualityResult

## Design Requirement

Models should remain independent from:

- Flutter widgets
- Firebase documents
- camera plugins
- OpenCV-specific types

Adapters may translate infrastructure values into domain values.
