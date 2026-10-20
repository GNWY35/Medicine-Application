import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_record.dart';

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

  /// ลบบันทึกประวัติทั้งหมด
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    // ลบไฟล์รูปที่ crop ไว้ทั้งหมด
    final raw = prefs.getString(_key);
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => HistoryRecord.fromJson(e))
          .toList();
      for (final rec in list) {
        if (rec.cropImagePaths != null) {
          for (final path in rec.cropImagePaths!) {
            if (path != null) {
              final file = File(path);
              if (await file.exists()) {
                try {
                  await file.delete();
                } catch (_) {}
              }
            }
          }
        }
      }
    }
    await prefs.remove(_key);
    changes.value++;
  }
}
