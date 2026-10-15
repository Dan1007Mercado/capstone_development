import 'dart:io';

import 'package:camera/camera.dart' as camera;
import 'package:flutter/services.dart' show DeviceOrientation;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../domain/camera_backend.dart';
import '../domain/camera_engine_config.dart';
import '../domain/camera_models.dart';

final class FlutterCameraBackend implements CameraBackend {
  camera.CameraController? _controller;

  camera.CameraController? get controller => _controller;

  @override
  Future<EngineResult<CameraPreviewInfo>> initialize(
    CameraEngineConfig config,
  ) async {
    await dispose();
    try {
      final cameras = await camera.availableCameras();
      if (cameras.isEmpty) {
        return _failure('CAMERA_UNAVAILABLE', 'No camera device is available.');
      }
      final preferredDirection =
          config.preferredLens == CameraLensPreference.rear
          ? camera.CameraLensDirection.back
          : camera.CameraLensDirection.front;
      final description = cameras.cast<camera.CameraDescription?>().firstWhere(
        (candidate) => candidate?.lensDirection == preferredDirection,
        orElse: () => cameras.first,
      )!;
      final controller = camera.CameraController(
        description,
        _resolution(config.preferredResolution),
        enableAudio: false,
        fps: config.preferredPreviewFps,
        imageFormatGroup: camera.ImageFormatGroup.yuv420,
      );
      _controller = controller;
      await controller.initialize();

      var focusEnabled = false;
      var exposureEnabled = false;
      try {
        await controller.setFocusMode(camera.FocusMode.auto);
        focusEnabled = true;
      } on Object {
        // Optional capability; initialization remains useful without it.
      }
      try {
        await controller.setExposureMode(camera.ExposureMode.auto);
        exposureEnabled = true;
      } on Object {
        // Optional capability; initialization remains useful without it.
      }
      try {
        await controller.setFlashMode(camera.FlashMode.off);
      } on Object {
        // Flash-off is requested but unsupported flash hardware is acceptable.
      }

      final previewSize = controller.value.previewSize;
      if (previewSize == null) {
        await dispose();
        return _failure(
          'CAMERA_INITIALIZATION_FAILED',
          'Camera initialized without a preview size.',
        );
      }
      return EngineResult.success(
        CameraPreviewInfo(
          width: previewSize.width.round(),
          height: previewSize.height.round(),
          sensorOrientationDegrees: description.sensorOrientation,
          lens: _lens(description.lensDirection),
          automaticFocusEnabled: focusEnabled,
          automaticExposureEnabled: exposureEnabled,
          requestedPreviewFps: config.preferredPreviewFps,
        ),
      );
    } on camera.CameraException catch (error) {
      await dispose();
      return _cameraFailure(error, initialization: true);
    } on Object catch (error) {
      await dispose();
      return _failure(
        'CAMERA_INITIALIZATION_FAILED',
        'Camera initialization failed.',
        {'cause': error.toString()},
      );
    }
  }

