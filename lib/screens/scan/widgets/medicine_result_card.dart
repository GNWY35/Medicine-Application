import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/med_item.dart';

class MedicineResultCard extends StatelessWidget {
  const MedicineResultCard({
    super.key,
    required this.medItem,
    required this.leading,
    required this.selectedListenable,
    required this.expandedListenable,
    required this.onToggleSelected,
    required this.onToggleExpanded,
    required this.isInteractive,
    required this.highlightSelection,
  });

  final MedItem medItem;
  final Widget leading;
  final ValueListenable<bool> selectedListenable;
  final ValueListenable<bool> expandedListenable;
  final VoidCallback onToggleSelected;
  final VoidCallback onToggleExpanded;
  final bool isInteractive;
  final bool highlightSelection;

  /// สรรพคุณฉบับเต็มจาก DB; ถ้าไม่มี (API ใช้ไม่ได้) ใช้สรรพคุณย่อจาก Excel แทน
  String get _fullText => medItem.fullIndication ?? medItem.description;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: selectedListenable,
        builder: (context, isSelected, _) {
          final isHighlighted = highlightSelection && isSelected;
          return GestureDetector(
            onTap: isInteractive ? onToggleSelected : null,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isHighlighted ? const Color(0xFFD1FAE5) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isHighlighted
                      ? const Color(0xFF10B981)
                      : const Color(0xFFE5E7EB),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      ClipRRect(child: leading),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              medItem.brandName,
                              style: GoogleFonts.kanit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (medItem.genericName.isNotEmpty)
                              Text(
                                medItem.genericName,
                                style: GoogleFonts.kanit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF6B7280),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ClipRRect(
                        child: Image.asset(
                          medItem.imagePath,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          cacheWidth: 210, // ปรับตรงนี้ ขนาดรูปย่อของยาในหน้าประวัติ
                          cacheHeight: 150, // ปรับตรงนี้ ขนาดรูปย่อของยาในหน้าประวัติ - ในกรณีเปลี่ยนรูปใหม่ แล้วขนาดเปลี่ยนไป อาจจะทำให้ดูไม่สวยให้ปรับตรงนี้
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<bool>(
                    valueListenable: expandedListenable,
                    builder: (context, isExpanded, _) {
                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'สรรพคุณยา',
                                style: GoogleFonts.kanit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                onPressed: onToggleExpanded,
                                icon: Icon(
                                  isExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: const Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                          AnimatedCrossFade(
                            firstChild: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Text(
                                _fullText.isEmpty
                                    ? 'ไม่มีข้อมูลสรรพคุณ'
                                    : _fullText,
                                style: GoogleFonts.kanit(height: 1.6),
                              ),
                            ),
                            secondChild: const SizedBox.shrink(),
                            crossFadeState: isExpanded
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                            duration: const Duration(milliseconds: 250),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
