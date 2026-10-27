import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/med_item.dart';
import '../../repositories/med_repository.dart';
import '../about/about_developers_page.dart';
import 'widgets/home_quick_filters.dart';
import 'widgets/home_search_bar.dart';
import 'widgets/medicine_detail_sheet.dart';
import 'widgets/medicine_grid_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MedRepository _repository = MedRepository();
  final TextEditingController _searchController = TextEditingController();

  List<MedItem> _allMedicines = [];
  bool _loading = true;
  String _quickFilter = 'ทั้งหมด';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadMedicines();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  Future<void> _loadMedicines() async {
    setState(() => _loading = true);
    try {
      final medicines = await _repository.loadAll();
      if (!mounted) return;
      setState(() {
        _allMedicines = medicines;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('โหลด meds.xlsm ไม่สำเร็จ: $error')),
      );
    }
  }

  List<MedItem> _computeFilteredMedicines() {
    final query = _searchController.text.trim().toLowerCase();
    var filtered = _allMedicines.where((medicine) {
      final text = '${medicine.name} ${medicine.description}'.toLowerCase();
      return query.isEmpty || text.contains(query);
    }).toList();

    if (_quickFilter == 'ความดันโลหิต') {
      filtered = filtered.where((medicine) {
        final text = '${medicine.name} ${medicine.description}'.toLowerCase();
        return text.contains('ความดัน') ||
            text.contains('ความดันโลหิต') ||
            text.contains('hypertension');
      }).toList();
    }

    return filtered;
  }

  void _openDetail(MedItem medicine) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MedDetailSheet(item: medicine),
    );
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredMedicines = _computeFilteredMedicines();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF112C63),
        elevation: 0,
        centerTitle: true,
        title: Text(
          'ยาความดันโลหิต',
          style: GoogleFonts.kanit(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.local_pharmacy_rounded, color: Colors.white),
          onPressed: () {},
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
            tooltip: 'เกี่ยวกับผู้พัฒนา',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AboutDevelopersPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: HomeSearchBar(controller: _searchController),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: HomeQuickFilters(
                currentFilter: _quickFilter,
                onFilterChanged: (value) => setState(() => _quickFilter = value),
                onRefresh: _loadMedicines,
              ),
            ),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredMedicines.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.local_pharmacy_rounded,
                        size: 64,
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'ไม่พบรายการ',
                        style: GoogleFonts.kanit(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Container(
                  color: const Color.fromARGB(255, 229, 234, 233),
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.7,
                    ),
                    itemCount: filteredMedicines.length,
                    itemBuilder: (context, index) {
                      final medicine = filteredMedicines[index];
                      return MedicineGridCard(
                        item: medicine,
                        onTap: () => _openDetail(medicine),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