  @override
  Future<EngineResult<bool>> startAnalysis(CameraFrameCallback onFrame) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _failure('CAMERA_STREAM_FAILED', 'Camera is not initialized.');
    }
    if (!controller.supportsImageStreaming()) {
      return _failure(
        'CAMERA_STREAM_FAILED',
        'The selected camera does not support image streaming.',
      );
    }
    try {
      await controller.startImageStream((image) {
        if (image.planes.isEmpty) return;
        final timestamp = DateTime.now();
        onFrame(timestamp, () {
          final luma = image.planes.first;
          return CameraAnalysisFrame(
            // CameraAnalysisFrame takes the single owned copy needed after
            // this native image callback returns.
            lumaBytes: luma.bytes,
            width: image.width,
            height: image.height,
            bytesPerRow: luma.bytesPerRow,
            bytesPerPixel: luma.bytesPerPixel ?? 1,
            timestamp: timestamp,
            sensorOrientationDegrees: controller.description.sensorOrientation,
            deviceOrientation: _orientation(controller.value.deviceOrientation),
          );
        });
      });
      return EngineResult.success(true);
    } on camera.CameraException catch (error) {
      return _failure(
        'CAMERA_STREAM_FAILED',
        'Camera analysis stream failed to start.',
        {'pluginCode': error.code, 'cause': error.description},
      );
    } on Object catch (error) {
      return _failure(
        'CAMERA_STREAM_FAILED',
        'Camera analysis stream failed to start.',
        {'cause': error.toString()},
      );
    }
  }

  @override
  Future<EngineResult<bool>> stopAnalysis() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return EngineResult.success(true);
    }
    if (!controller.value.isStreamingImages) {
      return EngineResult.success(true);
    }
    try {
      await controller.stopImageStream();
      return EngineResult.success(true);
    } on camera.CameraException catch (error) {
      return _failure(
        'CAMERA_STREAM_FAILED',
        'Camera analysis stream failed to stop.',
        {'pluginCode': error.code, 'cause': error.description},
      );
    }
  }

  @override
  Future<EngineResult<CapturedPageImage>> captureStill() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _failure('CAMERA_CAPTURE_FAILED', 'Camera is not initialized.');
    }
    String? capturedPath;
    try {
      final captured = await controller.takePicture();
      capturedPath = captured.path;
      final bytes = await captured.readAsBytes();
      if (bytes.isEmpty) {
        return _failure(
          'CAMERA_CAPTURE_FAILED',
          'Camera returned an empty still image.',
        );
      }
      return EngineResult.success(
        CapturedPageImage(
          encodedBytes: bytes,
          timestamp: DateTime.now(),
          sensorOrientationDegrees: controller.description.sensorOrientation,
          deviceOrientation: _orientation(controller.value.deviceOrientation),
          orientationAppliedByBackend: true,
        ),
      );
    } on camera.CameraException catch (error) {
      return _failure(
        'CAMERA_CAPTURE_FAILED',
        'High-quality still capture failed.',
        {'pluginCode': error.code, 'cause': error.description},
      );
    } on Object catch (error) {
      return _failure(
        'CAMERA_CAPTURE_FAILED',
        'High-quality still capture failed.',
        {'cause': error.toString()},
      );
    } finally {
      final path = capturedPath;
      if (path != null && path.isNotEmpty) {
        try {
          final temporaryFile = File(path);
          if (await temporaryFile.exists()) await temporaryFile.delete();
        } on Object {
          // The bytes are already owned. Platform temporary-file cleanup is
          // best effort and must not turn a valid capture into a failure.
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } on Object {
        // Disposal continues even if the stream was already closed natively.
      }
    }
    await controller.dispose();
  }

  EngineResult<T> _cameraFailure<T>(
    camera.CameraException error, {
    required bool initialization,
  }) {
    final permissionDenied = const {
      'CameraAccessDenied',
      'CameraAccessDeniedWithoutPrompt',
      'CameraAccessRestricted',
    }.contains(error.code);
    return _failure(
      permissionDenied
          ? 'CAMERA_PERMISSION_DENIED'
          : initialization
          ? 'CAMERA_INITIALIZATION_FAILED'
          : 'CAMERA_UNAVAILABLE',
      permissionDenied
          ? 'Camera permission was denied or restricted.'
          : 'Camera plugin operation failed.',
      {'pluginCode': error.code, 'cause': error.description},
    );
  }

  EngineResult<T> _failure<T>(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );

  static camera.ResolutionPreset _resolution(
    CameraResolutionPreference preference,
  ) => switch (preference) {
    CameraResolutionPreference.medium => camera.ResolutionPreset.medium,
    CameraResolutionPreference.high => camera.ResolutionPreset.high,
    CameraResolutionPreference.veryHigh => camera.ResolutionPreset.veryHigh,
    CameraResolutionPreference.ultraHigh => camera.ResolutionPreset.ultraHigh,
    CameraResolutionPreference.maximum => camera.ResolutionPreset.max,
  };

  static CameraLensPreference _lens(camera.CameraLensDirection direction) =>
      direction == camera.CameraLensDirection.front
      ? CameraLensPreference.front
      : CameraLensPreference.rear;

  static CameraDeviceOrientation _orientation(
    DeviceOrientation orientation,
  ) => switch (orientation) {
    DeviceOrientation.portraitUp => CameraDeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown => CameraDeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft => CameraDeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight => CameraDeviceOrientation.landscapeRight,
  };
}
