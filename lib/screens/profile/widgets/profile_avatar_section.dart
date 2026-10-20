import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProfileAvatarSection extends StatelessWidget {
  const ProfileAvatarSection({
    super.key,
    required this.imageFile,
    required this.onTap,
  });

  final File? imageFile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF10B981),
              width: 3,
            ),
          ),
          child: GestureDetector(
            onTap: onTap,
            child: CircleAvatar(
              radius: 60,
              backgroundImage: imageFile != null ? FileImage(imageFile!) : null,
              backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
              child: imageFile == null
                  ? const Icon(
                      Icons.person_rounded,
                      size: 60,
                      color: Color(0xFF10B981),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'แตะเพื่อเปลี่ยนรูปภาพ',
          style: GoogleFonts.kanit(
            fontSize: 12,
            color: const Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }
}
