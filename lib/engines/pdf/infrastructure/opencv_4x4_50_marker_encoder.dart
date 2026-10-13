import '../domain/aruco_marker_encoder.dart';

/// Pure-Dart encoder for OpenCV's stable DICT_4X4_50 dictionary.
///
/// Output uses an 8x8 grid: white quiet zone, black marker border, then the
/// canonical 4x4 payload. The first 50 canonical codewords are the prefix of
/// OpenCV's DICT_4X4_1000 table, as specified by DICT_4X4_50.
final class OpenCvDictionary4x4MarkerEncoder implements ArucoMarkerEncoder {
  const OpenCvDictionary4x4MarkerEncoder();

  @override
  ArucoDictionary get dictionary => ArucoDictionary.openCv4x4_50;

  @override
  ArucoMarkerMatrix encode(int markerId) {
    if (markerId < 0 || markerId >= _canonicalCodewords.length) {
      throw RangeError.range(
        markerId,
        0,
        _canonicalCodewords.length - 1,
        'markerId',
        'DICT_4X4_50 supports IDs 0 through 49.',
      );
    }

    final codeword = _canonicalCodewords[markerId];
    final modules = List.generate(
      8,
      (_) => List<bool>.filled(8, false),
      growable: false,
    );

    for (var index = 1; index <= 6; index++) {
      modules[1][index] = true;
      modules[6][index] = true;
      modules[index][1] = true;
      modules[index][6] = true;
    }

    for (var bitIndex = 0; bitIndex < 16; bitIndex++) {
      final byte = codeword[bitIndex ~/ 8];
      final isWhite = byte & (0x80 >> (bitIndex % 8)) != 0;
      final row = bitIndex ~/ 4 + 2;
      final column = bitIndex % 4 + 2;
      modules[row][column] = !isWhite;
    }

    return ArucoMarkerMatrix(
      dictionary: dictionary,
      markerId: markerId,
      modules: modules,
    );
  }
}

const List<List<int>> _canonicalCodewords = [
  [181, 50],
  [15, 154],
  [51, 45],
  [153, 70],
  [84, 158],
  [121, 205],
  [158, 46],
  [196, 242],
  [254, 218],
  [207, 86],
  [249, 145],
  [17, 167],
  [14, 183],
  [42, 15],
  [36, 177],
  [38, 62],
  [70, 101],
  [102, 0],
  [108, 94],
  [118, 175],
  [134, 139],
  [176, 43],
  [204, 213],
  [221, 130],
  [254, 71],
  [148, 113],
  [172, 228],
  [165, 84],
  [33, 35],
  [52, 111],
  [68, 21],
  [87, 178],
  [158, 207],
  [240, 203],
  [8, 174],
  [9, 41],
  [24, 117],
  [4, 255],
  [13, 246],
  [28, 90],
  [23, 24],
  [42, 40],
  [50, 140],
  [56, 178],
  [36, 232],
  [46, 235],
  [45, 63],
  [75, 100],
  [80, 46],
  [80, 19],
];
