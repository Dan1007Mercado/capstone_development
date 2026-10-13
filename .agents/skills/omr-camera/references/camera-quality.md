# Camera Quality Metrics

The Camera Engine should eventually calculate real quality measurements.

## Blur

Potential measurement:

variance of Laplacian or equivalent focus metric.

Threshold must be device/test calibrated.

## Exposure

Detect:

- excessive underexposure
- excessive overexposure
- clipped regions

## Page Size

The document should occupy enough frame area for reliable detection.

## Perspective

Reject or warn on extreme perspective that may degrade recognition.

## Marker Stability

Require stable marker geometry over several observations before auto capture.

## Motion

Large frame-to-frame marker displacement indicates camera or sheet movement.

## Auto Capture

Auto capture should require all critical checks to remain acceptable for a small stability window.

Do not auto capture based on a single frame.
