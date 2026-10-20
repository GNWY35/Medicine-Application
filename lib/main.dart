// ไฟล์: lib/main.dart
// ✅ แอป MyMedicine (Excel -> รูปภาพจาก assets/images/amldac/<Name>.jpg)
// • ไม่ใช้คอลัมน์ "รูปยา" ในไฟล์ Excel
// • จำกัดรายการสูงสุด 36 รายการ
// • ใช้นามสกุลไฟล์ .jpg เท่านั้น (ไม่ทำการเดานามสกุล)
// • มีฟีเจอร์อ่านออกเสียง (TTS) โดยใช้แพ็กเกจ flutter_tts
// • หน้าแรก: การ์ดยา (รูป + ชื่อ + สรรพคุณ) และ BottomSheet สำหรับรายละเอียด
// • หน้าสแกน (จำลอง): ถ่ายรูป/เลือกจากแกลเลอรี และพิมพ์ชื่อยา → แสดงผลลัพธ์
// • ประวัติการสแกนเก็บไว้ใน SharedPreferences
// • โปรไฟล์ผู้ใช้งานสามารถเปลี่ยนชื่อและเลือกรูปโปรไฟล์ได้ (local)

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_skill/flutter_skill.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) FlutterSkillBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyMedicine',
      debugShowCheckedModeBanner: false,
      supportedLocales: const [
        Locale('th', 'TH'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF06B6D4)),
        textTheme: GoogleFonts.kanitTextTheme(),
      ),
      home: const SplashScreen(),
    );
  }
}
