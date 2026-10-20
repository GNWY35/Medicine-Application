import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../repositories/auth_repository.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.onRegistered,
  });

  final VoidCallback onRegistered;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  Future<void> _register() async {
  if (!_formKey.currentState!.validate()) return;

  await AuthRepository().register(
    AuthCredentials(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    ),
  );

  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('ลงทะเบียนสำเร็จ!')),
  );
  widget.onRegistered();
}

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF112C63),
      body: Stack(
        children: [
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'สมัครสมาชิก',
                        style: GoogleFonts.kanit(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Text(
                      'สร้างบัญชีของคุณเพื่อเริ่มต้น',
                      style: GoogleFonts.kanit(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _RegisterTextField(
                            controller: _emailController,
                            labelText: 'อีเมล',
                            hintText: 'กรุณากรอกอีเมลของคุณ',
                            icon: Icons.email_rounded,
                            validator: (value) => (value == null || value.isEmpty)
                                ? 'กรุณากรอกอีเมล'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _RegisterTextField(
                            controller: _passwordController,
                            labelText: 'รหัสผ่าน',
                            hintText: 'กรุณากรอกรหัสผ่านของคุณ',
                            icon: Icons.lock_rounded,
                            obscureText: true,
                            validator: (value) => (value == null || value.isEmpty)
                                ? 'กรุณากรอกรหัสผ่าน'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _RegisterTextField(
                            controller: _confirmPasswordController,
                            labelText: 'ยืนยันรหัสผ่าน',
                            hintText: 'กรุณากรอกรหัสผ่านอีกครั้ง',
                            icon: Icons.lock_outline_rounded,
                            obscureText: true,
                            validator: (value) => value != _passwordController.text
                                ? 'รหัสผ่านไม่ตรงกัน'
                                : null,
                          ),
                          const SizedBox(height: 24),
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF059669), Color(0xFF10B981)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF10B981).withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: FilledButton.icon(
                              onPressed: _register,
                              icon: const Icon(Icons.app_registration_rounded),
                              label: Text(
                                'สมัครสมาชิก',
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
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'มีบัญชีอยู่แล้ว?',
                                style: GoogleFonts.kanit(
                                  color: const Color(0xFF6B7280),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'เข้าสู่ระบบ',
                                  style: GoogleFonts.kanit(
                                    color: const Color(0xFF10B981),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterTextField extends StatelessWidget {
  const _RegisterTextField({
    required this.controller,
    required this.labelText,
    required this.hintText,
    required this.icon,
    required this.validator,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final IconData icon;
  final String? Function(String?) validator;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Icon(icon, color: const Color(0xFF10B981)),
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
        labelStyle: GoogleFonts.kanit(color: const Color(0xFF6B7280)),
      ),
    );
  }
}
