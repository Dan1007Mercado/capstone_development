// Offline pixel observations; never used to correct production geometry.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as im;
import 'package:capstone_development/application/published_templates/published_template_artifact_codec.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';

void main(List<String> args) {
  final output = Directory('docs/development/evidence/p15_7')
    ..createSync(recursive: true);
  final manifest =
      jsonDecode(
            File(
              'test/fixtures/p15_6/published_manifest.json',
            ).readAsStringSync(),
          )
          as Map;
  final page = const PublishedTemplateArtifactCodec()
      .decode((manifest['artifact'] as Map).cast<String, Object?>())
      .layout
      .pages
      .single;
  final results = <Object?>[];
  final folder = args.isEmpty ? 'build/p157' : args[0];
  for (final file in Directory('images_samples').listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    final report =
        jsonDecode(
              File(
                'docs/development/evidence/p15_6/$name.json',
              ).readAsStringSync(),
            )
            as Map;
    final snapshot = report['fourPoint']['snapshot'] as Map?;
    if (snapshot == null) continue;
    final h = HomographyMatrix(
      (snapshot['homography'] as List).cast<num>().map((v) => v.toDouble()),
    );
    final inverse = h.inverse();
    final source = im
        .decodeImage(file.readAsBytesSync())!
        .convert(numChannels: 1);
    final landmarks = <Object?>[];
    // Restrict association to the existing expected neighborhood; centers are
    // measured from connected outer-ink bounds, not ring-contrast maximization.
    for (final bubble in page.bubbleRegions) {
      final expected = ImagePoint(
        bubble.physicalCenter.x.millimeters * 10,
        bubble.physicalCenter.y.millimeters * 10,
      );
      final predicted = inverse.project(expected);
      final candidates = components(
        source,
        predicted.x.round() - 48,
        predicted.y.round() - 48,
        96,
        96,
      );
      final valid = candidates
          .where(
            (b) =>
                b[2] >= 32 &&
                b[2] <= 70 &&
                b[3] >= 32 &&
                b[3] <= 70 &&
                b[2] / b[3] > .7 &&
                b[2] / b[3] < 1.4,
          )
          .toList();
      valid.sort(
        (a, b) => center(
          a,
        ).distanceTo(predicted).compareTo(center(b).distanceTo(predicted)),
      );
      if (valid.isEmpty) continue;
      final bounds = valid.first;
      final observed = center(bounds);
      final projected = h.project(observed);
      landmarks.add({
        'question': bubble.questionId.value,
        'target': bubble.optionId?.value,
        'expected': [expected.x, expected.y],
        'source': [observed.x, observed.y],
        'sourceInkBounds': bounds,
        'fourPoint': [projected.x, projected.y],
        'residual': [projected.x - expected.x, projected.y - expected.y],
      });
    }
    results.add({'file': name, 'landmarks': landmarks});
    if (name == 'unmarked.jpg') {
      final crop = im.copyCrop(source, x: 465, y: 635, width: 365, height: 970);
      File(
        '${output.path}/unmarked_source_bubbles.png',
      ).writeAsBytesSync(im.encodePng(crop));
      // Fixed source-coordinate crops with rulers for independent visual review.
      const origins = [
        (470, 630),
        (745, 645),
        (470, 750),
        (680, 765),
        (475, 1060),
        (615, 1185),
        (550, 1420),
        (480, 1540),
      ];
      final sheet = im.Image(width: 640, height: 1280)
        ..clear(im.ColorRgb8(255, 255, 255));
      for (var i = 0; i < origins.length; i++) {
        final (x, y) = origins[i];
        final tile = im
            .copyResize(
              im.copyCrop(source, x: x, y: y, width: 90, height: 90),
              width: 270,
              height: 270,
            )
            .convert(numChannels: 3);
        for (var grid = 0; grid < 90; grid += 10) {
          im.drawLine(
            tile,
            x1: grid * 3,
            y1: 0,
            x2: grid * 3,
            y2: 269,
            color: im.ColorRgba8(0, 130, 255, 75),
          );
          im.drawLine(
            tile,
            x1: 0,
            y1: grid * 3,
            x2: 269,
            y2: grid * 3,
            color: im.ColorRgba8(0, 130, 255, 75),
          );
        }
        final dx = i % 2 * 320, dy = i ~/ 2 * 320;
        im.compositeImage(sheet, tile, dstX: dx, dstY: dy + 30);
        im.drawString(
          sheet,
          '$i origin $x,$y; grid10',
          font: im.arial14,
          x: dx,
          y: dy,
          color: im.ColorRgb8(0, 0, 0),
        );
      }
      File(
        '${output.path}/source_review_grid.png',
      ).writeAsBytesSync(im.encodePng(sheet));
    }
  }
  File('${output.path}/source_landmarks.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'provenance':
          'Source-image connected outer-ink bounds at intensity <110; algorithmic proposals, analyst visual review recorded separately; not human ground truth.',
      'results': results,
    }),
  );
  for (final pdfFile in Directory(
    folder,
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.bmp'))) {
    final rgba = im.decodeImage(pdfFile.readAsBytesSync())!;
    // PdfRenderer leaves the page background transparent. Composite onto
    // paper before grayscale conversion; dropping alpha makes paper black.
    for (final pixel in rgba) {
      final alpha = pixel.a / 255;
      pixel.setRgba(
        (pixel.r * alpha + 255 * (1 - alpha)).round(),
        (pixel.g * alpha + 255 * (1 - alpha)).round(),
        (pixel.b * alpha + 255 * (1 - alpha)).round(),
        255,
      );
    }
    // PDFium output has an explicitly controlled size; no geometric resize.
    if (rgba.width != 2100 || rgba.height != 2970) {
      throw StateError('Expected exact-size PDFium raster');
    }
    final raster = rgba.convert(numChannels: 1);
    final measurements = <Object?>[];
    for (final bubble in page.bubbleRegions) {
      final x = bubble.physicalCenter.x.millimeters * 10;
      final y = bubble.physicalCenter.y.millimeters * 10;
      final ring = components(
        raster,
        x.round() - 31,
        y.round() - 31,
        63,
        63,
      ).where((b) => b[2] > 40 && b[3] > 40).toList();
      measurements.add({
        'target': bubble.optionId?.value,
        'expected': [x, y],
        'inkComponents': ring,
        'observed': ring.isEmpty
            ? null
            : [center(ring.first).x, center(ring.first).y],
      });
    }
    final name = pdfFile.uri.pathSegments.last;
    final markerMeasurements = [
      for (final marker in page.markerRegions)
        {
          'id': marker.markerId,
          'expectedBounds': [
            marker.physicalMarkerBounds.left.millimeters * 10,
            marker.physicalMarkerBounds.top.millimeters * 10,
            marker.physicalMarkerBounds.width.millimeters * 10,
            marker.physicalMarkerBounds.height.millimeters * 10,
          ],
          'inkComponents': components(
            raster,
            (marker.physicalBounds.left.millimeters * 10).round(),
            (marker.physicalBounds.top.millimeters * 10).round(),
            140,
            140,
          ),
        },
    ];
    File('${output.path}/$name.measurements.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'width': raster.width,
        'height': raster.height,
        'measurements': measurements,
        'markers': markerMeasurements,
      }),
    );
    File('${output.path}/$name.bubbles.png').writeAsBytesSync(
      im.encodePng(
        im.copyCrop(raster, x: 300, y: 470, width: 365, height: 1000),
      ),
    );
  }
  final detectionFile = File('$folder/detections.json');
  if (detectionFile.existsSync()) {
    final detections = jsonDecode(detectionFile.readAsStringSync()) as List;
    for (final name in ['all_marked.jpg', 'blank_tilted.jpg', 'unmarked.jpg']) {
      final source = im.decodeImage(
        File('images_samples/$name').readAsBytesSync(),
      )!;
      if (name == 'all_marked.jpg') {
        File('${output.path}/all_marked_missing12.png').writeAsBytesSync(
          im.encodePng(
            im.copyResize(
              im.copyCrop(source, x: 2890, y: 1960, width: 190, height: 190),
              width: 380,
            ),
          ),
        );
      }
      final observations =
          detections
                  .where((d) => d['file'] == name && d['mode'] == 'baseline')
                  .single['markers']
              as List;
      for (var i = 0; i < observations.length; i++) {
        final m = observations[i];
        final points = (m['corners'] as List).cast<List>();
        final left =
            points.map((p) => (p[0] as num).floor()).reduce(math.min) - 15;
        final top =
            points.map((p) => (p[1] as num).floor()).reduce(math.min) - 15;
        final right =
            points.map((p) => (p[0] as num).ceil()).reduce(math.max) + 15;
        final bottom =
            points.map((p) => (p[1] as num).ceil()).reduce(math.max) + 15;
        File('$folder/${name}_marker_${m['id']}_$i.png').writeAsBytesSync(
          im.encodePng(
            im.copyResize(
              im.copyCrop(
                source,
                x: left,
                y: top,
                width: right - left,
                height: bottom - top,
              ),
              width: 320,
            ),
          ),
        );
      }
    }
  }
}

