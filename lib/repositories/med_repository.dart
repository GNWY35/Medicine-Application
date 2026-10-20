import 'dart:convert';

import 'package:excel/excel.dart' as xlsx;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../models/med_item.dart';
import '../services/api_config.dart';

const Map<String, String> kImageOverrides = <String, String>{};

/// ที่เก็บข้อมูลสำหรับการโหลดและแคชข้อมูลยา
/// พยายามโหลดจาก API ก่อน หากล้มเหลว (ไม่มีเน็ต/เซิร์ฟเวอร์ล่ม) จะ fallback
/// ไปโหลดจากไฟล์ Excel ที่แนบมากับแอปแทน
class MedRepository {
  static const String excelAsset = 'assets/data/meds.xlsm';
  static const String imgDir = 'assets/images/amldac/';
  static const String medicinesEndpoint = '$kApiBaseUrl/medicines/';

  static List<MedItem>? _cache;

  /// แปลงชื่อเป็นชื่อไฟล์ฐาน: เว้นวรรค -> "_" อักขระต้องห้าม -> "_"
  String _fileBase(String name) {
    var s = name.trim();
    s = s.replaceAll(RegExp(r'\s+'), '_');
    s = s.replaceAll(RegExp(r'[\\/:"*?<>|]'), '_');
    return s;
  }

  /// โหลดยาทั้งหมด: ใช้ Excel เป็นฐานเสมอ (ชื่อ/สรรพคุณย่อ/รูป) เพราะเป็นไฟล์
  /// ที่แนบมากับแอป โหลดได้ทันทีแม้ไม่มีเน็ต จากนั้นพยายามเสริมสรรพคุณฉบับเต็ม
  /// จาก API (DB) เข้าไปในรายการเดิม หาก API ใช้ไม่ได้ก็ไม่เป็นไร - ปล่อยให้
  /// fullIndication เป็น null (จะ fallback ไปใช้สรรพคุณย่อตอนแสดงผล)
  /// (มีแคชแบบ static เหมือนเดิม)
  Future<List<MedItem>> loadAll() async {
    if (_cache != null) return _cache!;

    final base = await _loadFromExcel();
    final indicationByName = await _loadFullIndicationsByBrandName();

    final merged = indicationByName == null
        ? base
        : base
            .map((med) => MedItem(
                  name: med.name,
                  description: med.description,
                  imagePath: med.imagePath,
                  fullIndication: _matchFullIndication(
                    med.name,
                    indicationByName,
                  ),
                ))
            .toList();

    return _cache = merged;
  }

  /// จับคู่ชื่อยาแบบ Excel (Brand_Generic เช่น "Ambes_Amlodipine") กับ
  /// brand_name จาก API (เช่น "Ambes"): ตรงกันทั้งหมด (ไม่มี generic ต่อท้าย)
  /// หรือขึ้นต้นด้วย `brand_name` ตามด้วย "_" (ไม่สนตัวพิมพ์เล็ก/ใหญ่)
  String? _matchFullIndication(
    String excelName,
    Map<String, String> indicationByBrandName,
  ) {
    final lower = excelName.toLowerCase();
    for (final entry in indicationByBrandName.entries) {
      if (lower == entry.key || lower.startsWith('${entry.key}_')) {
        return entry.value;
      }
    }
    return null;
  }

  /// โหลด indications ฉบับเต็มจาก API เก็บเป็น map: brand_name (lowercase) -> indications
  /// คืนค่า null หากเกิดข้อผิดพลาดใด ๆ (จะไม่บล็อกแอป - แค่ไม่มีข้อมูลเสริม)
  Future<Map<String, String>?> _loadFullIndicationsByBrandName() async {
    try {
      final response = await http
          .get(Uri.parse(medicinesEndpoint))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final decoded = json.decode(response.body);
      if (decoded is! List) return null;

      final out = <String, String>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final brandName = (item['brand_name'] ?? '').toString().trim();
        final indications = (item['indications'] ?? '').toString().trim();
        if (brandName.isEmpty || indications.isEmpty) continue;
        out[brandName.toLowerCase()] = indications;
      }

      return out;
    } catch (error) {
      debugPrint('MedRepository: failed to load indications from API: $error');
      return null;
    }
  }

  /// โหลดยาทั้งหมดจากไฟล์ Excel (fallback แบบเดิม)
  Future<List<MedItem>> _loadFromExcel() async {
    final bytes = (await rootBundle.load(excelAsset)).buffer.asUint8List();
    final book = xlsx.Excel.decodeBytes(bytes);
    final sheet = book.tables.values.first;

    // แยกแถวส่วนหัว
    final headers = sheet
        .row(0)
        .map((c) => (c?.value?.toString() ?? '').trim())
        .toList();
    
    int idxOf(String h) =>
        headers.indexWhere((x) => x.toLowerCase() == h.toLowerCase());

    final idxName = idxOf('ชื่อยาความดันโลหิตสูง(ยี่ห้อยา_ชื่อยา)');
    final idxDesc = idxOf('สรรพคุณ');

    final out = <MedItem>[];
    for (int r = 1; r < sheet.maxRows && out.length < 36; r++) {
      final row = sheet.row(r);
      String cell(int i) => (i >= 0 && i < row.length && row[i] != null)
          ? row[i]!.value.toString().trim()
          : '';

      final name = cell(idxName);
      final desc = cell(idxDesc);
      if (name.isEmpty && desc.isEmpty) continue;

      final base = _fileBase(name);
      final path = kImageOverrides[name] ?? '$imgDir$base.jpg';

      out.add(MedItem(name: name, description: desc, imagePath: path));
    }

    return out;
  }
}
