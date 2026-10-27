import 'dart:convert';

import 'package:excel/excel.dart' as xlsx;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../models/med_item.dart';
import '../services/api_config.dart';

/// ที่เก็บข้อมูลสำหรับการโหลดและแคชข้อมูลยา
/// ใช้ไฟล์ Excel ที่แนบมากับแอปเป็นฐานเสมอ แล้วเสริมสรรพคุณฉบับเต็มจาก API
/// ในเบื้องหลัง (ไม่บล็อกการแสดงผล)
class MedRepository {
  static const String excelAsset = 'assets/data/meds.xlsm';
  static const String imgDir = 'assets/images/amldac/';
  static const String medicinesEndpoint = '$kApiBaseUrl/medicines/';

  /// ผลล่าสุดที่มี: รายการจาก Excel และถูกแทนด้วยรายการที่เสริม
  /// fullIndication แล้วเมื่อ API ตอบกลับ
  static List<MedItem>? _cache;
  static Future<List<MedItem>>? _excelFuture;
  static Future<List<MedItem>>? _enrichFuture;

  /// แปลงชื่อเป็นชื่อไฟล์ฐาน: เว้นวรรค -> "_" อักขระต้องห้าม -> "_"
  static String fileBase(String name) {
    var s = name.trim();
    s = s.replaceAll(RegExp(r'\s+'), '_');
    s = s.replaceAll(RegExp(r'[\\/:"*?<>|]'), '_');
    return s;
  }

  /// โหลดยาทั้งหมดจาก Excel แล้วคืนค่าทันที ส่วนสรรพคุณฉบับเต็มจาก API
  /// จะถูกเสริมในเบื้องหลัง เรียกครั้งถัดไปจะได้รายการที่เสริมแล้ว (ถ้าเสร็จ)
  /// หากต้องการรอผลจาก API ให้ใช้ [loadAllWithIndications]
  Future<List<MedItem>> loadAll() async {
    if (_cache != null) return _cache!;
    final base = await _loadExcelOnce();
    _startEnrichment(base);
    return _cache ?? base;
  }

  /// เหมือน [loadAll] แต่รอให้การเสริม fullIndication จาก API เสร็จก่อน
  /// (API ล้มเหลว = คืนรายการจาก Excel โดย fullIndication เป็น null)
  Future<List<MedItem>> loadAllWithIndications() async {
    final base = await _loadExcelOnce();
    return _startEnrichment(base);
  }

  Future<List<MedItem>> _loadExcelOnce() {
    return _excelFuture ??= _loadFromExcel().then((items) {
      _cache ??= items;
      return items;
    }, onError: (Object error, StackTrace stack) {
      _excelFuture = null; // ให้ลองใหม่ได้ในครั้งถัดไป
      return Future<List<MedItem>>.error(error, stack);
    });
  }

  Future<List<MedItem>> _startEnrichment(List<MedItem> base) {
    return _enrichFuture ??= _enrich(base);
  }

  Future<List<MedItem>> _enrich(List<MedItem> base) async {
    final indicationByName = await _loadFullIndicationsByBrandName();
    if (indicationByName == null) return base;

    final merged = base
        .map((med) => MedItem(
              name: med.name,
              description: med.description,
              imagePath: med.imagePath,
              fullIndication: _matchFullIndication(med.name, indicationByName),
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

  /// โหลดยาทั้งหมดจากไฟล์ Excel โดย parse ใน isolate แยก (ไฟล์ใหญ่ ถ้า parse
  /// บน UI isolate จะทำให้หน้าจอค้างบนเครื่องสเปกต่ำ)
  Future<List<MedItem>> _loadFromExcel() async {
    final bytes = (await rootBundle.load(excelAsset)).buffer.asUint8List();
    return compute(_parseMedsExcel, bytes);
  }
}

/// ต้องเป็นฟังก์ชัน top-level เพื่อส่งให้ [compute]
List<MedItem> _parseMedsExcel(Uint8List bytes) {
  final book = xlsx.Excel.decodeBytes(bytes);
  final sheet = book.tables.values.first;

  // แยกแถวส่วนหัว
  final headers =
      sheet.row(0).map((c) => (c?.value?.toString() ?? '').trim()).toList();

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

    final path = '${MedRepository.imgDir}${MedRepository.fileBase(name)}.jpg';
    out.add(MedItem(name: name, description: desc, imagePath: path));
  }

  return out;
}
