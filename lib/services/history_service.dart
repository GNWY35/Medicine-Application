import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_record.dart';
import 'thumbnail_cache_service.dart';

/// การจัดการประวัติการสแกนด้วย SharedPreferences
class HistoryStore {
  static const _key = 'scan_history';
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// โหลดบันทึกประวัติทั้งหมดจัดเรียงตามล่าสุดก่อน
  static Future<List<HistoryRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];

    final list = (jsonDecode(raw) as List)
        .map((e) => HistoryRecord.fromJson(e))
        .toList();
    list.sort((a, b) => b.time.compareTo(a.time));
    return list;
  }

  /// เพิ่มบันทึกใหม่ลงในประวัติ
  static Future<void> addRecord(List<String> items,
      {String? imagePath, List<String?>? cropImagePaths}) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    list.insert(
        0,
        HistoryRecord(
          time: DateTime.now(),
          items: items,
          imagePath: imagePath,
          cropImagePaths: cropImagePaths,
        ));
    await prefs.setString(
      _key,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
    changes.value++;
  }

  /// ลบบันทึกประวัติทั้งหมด แล้วลบไฟล์รูปที่เกี่ยวข้อง (รูปสแกน, รูป crop,
  /// thumbnail) ในเบื้องหลังแบบ best-effort โดยไม่ให้ UI รอ
  static Future<void> clear() async {
    final records = await load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    changes.value++;
    unawaited(_deleteRecordFiles(records));
  }

  static Future<void> _deleteRecordFiles(List<HistoryRecord> records) async {
    final ownedDirs = await _appOwnedDirs();
    for (final rec in records) {
      for (final path in rec.cropImagePaths ?? const <String?>[]) {
        if (path != null) await _deleteIfOwned(path, ownedDirs);
      }
      final imagePath = rec.imagePath;
      if (imagePath != null) {
        await _deleteIfOwned(imagePath, ownedDirs);
        await ThumbnailCacheService.deleteFor(imagePath);
      }
    }
  }

  /// โฟลเดอร์ของแอปเอง: ลบเฉพาะไฟล์ในนี้ เพื่อไม่ลบรูปต้นฉบับของผู้ใช้
  /// (รูปจากกล้อง/แกลเลอรีถูกคัดลอกไว้ใน cache ของแอปอยู่แล้ว)
  static Future<List<String>> _appOwnedDirs() async {
    final dirs = <String>[];
    for (final getDir in <Future<Directory> Function()>[
      getTemporaryDirectory,
      getApplicationDocumentsDirectory,
      getApplicationSupportDirectory,
    ]) {
      try {
        dirs.add((await getDir()).path);
      } catch (_) {}
    }
    return dirs;
  }

  static Future<void> _deleteIfOwned(String path, List<String> ownedDirs) async {
    if (!ownedDirs.any((dir) => path.startsWith('$dir/'))) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
