import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class ScanResult {
  const ScanResult.success({
    required this.detectedNames,
    required this.detectedBboxes,
  })  : errorMessage = null;

  const ScanResult.failure(this.errorMessage)
      : detectedNames = const [],
        detectedBboxes = const [];

  final List<String> detectedNames;
  final List<List<double>> detectedBboxes;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
}

const Duration _requestTimeout = Duration(seconds: 30);

Future<Map<String, dynamic>> sendImageToApi(File image) async {
  final uri = Uri.parse('$kApiBaseUrl/detect/');
  final request = http.MultipartRequest('POST', uri);
  request.files.add(await http.MultipartFile.fromPath('file', image.path));

  final streamed = await request.send().timeout(_requestTimeout);
  final response =
      await http.Response.fromStream(streamed).timeout(_requestTimeout);

  if (response.statusCode != 200) {
    throw Exception('Upload failed: ${response.statusCode}');
  }

  return json.decode(response.body) as Map<String, dynamic>;
}

List<double> _parseBbox(dynamic value) {
  final rawList = value is List ? value : const <dynamic>[];
  final numbers = rawList.whereType<num>().map((n) => n.toDouble()).toList();
  if (numbers.length >= 4) return numbers.take(4).toList();
  return [...numbers, ...List<double>.filled(4 - numbers.length, 0.0)];
}

List<dynamic> _extractDetections(Map<String, dynamic> body) {
  return (body['detection_data']?['detections'] ?? []) as List<dynamic>;
}

List<String> _extractDetectedNames(List<dynamic> detections, String fallback) {
  return detections
      .map((d) => (d['class'] ?? fallback).toString())
      .toList();
}

List<List<double>> _extractDetectedBboxes(List<dynamic> detections) {
  return detections.map((d) => _parseBbox(d['bbox'])).toList();
}

/// เรียก API วิเคราะห์ภาพยา แล้วคืนผลลัพธ์แบบ data-only
/// (ไม่ทำ Navigation หรือแสดง UI ใด ๆ — ผู้เรียกเป็นคนตัดสินใจเอง)
Future<ScanResult> analyzeImage(
  File image, {
  String fallbackName = 'Unknown',
}) async {
  try {
    final body = await sendImageToApi(image);
    final status = body['status'] ?? '';

    if (status != 'success') {
      final detail = body['detail'] ?? json.encode(body);
      return ScanResult.failure('Server error: $detail');
    }

    final detections = _extractDetections(body);
    if (detections.isEmpty) {
      return const ScanResult.failure('ตรวจไม่พบยาในภาพ');
    }

    detections.sort((a, b) {
      final left = (a['confidence'] ?? 0) as num;
      final right = (b['confidence'] ?? 0) as num;
      return right.compareTo(left);
    });

    return ScanResult.success(
      detectedNames: _extractDetectedNames(detections, fallbackName),
      detectedBboxes: _extractDetectedBboxes(detections),
    );
  } on HandshakeException catch (error) {
    debugPrint('analyzeImage handshake error: $error');
    return const ScanResult.failure(
      'เชื่อมต่อแบบปลอดภัยกับเซิร์ฟเวอร์ไม่สำเร็จ '
      'ลองใช้อินเทอร์เน็ตมือถือ หรือปิด VPN / Private DNS แล้วลองใหม่',
    );
  } on SocketException catch (error) {
    debugPrint('analyzeImage socket error: $error');
    return const ScanResult.failure(
      'ติดต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่',
    );
  } on TimeoutException catch (error) {
    debugPrint('analyzeImage timeout: $error');
    return const ScanResult.failure(
      'ติดต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่',
    );
  } catch (error) {
    return ScanResult.failure('อัปโหลดผิดพลาด: $error');
  }
}