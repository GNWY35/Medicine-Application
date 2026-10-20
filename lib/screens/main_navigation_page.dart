import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../repositories/auth_repository.dart';
import 'account/account_page.dart';
import 'history/history_page.dart';
import 'home/home_page.dart';
import 'scan/scan_medicine_page.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _current = 0;
  bool _isLoggedIn = false;
  final _authRepository = AuthRepository();

  @override
  void initState() {
    super.initState();
    _refreshAuthState();
  }

  Future<void> _refreshAuthState() async {
    final loggedIn = await _authRepository.isLoggedIn();
    if (!mounted) return;
    setState(() => _isLoggedIn = loggedIn);
  }

  List<Widget> get _pages => [
        const HomePage(),
        const ScanMedicinePage(),
        const HistoryPage(),
        AccountPage(
          isLoggedIn: _isLoggedIn,
          onAuthChanged: _refreshAuthState,
        ),
      ];

  void _onSelectTab(int index) {
    if (_current == index) return;
    setState(() => _current = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _current,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0B5394),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MainNavItem(
                  icon: _current == 0
                      ? Icons.home_rounded
                      : Icons.home_outlined,
                  label: 'หน้าแรก',
                  isSelected: _current == 0,
                  onTap: () => _onSelectTab(0),
                ),
                _MainNavItem(
                  icon: _current == 1
                      ? Icons.camera_alt_rounded
                      : Icons.camera_alt_outlined,
                  label: 'สแกน',
                  isSelected: _current == 1,
                  onTap: () => _onSelectTab(1),
                ),
                _MainNavItem(
                  icon: _current == 2
                      ? Icons.history_rounded
                      : Icons.history_outlined,
                  label: 'ประวัติ',
                  isSelected: _current == 2,
                  onTap: () => _onSelectTab(2),
                ),
                _MainNavItem(
                  icon: _current == 3
                      ? Icons.person_rounded
                      : Icons.person_outlined,
                  label: _isLoggedIn ? 'บัญชี' : 'เข้าสู่ระบบ',
                  isSelected: _current == 3,
                  onTap: () => _onSelectTab(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MainNavItem extends StatelessWidget {
  const _MainNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF10B981).withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF10B981)
                  : Colors.white.withValues(alpha: 0.6),
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.kanit(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF10B981)
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