ImagePoint center(List<int> b) =>
    ImagePoint(b[0] + (b[2] - 1) / 2, b[1] + (b[3] - 1) / 2);

List<List<int>> components(
  im.Image image,
  int left,
  int top,
  int width,
  int height,
) {
  final visited = Uint8List(width * height);
  final result = <List<int>>[];
  bool dark(int x, int y) => image.getPixel(x + left, y + top).r < 110;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      if (visited[index] != 0 || !dark(x, y)) continue;
      final queue = <int>[index];
      visited[index] = 1;
      var minX = x, maxX = x, minY = y, maxY = y;
      for (var i = 0; i < queue.length; i++) {
        final px = queue[i] % width, py = queue[i] ~/ width;
        minX = math.min(minX, px);
        maxX = math.max(maxX, px);
        minY = math.min(minY, py);
        maxY = math.max(maxY, py);
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = px + dx, ny = py + dy;
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
            final next = ny * width + nx;
            if (visited[next] != 0 || !dark(nx, ny)) continue;
            visited[next] = 1;
            queue.add(next);
          }
        }
      }
      if (queue.length > 20) {
        result.add([
          left + minX,
          top + minY,
          maxX - minX + 1,
          maxY - minY + 1,
          queue.length,
        ]);
      }
    }
  }
  return result;
}
