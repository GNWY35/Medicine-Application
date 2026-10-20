import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/scan_api_service.dart';
import 'realtime_detection_page.dart';
import 'scan_result_page.dart';

class ScanMedicinePage extends StatefulWidget {
  const ScanMedicinePage({super.key});

  @override
  State<ScanMedicinePage> createState() => _ScanMedicinePageState();
}

class _ScanMedicinePageState extends State<ScanMedicinePage> {
  static const String _autosavePreferenceKey = 'scan_autosave_enabled';

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();

  File? _image;
  bool _autosaveEnabled = true;

  Future<void> _pickGallery() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted || image == null) return;
    setState(() => _image = File(image.path));
  }

  Future<void> _openRealtime() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isDenied) {
      _showSnackBar('สิทธิ์การใช้กล้องถูกปฏิเสธ');
      return;
    }
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }

    final resultPath = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => const RealtimeDetectionPage()),
    );

    // Realtime Scan ส่ง path รูปที่ถ่ายกลับมา → ตั้งเป็นรูป preview
    if (!mounted || resultPath == null || resultPath.isEmpty) return;
    setState(() => _image = File(resultPath));
  }

  Future<void> _goToResult() async {
  if (_image == null) {
    _showSnackBar('โปรดถ่ายรูปหรือเลือกภาพยาก่อนดูผลลัพธ์');
    return;
  }

  final result = await analyzeImage(
    _image!,
    fallbackName: _nameController.text.trim().isEmpty
        ? 'Unknown'
        : _nameController.text.trim(),
  );

  if (!mounted) return;

  if (!result.isSuccess) {
    _showSnackBar(result.errorMessage!);
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ScanResultPage(
        imageFile: _image!,
        detectedNames: result.detectedNames,
        detectedBboxes: result.detectedBboxes,
        autosave: _autosaveEnabled,
      ),
    ),
  );
}

  @override
  void initState() {
    super.initState();
    _loadAutosavePreference();
  }

  Future<void> _loadAutosavePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final autosave = prefs.getBool(_autosavePreferenceKey) ?? true;
    if (!mounted) return;
    setState(() => _autosaveEnabled = autosave);
  }

  Future<void> _setAutosaveEnabled(bool value) async {
    setState(() => _autosaveEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autosavePreferenceKey, value);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.kanit()),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF112C63),
        elevation: 0,
        centerTitle: true,
        title: Text(
          'สแกนระบุชื่อยา',
          style: GoogleFonts.kanit(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: Stack(
        children: [
          Container(
            height: 120,
            decoration: const BoxDecoration(
              color: Color(0xFF112C63),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
          ),
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const _ScanIntroCard(),
                  const SizedBox(height: 20),
                  if (_image != null) ...[
                    _SelectedImagePreview(
                      image: _image!,
                      onRemove: () => setState(() => _image = null),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const _AiDisclaimerBanner(),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _ScanOptionCard(
                          onTap: _openRealtime,
                          icon: Icons.videocam_rounded,
                          label: 'Realtime Scan',
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ScanOptionCard(
                          onTap: _pickGallery,
                          icon: Icons.photo_library_rounded,
                          label: 'เลือกจากเครื่อง',
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _AutosaveToggleRow(
                    autosaveEnabled: _autosaveEnabled,
                    onChanged: _setAutosaveEnabled,
                  ),
                  const SizedBox(height: 16),
                  _AnalyzeButton(onPressed: _goToResult),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanIntroCard extends StatelessWidget {
  const _ScanIntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.medication_rounded,
              size: 40,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'วิธีใช้: สแกนหรือถ่ายรูปยาที่ต้องการตรวจสอบให้ชัดเจน'
            'จับยาวางไว้บนมือจะมีประสิทธิภาพมากขึ้น',
            style: GoogleFonts.kanit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ถ่ายรูปตัวยาให้มีขนาดใหญ่ชัดเจน\nเพื่อให้ AI วิเคราะห์ข้อมูลได้แม่นยำ',
            textAlign: TextAlign.center,
            style: GoogleFonts.kanit(
              fontSize: 14,
              color: const Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutosaveToggleRow extends StatelessWidget {
  const _AutosaveToggleRow({
    required this.autosaveEnabled,
    required this.onChanged,
  });

  final bool autosaveEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.save_outlined,
            size: 18,
            color: Color(0xFF6B7280),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'บันทึกประวัติอัตโนมัติ',
              style: GoogleFonts.kanit(
                fontSize: 13,
                color: const Color(0xFF374151),
              ),
            ),
          ),
          Switch.adaptive(
            value: autosaveEnabled,
            activeThumbColor: const Color(0xFF10B981),
            activeTrackColor: const Color(0xFF10B981).withValues(alpha: 0.35),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _AiDisclaimerBanner extends StatelessWidget {
  const _AiDisclaimerBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF9C3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFFB45309),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ผลการตรวจสอบนี้ประมวลผลด้วย AI อาจมีความคลาดเคลื่อน '
              'ผลลัพธ์ที่ได้อาจไม่ถูกต้องเสมอไป '
              'และมีไว้เพื่อเป็นข้อมูลประกอบการพิจารณาเบื้องต้นเท่านั้น',
              style: GoogleFonts.kanit(
                fontSize: 12,
                height: 1.5,
                color: const Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOptionCard extends StatelessWidget {
  const _ScanOptionCard({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedImagePreview extends StatelessWidget {
  const _SelectedImagePreview({
    required this.image,
    required this.onRemove,
  });

  final File image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              image,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
              cacheWidth: 720,
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalyzeButton extends StatelessWidget {
  const _AnalyzeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F7938), Color(0xFF10B981)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            'วิเคราะห์ภาพยา',
            style: GoogleFonts.kanit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
