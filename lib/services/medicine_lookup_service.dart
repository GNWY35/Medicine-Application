import '../models/med_item.dart';
import '../repositories/med_repository.dart';

class MedicineLookupService {
  MedicineLookupService({MedRepository? repository})
      : _repository = repository ?? MedRepository();

  final MedRepository _repository;
  Future<Map<String, MedItem>>? _excelMapFuture;

  Future<MedItem> findMedicine(String name) async {
    final excelMap = await _loadExcelMap();
    final excelMed = excelMap[name.toLowerCase()];
    if (excelMed != null) return excelMed;

    return _buildFallbackMedicine(name);
  }

  Future<List<MedItem>> findMedicines(List<String> names) async {
    final lookupByName = <String, Future<MedItem>>{};
    return Future.wait(
      names.map((name) {
        return lookupByName.putIfAbsent(name, () => findMedicine(name));
      }),
    );
  }

  Future<Map<String, MedItem>> _loadExcelMap() {
    return _excelMapFuture ??= _createExcelMap();
  }

  Future<Map<String, MedItem>> _createExcelMap() async {
    final allExcelMeds = await _repository.loadAll();
    return {
      for (final med in allExcelMeds) med.name.toLowerCase(): med,
    };
  }

  MedItem _buildFallbackMedicine(String name) {
    return MedItem(
      name: name,
      description: '',
      imagePath: _fallbackImagePath(name),
    );
  }

  String _fallbackImagePath(String name) {
    final override = kImageOverrides[name];
    if (override != null) return override;

    final sanitized = name
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[\\/:"*?<>|]'), '_');
    return '${MedRepository.imgDir}$sanitized.jpg';
  }
}
