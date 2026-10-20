import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/history_record.dart';
import '../../services/history_service.dart';
import '../../services/thumbnail_cache_service.dart';
import '../scan/scan_result_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<HistoryRecord>> _future;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _future = HistoryStore.load();
    HistoryStore.changes.addListener(_handleHistoryChanged);
  }

  @override
  void dispose() {
    HistoryStore.changes.removeListener(_handleHistoryChanged);
    super.dispose();
  }

  void _handleHistoryChanged() {
    if (!mounted) return;
    setState(() {
      _future = HistoryStore.load();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _future = HistoryStore.load();
      _selectedDate = null;
    });
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'ยืนยันการลบ',
          style: GoogleFonts.kanit(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'คุณต้องการลบประวัติการสแกนทั้งหมดใช่หรือไม่?',
          style: GoogleFonts.kanit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('ยกเลิก', style: GoogleFonts.kanit()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'ลบทั้งหมด',
              style: GoogleFonts.kanit(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await HistoryStore.clear();
    if (!mounted) return;

    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ลบประวัติทั้งหมดแล้ว')),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('th', 'TH'),
    );

    if (!mounted || picked == null) return;
    setState(() => _selectedDate = picked);
  }

  List<HistoryRecord> _filterRecords(List<HistoryRecord> records) {
    if (_selectedDate == null) return records;

    return records.where((record) {
      return record.time.year == _selectedDate!.year &&
          record.time.month == _selectedDate!.month &&
          record.time.day == _selectedDate!.day;
    }).toList();
  }

  void _openRecord(HistoryRecord record) {
    if (record.items.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanResultPage(
          imageFile: record.imagePath != null ? File(record.imagePath!) : null,
          detectedNames: record.items,
          isFromHistory: true,
          cropImagePaths: record.cropImagePaths,
          autosave: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF112C63),
        elevation: 0,
        centerTitle: true,
        title: Text(
          'ประวัติการสแกน',
          style: GoogleFonts.kanit(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'เลือกวันที่',
            icon: const Icon(Icons.date_range_rounded, color: Colors.white),
            onPressed: _pickDate,
          ),
          IconButton(
            tooltip: 'ลบทั้งหมด',
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
          ),
        ],
      ),
      body: FutureBuilder<List<HistoryRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            );
          }

          final filtered = _filterRecords(snapshot.data!);
          if (filtered.isEmpty) {
            return _EmptyHistoryState(selectedDate: _selectedDate);
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            color: const Color(0xFF10B981),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final record = filtered[index];
                return _HistoryCard(
                  record: record,
                  timeText: DateFormat('d MMM yyyy, HH:mm').format(record.time),
                  onTap: () => _openRecord(record),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState({required this.selectedDate});

  final DateTime? selectedDate;

  @override
  Widget build(BuildContext context) {
    final text = selectedDate == null
        ? 'ยังไม่มีประวัติการสแกน'
        : 'ไม่พบประวัติในวันที่เลือก';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.history_rounded,
              size: 64,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            text,
            style: GoogleFonts.kanit(
              color: const Color(0xFF6B7280),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.record,
    required this.timeText,
    required this.onTap,
  });

  final HistoryRecord record;
  final String timeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 6, color: const Color(0xFF10B981)),
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        _HistoryLeading(record: record),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.items.join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.kanit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: const Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.access_time_rounded,
                                    size: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    timeText,
                                    style: GoogleFonts.kanit(
                                      fontSize: 12,
                                      color: const Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: Color(0xFFD1D5DB),
                        ),
                      ],
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

class _HistoryLeading extends StatelessWidget {
  const _HistoryLeading({required this.record});

  final HistoryRecord record;

  @override
  Widget build(BuildContext context) {
    if (record.imagePath == null) {
      return _CountCircle(count: record.items.length);
    }

    return FutureBuilder<String?>(
      future: ThumbnailCacheService.getOrCreateThumbnail(record.imagePath!),
      builder: (context, snapshot) {
        final imagePath = snapshot.data;
        final file =
            imagePath != null ? File(imagePath) : File(record.imagePath!);

        return ClipOval(
          child: Image.file(
            file,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            cacheWidth: 104,
            cacheHeight: 104,
            errorBuilder: (_, __, ___) =>
                _CountCircle(count: record.items.length),
          ),
        );
      },
    );
  }
}

class _CountCircle extends StatelessWidget {
  const _CountCircle({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF10B981).withValues(alpha: 0.2),
            const Color(0xFF10B981).withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$count',
          style: GoogleFonts.kanit(
            color: const Color(0xFF0F7938),
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
