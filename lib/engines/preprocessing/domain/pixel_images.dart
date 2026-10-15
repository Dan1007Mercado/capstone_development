import 'dart:typed_data';

import '../../aruco/domain/image_geometry.dart';

/// Contiguous 8-bit grayscale pixels: 0 is black and 255 is white.
/// Storage is row-major with no stride: `index = y * width + x`.
final class GrayImage {
  GrayImage({required this.size, required List<int> pixels})
    : _pixels = _validatedCopy(size, pixels);

  GrayImage.owned({required this.size, required Uint8List pixels})
    : _pixels = _validateOwned(size, pixels);

  final ImageSize size;
  final Uint8List _pixels;

  Uint8List get pixels => _pixels.asUnmodifiableView();

  int at(int x, int y) {
    _checkCoordinates(size, x, y);
    return _pixels[y * size.width + x];
  }
}

/// Contiguous binary pixels: 1 is foreground/ink and 0 is background/paper.
/// Storage is row-major with no stride: `index = y * width + x`.
final class BinaryImage {
  BinaryImage({required this.size, required List<int> pixels})
    : _pixels = _validatedBinaryCopy(size, pixels);

  BinaryImage.owned({required this.size, required Uint8List pixels})
    : _pixels = _validateOwnedBinary(size, pixels);

  final ImageSize size;
  final Uint8List _pixels;

  Uint8List get pixels => _pixels.asUnmodifiableView();

  bool at(int x, int y) {
    _checkCoordinates(size, x, y);
    return _pixels[y * size.width + x] == 1;
  }
}

Uint8List _validatedCopy(ImageSize size, List<int> pixels) {
  if (pixels.length != size.area) {
    throw ArgumentError.value(
      pixels.length,
      'pixels',
      'Pixel count must equal width * height.',
    );
  }
  return Uint8List.fromList(pixels);
}

Uint8List _validatedBinaryCopy(ImageSize size, List<int> pixels) {
  if (pixels.any((pixel) => pixel != 0 && pixel != 1)) {
    throw ArgumentError.value(
      pixels,
      'pixels',
      'Binary pixels must contain only 0 and 1.',
    );
  }
  return _validatedCopy(size, pixels);
}

Uint8List _validateOwned(ImageSize size, Uint8List pixels) {
  if (pixels.length != size.area) {
    throw ArgumentError.value(
      pixels.length,
      'pixels',
      'Pixel count must equal width * height.',
    );
  }
  return pixels;
}

Uint8List _validateOwnedBinary(ImageSize size, Uint8List pixels) {
  if (pixels.any((pixel) => pixel != 0 && pixel != 1)) {
    throw ArgumentError.value(
      pixels,
      'pixels',
      'Binary pixels must contain only 0 and 1.',
    );
  }
  return _validateOwned(size, pixels);
}

void _checkCoordinates(ImageSize size, int x, int y) {
  if (x < 0 || x >= size.width || y < 0 || y >= size.height) {
    throw RangeError('Pixel ($x, $y) is outside ${size.width}x${size.height}.');
  }
}
