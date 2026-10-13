# Regression Testing

OMR development requires reproducible image fixtures.

## Known-answer Fixture

Each image should have:

- source template
- exact template version
- expected page
- expected responses
- expected invalid/ambiguous conditions

## Synthetic Transformations

Generated clean sheets may be transformed with controlled:

- perspective
- rotation
- blur
- brightness
- contrast
- noise
- shadows

Synthetic tests complement physical tests.

They do not replace physical printed-sheet testing.

## Bug Regression

When a real scan exposes a bug:

1. preserve the image if legally/ethically permitted
2. define expected behavior
3. create a regression test
4. fix the engine
5. ensure the test remains in the suite

## Metrics

Measure:

- accepted scan accuracy
- incorrect-response rate
- ambiguous-response rate
- rejected scan rate
- average processing time

Never report accuracy without clarifying how rejected scans are handled.
