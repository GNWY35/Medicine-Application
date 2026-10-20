import 'package:shared_preferences/shared_preferences.dart';

class AuthCredentials {
  const AuthCredentials({required this.email, required this.password});
  final String email;
  final String password;
}

/// เก็บ/ตรวจสอบข้อมูลผู้ใช้ (ปัจจุบันใช้ SharedPreferences — จะสลับไปเรียก
/// เซิร์ฟเวอร์ local แทนในขั้นถัดไป โดยไม่ต้องแก้ไฟล์อื่น)
class AuthRepository {
  Future<void> register(AuthCredentials credentials) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', credentials.email.trim());
    await prefs.setString('user_password', credentials.password);
  }

  Future<bool> login(
    AuthCredentials credentials, {
    required bool rememberMe,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('user_email');
    final savedPassword = prefs.getString('user_password');

    final matches = credentials.email == savedEmail &&
        credentials.password == savedPassword &&
        credentials.email.isNotEmpty;

    if (!matches) return false;

    if (rememberMe) {
      await prefs.setBool('remember_me', true);
      await prefs.setString('saved_email', credentials.email);
      await prefs.setString('saved_password', credentials.password);
    } else {
      await prefs.setBool('remember_me', false);
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
    }
    await prefs.setBool('is_logged_in', true);
    return true;
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_logged_in') ?? false;
  }

  Future<AuthCredentials?> loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('remember_me') ?? false)) return null;
    return AuthCredentials(
      email: prefs.getString('saved_email') ?? '',
      password: prefs.getString('saved_password') ?? '',
    );
  }

  Future<String?> currentUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_email');
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', false);
    await prefs.remove('saved_email');
    await prefs.remove('saved_password');
    await prefs.setBool('is_logged_in', false);
  }
}