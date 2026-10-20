import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeQuickFilters extends StatelessWidget {
  const HomeQuickFilters({
    super.key,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.onRefresh,
  });

  final String currentFilter;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FilterChipItem(
          label: 'ทั้งหมด',
          selected: currentFilter == 'ทั้งหมด',
          onSelected: () => onFilterChanged('ทั้งหมด'),
        ),
        const SizedBox(width: 8),
        _FilterChipItem(
          label: 'ความดันโลหิต',
          selected: currentFilter == 'ความดันโลหิต',
          onSelected: () => onFilterChanged('ความดันโลหิต'),
        ),
        const Spacer(),
        IconButton(
          onPressed: onRefresh,
          tooltip: 'รีเฟรช',
          icon: const Icon(
            Icons.refresh_rounded,
            color: Color(0xFF10B981),
          ),
        ),
      ],
    );
  }
}

class _FilterChipItem extends StatelessWidget {
  const _FilterChipItem({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.kanit(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFF10B981).withValues(alpha: 0.2),
      side: BorderSide(
        color: selected
            ? const Color(0xFF10B981)
            : const Color(0xFFE5E7EB),
      ),
    );
  }
}
