// ไฟล์: lib/main.dart
// แอป Medi-Ident AI: จุดเริ่มต้นของแอป (theme, locale) แล้วเปิด SplashScreen
// • ข้อมูลยามาจาก assets/data/meds.xlsm (สูงสุด 36 รายการ) รูปจาก
//   assets/images/amldac/<Name>.jpg และเสริมสรรพคุณฉบับเต็มจาก API
// • หน้าสแกน: ถ่ายรูป/เลือกจากแกลเลอรี ส่งให้ API ตรวจจับยา แล้วแสดงผล
// • ประวัติการสแกนเก็บไว้ใน SharedPreferences
// • โปรไฟล์ผู้ใช้งานเปลี่ยนชื่อและรูปโปรไฟล์ได้ (เก็บในเครื่อง)

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_skill/flutter_skill.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) FlutterSkillBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medi-Ident AI',
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
