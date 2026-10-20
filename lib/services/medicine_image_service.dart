import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

Future<String?> cropAndSaveMedicineImage(
  File imageFile,
  List<double> bbox,
  String name, {
  double expandRatio = 1.0,
  int outputSize = 72,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  return compute(
    _cropAndSaveImageInBackground,
    <String, dynamic>{
      'imagePath': imageFile.path,
      'bbox': bbox,
      'name': name,
      'outputDir': dir.path,
      'expandRatio': expandRatio,
      'outputSize': outputSize,
    },
  );
}

Future<String?> _cropAndSaveImageInBackground(
  Map<String, dynamic> request,
) async {
  try {
    final imagePath = request['imagePath'] as String;
    final bbox = (request['bbox'] as List).cast<double>();
    final name = request['name'] as String;
    final outputDir = request['outputDir'] as String;
    final expandRatio = request['expandRatio'] as double;
    final outputSize = request['outputSize'] as int;

    final bytes = await File(imagePath).readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return null;

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

    final resized = img.copyResize(
      cropped,
      width: outputSize,
      height: outputSize,
    );

    final fileName =
        'med_crop_${DateTime.now().millisecondsSinceEpoch}_$name.jpg';
    final outPath = '$outputDir/$fileName';
    await File(outPath).writeAsBytes(img.encodeJpg(resized));
    return outPath;
  } catch (_) {
    return null;
  }
}
