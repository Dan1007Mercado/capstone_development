import 'dart:collection';

enum ArucoDictionary { openCv4x4_50 }

/// Pure data consumed by the PDF painter; true cells are printed black.
final class ArucoMarkerMatrix {
  ArucoMarkerMatrix({
    required this.dictionary,
    required this.markerId,
    required Iterable<Iterable<bool>> modules,
  }) : modules = UnmodifiableListView(
         modules
             .map((row) => UnmodifiableListView(List<bool>.of(row)))
             .toList(growable: false),
       ) {
    if (this.modules.isEmpty ||
        this.modules.any((row) => row.length != this.modules.length)) {
      throw ArgumentError('Marker modules must form a non-empty square.');
    }
  }

  final ArucoDictionary dictionary;
  final int markerId;
  final List<List<bool>> modules;

  int get moduleCount => modules.length;
}

abstract interface class ArucoMarkerEncoder {
  ArucoDictionary get dictionary;

  ArucoMarkerMatrix encode(int markerId);
}
