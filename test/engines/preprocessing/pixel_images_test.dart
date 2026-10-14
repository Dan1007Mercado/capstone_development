import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/preprocessing/domain/pixel_images.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final size = ImageSize(width: 3, height: 2);

  test('gray pixels use documented row-major indexing', () {
    final image = GrayImage(size: size, pixels: [10, 11, 12, 20, 21, 22]);

    expect(image.at(0, 0), 10);
    expect(image.at(2, 0), 12);
    expect(image.at(0, 1), 20);
    expect(image.at(2, 1), 22);
    expect(image.pixels, hasLength(size.area));
  });

  test('pixel buffers defensively copy and expose unmodifiable views', () {
    final source = [0, 1, 2, 3, 4, 5];
    final image = GrayImage(size: size, pixels: source);
    source[0] = 99;

    expect(image.at(0, 0), 0);
    expect(() => image.pixels[0] = 12, throwsUnsupportedError);
  });

  test('binary convention is one for ink and zero for paper', () {
    final image = BinaryImage(size: size, pixels: [0, 0, 1, 0, 1, 0]);

    expect(image.at(2, 0), isTrue);
    expect(image.at(0, 0), isFalse);
    expect(image.pixels.toSet(), {0, 1});
  });

  test('invalid buffer length and binary values are rejected', () {
    expect(() => GrayImage(size: size, pixels: [0]), throwsArgumentError);
    expect(
      () => BinaryImage(size: size, pixels: [0, 0, 2, 0, 0, 0]),
      throwsArgumentError,
    );
  });

  test('safe access rejects out-of-range coordinates', () {
    final image = GrayImage(size: size, pixels: List.filled(size.area, 0));
    expect(() => image.at(3, 0), throwsRangeError);
    expect(() => image.at(0, -1), throwsRangeError);
  });
}
