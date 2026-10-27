import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AboutDevelopersPage extends StatelessWidget {
  const AboutDevelopersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF112C63),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'เกี่ยวกับผู้พัฒนา',
          style: GoogleFonts.kanit(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.local_pharmacy_rounded,
                  size: 44,
                  color: Color(0xFF10B981),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Medi-Ident AI',
                style: GoogleFonts.kanit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1F2937),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'แอปช่วยระบุยาความดันโลหิตสูงด้วย AI',
                style: GoogleFonts.kanit(
                  fontSize: 13,
                  color: const Color(0xFF6B7280),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'ทีมผู้พัฒนา',
              style: GoogleFonts.kanit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 12),
            // TODO: ใส่รายชื่อ/เครดิตผู้พัฒนาจริงตรงนี้
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(
                'ใส่ข้อมูลทีมผู้พัฒนาที่นี่',
                style: GoogleFonts.kanit(
                  fontSize: 14,
                  color: const Color(0xFF4B5563),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
