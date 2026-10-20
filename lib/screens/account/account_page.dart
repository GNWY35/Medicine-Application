import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth/login_page.dart';
import '../auth/register_page.dart';
import '../profile/profile_page.dart';

/// แท็บบัญชี: ผู้ใช้ทั่วไปไม่ต้องเข้าสู่ระบบ
/// เข้าสู่ระบบสำหรับเภสัชกร (super user) เท่านั้น
class AccountPage extends StatelessWidget {
  const AccountPage({
    super.key,
    required this.isLoggedIn,
    required this.onAuthChanged,
  });

  final bool isLoggedIn;
  final VoidCallback onAuthChanged;

  Future<void> _goToLogin(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (loginContext) => LoginPage(
          onRegisterClicked: () {
            Navigator.push(
              loginContext,
              MaterialPageRoute(
                builder: (registerContext) => RegisterPage(
                  onRegistered: () => Navigator.pop(registerContext),
                ),
              ),
            );
          },
        ),
      ),
    );
    onAuthChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoggedIn) {
      return ProfilePage(onLoggedOut: onAuthChanged);
    }
    return _LoginPromptView(onLoginTap: () => _goToLogin(context));
  }
}

class _LoginPromptView extends StatelessWidget {
  const _LoginPromptView({required this.onLoginTap});

  final VoidCallback onLoginTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF112C63),
        elevation: 0,
        centerTitle: true,
        title: Text(
          'บัญชี',
          style: GoogleFonts.kanit(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.local_pharmacy_rounded,
                  size: 48,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'สำหรับเภสัชกร',
                style: GoogleFonts.kanit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'เข้าสู่ระบบเพื่อเข้าถึงเครื่องมือสำหรับเภสัชกร\n'
                'ผู้ใช้ทั่วไปสามารถใช้งานแอปได้โดยไม่ต้องเข้าสู่ระบบ',
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(
                  fontSize: 13,
                  color: const Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onLoginTap,
                  icon: const Icon(Icons.login_rounded),
                  label: Text(
                    'เข้าสู่ระบบ',
                    style: GoogleFonts.kanit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
