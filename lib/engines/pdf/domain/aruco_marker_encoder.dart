import 'dart:collection';

enum ArucoDictionary { openCv4x4_50 }

/// Pure data consumed by the PDF painter; true cells are printed black.
final class ArucoMarkerMatrix {
  ArucoMarkerMatrix({
    required this.dictionary,
    required this.markerId,
    required this.quietZoneModules,
    required this.markerModules,
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
    if (quietZoneModules < 0 ||
        markerModules <= 0 ||
        totalModules != markerModules + quietZoneModules * 2) {
      throw ArgumentError('Marker module metadata does not match its matrix.');
    }
  }

  final ArucoDictionary dictionary;
  final int markerId;
  final int quietZoneModules;
  final int markerModules;
  final List<List<bool>> modules;

  int get totalModules => modules.length;
}

abstract interface class ArucoMarkerEncoder {
  ArucoDictionary get dictionary;

  ArucoMarkerMatrix encode(int markerId);
}
