import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../repositories/auth_repository.dart';

import 'widgets/profile_avatar_section.dart';
import 'widgets/profile_info_card.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.onLoggedOut});

  final VoidCallback onLoggedOut;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController _nameController;

  String _email = '';
  String _displayName = 'ผู้ใช้ของฉัน';
  File? _imageFile;
  bool _isPickingImage = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _loadUserData();
  }

  final _authRepository = AuthRepository();

Future<void> _loadUserData() async {
  final email = await _authRepository.currentUserEmail();
  if (!mounted) return;

  setState(() {
    _email = email ?? '';
    _nameController.text = _displayName;
  });
}

  Future<void> _logout() async {
    await _authRepository.logout();

    if (!mounted) return;
    widget.onLoggedOut();
  }

  Future<void> _changeNameDialog() async {
    _nameController.text = _displayName;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'เปลี่ยนชื่อผู้ใช้',
          style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: 'กรอกชื่อใหม่',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF10B981),
                width: 2,
              ),
            ),
            fillColor: const Color(0xFFF3F4F6),
            filled: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'ยกเลิก',
              style: GoogleFonts.kanit(color: const Color(0xFF6B7280)),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _displayName = _nameController.text.trim().isEmpty
                    ? 'ผู้ใช้ของฉัน'
                    : _nameController.text.trim();
              });
              Navigator.pop(context);
            },
            child: Text(
              'บันทึก',
              style: GoogleFonts.kanit(
                color: const Color(0xFF10B981),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickProfileImage() async {
    if (_isPickingImage) return;

    _isPickingImage = true;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (!mounted || picked == null) return;
      setState(() => _imageFile = File(picked.path));
    } on PlatformException catch (_) {
    } finally {
      _isPickingImage = false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF112C63),
        elevation: 0,
        centerTitle: true,
        title: Text(
          'โปรไฟล์',
          style: GoogleFonts.kanit(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              ProfileAvatarSection(
                imageFile: _imageFile,
                onTap: _pickProfileImage,
              ),
              const SizedBox(height: 28),
              ProfileInfoCard(
                displayName: _displayName,
                email: _email,
                onEditName: _changeNameDialog,
              ),
              const SizedBox(height: 32),
              _LogoutButton(onPressed: _logout),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.logout_rounded),
        label: Text(
          'ออกจากระบบ',
          style: GoogleFonts.kanit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
