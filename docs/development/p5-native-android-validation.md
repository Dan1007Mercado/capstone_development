# P5 native Android validation

The P5 native gate remains **UNVERIFIED** until this harness passes on a real
Android device.

Connect the Android phone with USB debugging enabled, then:

1. Run `flutter devices`.
2. Run `flutter run -d <device-id>`.
3. On the default screen, open **P5 Native OpenCV Validation**.
4. Tap **Run Native ArUco Test**.
5. Copy the on-screen log or the console lines prefixed with `[P5_NATIVE]`.

`PASS` requires the Android OpenCV runtime to load, marker IDs 10, 11, 12, and
13 to be detected from the in-memory synthetic page, alignment to succeed, and
the canonical dimensions to match the `PageLayout` exactly. Send the complete
`[P5_NATIVE]` output for review.
