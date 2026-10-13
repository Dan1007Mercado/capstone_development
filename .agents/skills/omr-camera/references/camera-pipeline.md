# Camera Pipeline

Recommended architecture:

Camera Device
       |
       +-------------------------+
       |                         |
       v                         v
Live Preview               Analysis Frames
30/60 FPS                  throttled
                                 |
                                 v
                           ArUco Tracking
                                 |
                                 v
                          Page Geometry
                                 |
                                 v
                           Quality Checks
                                 |
                                 v
                          Stability Window
                                 |
                                 v
                            Auto Capture
                                 |
                                 v
                       High-quality Image
                                 |
                                 v
                          Scanner Engine

## Preview

Preview should remain smooth.

Do not equate preview FPS with analysis FPS.

## Analysis Frames

A reduced analysis frequency is expected.

Initial exploration may test approximately 8-15 FPS.

Do not treat this as a universal constant.

Profile on real devices.

## Recognition

Full bubble recognition should normally occur after stable capture rather than on every live frame.

## Capture

Final capture should prioritize enough spatial detail to measure bubbles reliably.
