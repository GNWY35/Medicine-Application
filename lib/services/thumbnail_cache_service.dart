import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ThumbnailCacheService {
  static final Map<String, Future<String?>> _cache = {};

  /// งาน decode ล่าสุดในคิว: สร้าง thumbnail ทีละรูป เพื่อไม่ให้ทุกแถวที่มองเห็น
  /// เปิด isolate decode รูปเต็มพร้อมกัน (หน่วยความจำ/CPU บนเครื่องสเปกต่ำ)
  static Future<void> _queueTail = Future<void>.value();

  static Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _queueTail.then((_) => task());
    _queueTail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

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

  /// ลบ thumbnail ทุกขนาดของ [sourcePath] (ทั้งในแคชหน่วยความจำและไฟล์)
  /// ไฟล์ที่ไม่มีอยู่หรือลบไม่ได้จะถูกข้าม
  static Future<void> deleteFor(String sourcePath) async {
    _cache.removeWhere((key, _) => key.startsWith('$sourcePath|'));
    try {
      final thumbDir = Directory(
        '${(await getTemporaryDirectory()).path}/medicine_thumbnails',
      );
      if (!await thumbDir.exists()) return;
      final prefix = '${base64Url.encode(utf8.encode(sourcePath))}-';
      await for (final entity in thumbDir.list()) {
        final name = entity.uri.pathSegments.last;
        if (entity is File && name.startsWith(prefix)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
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

    return _enqueue(
      () => compute(
        _generateThumbnail,
        <String, dynamic>{
          'sourcePath': sourcePath,
          'outputPath': outputPath,
          'size': size,
        },
      ),
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
