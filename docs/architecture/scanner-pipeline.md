# Scanner Pipeline

## Offline Full Scan

Captured Image

↓

Template/Page Identification

↓

Resolve PageLayout

↓

ArUco Detection

↓

Alignment Validation

↓

Homography

↓

Canonical Page

↓

Image Quality Validation

↓

Preprocessing

↓

Bubble ROI Sampling

↓

Bubble Measurements

↓

Question Classification

↓

Scan Validation

↓

ScanResult

## Live Camera Pipeline

Camera Preview

+

Throttled Analysis Stream

↓

ArUco Detection

↓

Geometry Tracking

↓

Image Quality Measurements

↓

Stability Window

↓

Auto Capture

↓

Offline Full Scan Pipeline

## Important Separation

The live analysis stream primarily helps find and capture a suitable page.

It does not need to execute the complete OMR classifier on every frame.
