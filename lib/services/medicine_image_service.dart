import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Crops one square thumbnail per bbox and saves each as a JPEG.
///
/// The source photo is decoded once in a single background isolate.
/// The result has one entry per bbox, in the same order; an entry is null
/// when its bbox is missing/invalid or the crop failed.
Future<List<String?>> cropAndSaveMedicineImages(
  File imageFile,
  List<List<double>?> bboxes,
  List<String> names, {
  double expandRatio = 1.0,
  int outputSize = 72,
}) async {
  if (bboxes.isEmpty) return <String?>[];
  final dir = await getApplicationDocumentsDirectory();
  return compute(
    _cropAndSaveImagesInBackground,
    <String, dynamic>{
      'imagePath': imageFile.path,
      'bboxes': bboxes,
      'names': names,
      'outputDir': dir.path,
      'expandRatio': expandRatio,
      'outputSize': outputSize,
    },
  );
}

Future<List<String?>> _cropAndSaveImagesInBackground(
  Map<String, dynamic> request,
) async {
  final bboxes = (request['bboxes'] as List).cast<List<double>?>();
  final results = List<String?>.filled(bboxes.length, null);

  try {
    final imagePath = request['imagePath'] as String;
    final names = (request['names'] as List).cast<String>();
    final outputDir = request['outputDir'] as String;
    final expandRatio = request['expandRatio'] as double;
    final outputSize = request['outputSize'] as int;

    final bytes = await File(imagePath).readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return results;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < bboxes.length; i++) {
      final bbox = bboxes[i];
      if (bbox == null || bbox.length != 4) continue;
      try {
        final resized = _cropSquare(original, bbox, expandRatio, outputSize);
        final name = i < names.length ? names[i] : 'unknown';
        final outPath = '$outputDir/med_crop_${timestamp}_${i}_$name.jpg';
        await File(outPath).writeAsBytes(img.encodeJpg(resized));
        results[i] = outPath;
      } catch (_) {
        // Leave this entry null; other crops can still succeed.
      }
    }
  } catch (_) {
    // Unreadable or undecodable source: every entry stays null.
  }
  return results;
}

img.Image _cropSquare(
  img.Image original,
  List<double> bbox,
  double expandRatio,
  int outputSize,
) {
  final imgW = original.width.toDouble();
  final imgH = original.height.toDouble();
  final x1 = bbox[0].clamp(0, imgW);
  final y1 = bbox[1].clamp(0, imgH);
  final x2 = bbox[2].clamp(0, imgW);
  final y2 = bbox[3].clamp(0, imgH);

  final cropW = (x2 - x1).abs();
  final cropH = (y2 - y1).abs();
  final squareSize = math.max(cropW, cropH).toDouble() * expandRatio;
  final centerX = x1 + cropW / 2;
  final centerY = y1 + cropH / 2;

  double newX1 = centerX - squareSize / 2;
  double newY1 = centerY - squareSize / 2;

  newX1 = newX1.clamp(0, imgW - squareSize);
  newY1 = newY1.clamp(0, imgH - squareSize);

  final cropped = img.copyCrop(
    original,
    x: newX1.toInt(),
    y: newY1.toInt(),
    width: squareSize.toInt(),
    height: squareSize.toInt(),
  );

  return img.copyResize(cropped, width: outputSize, height: outputSize);
}
