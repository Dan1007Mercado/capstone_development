# ArUco and Homography

## Purpose

ArUco markers establish geometric correspondence between a photographed physical sheet and the canonical page.

ArUco is not the answer classifier.

## Four Marker Model

Use:

top-left  
top-right  
bottom-left  
bottom-right

Each has a unique ID.

## Detection Result

The ArUco engine should eventually return:

- marker ID
- four detected marker corners
- marker center if useful
- diagnostic quality information

## Semantic Ordering

Detector output ordering is irrelevant.

Marker ID determines its page role.

## Registration Points

Homography uses explicitly defined registration points.

Do not automatically use marker centers.

The physical marker corner corresponding to the internal page area is often a better registration reference when the layout is designed accordingly.

The exact convention must be defined once and shared by print and scan.

## Homography

Given four or more corresponding source and destination points:

p' ~ H p

where H is a projective transformation matrix.

After transformation, the photographed sheet becomes a canonical top-down page.

## Rule

All bubble recognition occurs after alignment into canonical space.
