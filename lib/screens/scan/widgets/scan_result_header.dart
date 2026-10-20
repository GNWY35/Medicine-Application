import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ScanResultHeader extends StatelessWidget {
  const ScanResultHeader({
    super.key,
    this.imageFile,
    this.showSelectionAction = false,
    this.selectedCountListenable,
    this.totalCount = 0,
    this.onToggleSelectAll,
  });

  final File? imageFile;
  final bool showSelectionAction;
  final ValueNotifier<int>? selectedCountListenable;
  final int totalCount;
  final VoidCallback? onToggleSelectAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── รูปภาพ ─────────────────────────────────────────
        if (imageFile != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Image.file(
                  imageFile!,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                ),
                // gradient overlay ด้านล่าง
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                        ],
                      ),
                    ),
                  ),
                ),
                // badge "รูปที่ใช้สแกน"
                Positioned(
                  bottom: 10, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.image_rounded,
                            color: Colors.white70, size: 13),
                        const SizedBox(width: 5),
                        Text(
                          'รูปที่ใช้สแกน',
                          style: GoogleFonts.kanit(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── หัวข้อ + จำนวน ──────────────────────────────────
        Row(
          children: [
            Container(
              width: 4,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'รายการยาที่ตรวจพบ',
              style: GoogleFonts.kanit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
              ),
            ),
            const Spacer(),
            if (totalCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$totalCount รายการ',
                  style: GoogleFonts.kanit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF059669),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),

        // ── ปุ่ม select all ─────────────────────────────────
        if (showSelectionAction &&
            selectedCountListenable != null &&
            onToggleSelectAll != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ValueListenableBuilder<int>(
              valueListenable: selectedCountListenable!,
              builder: (_, count, __) {
                final allSelected = count == totalCount;
                return GestureDetector(
                  onTap: onToggleSelectAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: allSelected
                          ? const Color(0xFFD1FAE5)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: allSelected
                            ? const Color(0xFF10B981)
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          allSelected
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          color: allSelected
                              ? const Color(0xFF10B981)
                              : const Color(0xFF9CA3AF),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          allSelected
                              ? 'ยกเลิกเลือกทั้งหมด'
                              : 'เลือกทั้งหมด',
                          style: GoogleFonts.kanit(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: allSelected
                                ? const Color(0xFF059669)
                                : const Color(0xFF374151),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}