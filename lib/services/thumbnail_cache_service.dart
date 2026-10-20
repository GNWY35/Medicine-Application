import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ThumbnailCacheService {
  static final Map<String, Future<String?>> _cache = {};

  static Future<String?> getOrCreateThumbnail(
    String sourcePath, {
    int size = 120,
  }) {
    final key = '$sourcePath|$size';
    return _cache.putIfAbsent(
      key,
      () => _createThumbnail(sourcePath, size: size),
    );
  }

  static Future<String?> _createThumbnail(
    String sourcePath, {
    required int size,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return null;

    final cacheDir = await getTemporaryDirectory();
    final thumbDir = Directory('${cacheDir.path}/medicine_thumbnails');
    if (!await thumbDir.exists()) {
      await thumbDir.create(recursive: true);
    }

    final encoded = base64Url.encode(utf8.encode(sourcePath));
    final outputPath = '${thumbDir.path}/$encoded-$size.jpg';
    final outputFile = File(outputPath);
    if (await outputFile.exists()) return outputPath;

    return compute(
      _generateThumbnail,
      <String, dynamic>{
        'sourcePath': sourcePath,
        'outputPath': outputPath,
        'size': size,
      },
    );
  }
}

Future<String?> _generateThumbnail(Map<String, dynamic> request) async {
  try {
    final sourcePath = request['sourcePath'] as String;
    final outputPath = request['outputPath'] as String;
    final size = request['size'] as int;

    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final resized = img.copyResizeCropSquare(decoded, size: size);
    await File(outputPath).writeAsBytes(img.encodeJpg(resized, quality: 85));
    return outputPath;
  } catch (_) {
    return null;
  }
}
