$ErrorActionPreference = 'Stop'

# Host requirements for opencv_dart 1.2.5:
# - A compiled OpenCV Dart dynamic library with contrib/aruco enabled.
# - OPENCV_DART_LIB_PATH set to that library, or its directory on PATH.
# - On Windows builds: Visual Studio 2019+ and Conan are required to compile it.
if ($env:OPENCV_DART_LIB_PATH -and
    -not (Test-Path -LiteralPath $env:OPENCV_DART_LIB_PATH)) {
  throw "OPENCV_DART_LIB_PATH does not exist: $env:OPENCV_DART_LIB_PATH"
}

flutter test `
  --dart-define=REQUIRE_NATIVE_OPENCV=true `
  test\engines\aruco\opencv_aruco_integration_test.dart

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
