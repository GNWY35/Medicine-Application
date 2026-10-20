import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:google_fonts/google_fonts.dart';

import '../../models/med_item.dart';
import '../../services/history_service.dart';
import '../../services/medicine_image_service.dart';
import '../../services/medicine_lookup_service.dart';
import 'widgets/medicine_result_card.dart';
import 'widgets/scan_result_header.dart';

class ScanResultPage extends StatefulWidget {
  const ScanResultPage({
    super.key,
    this.imageFile,
    required this.detectedNames,
    this.detectedBboxes = const [],
    this.isFromHistory = false,
    this.cropImagePaths,
    this.autosave = true,
  });

  final File? imageFile;
  final List<String> detectedNames;
  final List<List<double>> detectedBboxes;
  final bool isFromHistory;
  final List<String?>? cropImagePaths;
  final bool autosave;

  @override
  State<ScanResultPage> createState() => _ScanResultPageState();
}

class _ScanResultPageState extends State<ScanResultPage> {
  final MedicineLookupService _lookupService = MedicineLookupService();
  final ValueNotifier<int> _selectedCount = ValueNotifier<int>(0);

  late final List<ValueNotifier<bool>> _selectedStates;
  late final List<ValueNotifier<bool>> _expandedStates;
  late final Future<List<MedItem>> _medsFuture;
  Future<ImageInfo>? _imageInfoFuture;
  bool _historySaved = false;

  @override
  void initState() {
    super.initState();
    _selectedStates = List.generate(
      widget.detectedNames.length,
      (_) => ValueNotifier<bool>(widget.autosave && !widget.isFromHistory),
    );
    _expandedStates = List.generate(
      widget.detectedNames.length,
      (_) => ValueNotifier<bool>(false),
    );
    _selectedCount.value =
        widget.autosave && !widget.isFromHistory ? _selectedStates.length : 0;
    _medsFuture = _lookupService.findMedicines(widget.detectedNames);
    _imageInfoFuture =
        widget.imageFile == null ? null : _resolveImageInfo(widget.imageFile!);

    if (widget.autosave &&
        !widget.isFromHistory &&
        widget.detectedNames.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoSaveHistory());
    }
  }

  Future<void> _autoSaveHistory() async {
    if (_historySaved) return;

    final meds = await _medsFuture;
    final selectedNames = _selectedNames(meds);
    if (selectedNames.isEmpty) return;

    await _saveHistory(selectedNames);
    if (!mounted) return;

    _historySaved = true;
    _showSuccessSnackBar();
  }

  Future<ImageInfo> _resolveImageInfo(File file) async {
    final completer = Completer<ImageInfo>();
    final image = Image.file(file);

    image.image.resolve(const ImageConfiguration()).addListener(
          ImageStreamListener((info, _) => completer.complete(info)),
        );

    return completer.future;
  }

  List<String> _selectedNames(List<MedItem> meds) {
    if (widget.autosave && !widget.isFromHistory) {
      return meds.map((med) => med.name).toList();
    }

    final selectedNames = <String>[];
    for (int i = 0; i < meds.length; i++) {
      if (_selectedStates[i].value) {
        selectedNames.add(meds[i].name);
      }
    }
    return selectedNames;
  }

  void _toggleSelected(int index) {
    if (widget.autosave || widget.isFromHistory) return;
    final notifier = _selectedStates[index];
    final nextValue = !notifier.value;
    notifier.value = nextValue;
    _selectedCount.value += nextValue ? 1 : -1;
  }

  void _toggleExpanded(int index) {
    _expandedStates[index].value = !_expandedStates[index].value;
  }

  void _toggleSelectAll() {
    if (widget.autosave || widget.isFromHistory) return;
    final shouldSelectAll = _selectedCount.value != _selectedStates.length;
    for (final notifier in _selectedStates) {
      notifier.value = shouldSelectAll;
    }
    _selectedCount.value = shouldSelectAll ? _selectedStates.length : 0;
  }

  Future<void> _saveHistory(List<String> items) async {
    final cropPaths = await _buildCropPaths();
    await HistoryStore.addRecord(
      items,
      imagePath: widget.imageFile?.path,
      cropImagePaths: cropPaths,
    );
  }

  Future<List<String?>> _buildCropPaths() async {
    if (widget.imageFile == null || widget.detectedBboxes.isEmpty) {
      return <String?>[];
    }

    final selectedIndexes = <int>[];
    for (int i = 0; i < widget.detectedNames.length; i++) {
      if (widget.autosave || _selectedStates[i].value) {
        selectedIndexes.add(i);
      }
    }

    return Future.wait(
      selectedIndexes.map((index) async {
        final bbox = widget.detectedBboxes.length > index
            ? widget.detectedBboxes[index]
            : null;
        if (bbox == null || bbox.length != 4) return null;

        return cropAndSaveMedicineImage(
          widget.imageFile!,
          bbox,
          widget.detectedNames[index],
        );
      }),
    );
  }

  void _showSuccessSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'บันทึกลง History แล้ว',
          style: GoogleFonts.kanit(),
        ),
        backgroundColor: const Color(0xFF059669),
      ),
    );
  }

  Widget _buildCroppedImage(
    File imageFile,
    double outputSize,
    List<double> bbox,
    ImageInfo info,
  ) {
    final imgW = info.image.width.toDouble();
    final imgH = info.image.height.toDouble();
    final x1 = bbox[0].clamp(0, imgW);
    final y1 = bbox[1].clamp(0, imgH);
    final x2 = bbox[2].clamp(0, imgW);
    final y2 = bbox[3].clamp(0, imgH);

    final cropW = (x2 - x1).abs();
    final cropH = (y2 - y1).abs();
    final squareSize = math.max(cropW, cropH).toDouble();
    final centerX = x1 + cropW / 2;
    final centerY = y1 + cropH / 2;

    double newX1 = centerX - squareSize / 2;
    double newY1 = centerY - squareSize / 2;

    newX1 = newX1.clamp(0, imgW - squareSize);
    newY1 = newY1.clamp(0, imgH - squareSize);

    return SizedBox(
      width: outputSize,
      height: outputSize,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: squareSize,
            height: squareSize,
            child: Stack(
              children: [
                Positioned(
                  left: -newX1,
                  top: -newY1,
                  child: Image.file(
                    imageFile,
                    width: imgW,
                    height: imgH,
                    fit: BoxFit.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingImage(
    List<MedItem> meds,
    int index,
    ImageInfo? imageInfo,
  ) {
    if (widget.isFromHistory &&
        widget.cropImagePaths != null &&
        widget.cropImagePaths!.length > index &&
        widget.cropImagePaths![index] != null) {
      return Image.file(
        File(widget.cropImagePaths![index]!),
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        cacheWidth: 144,
        cacheHeight: 144,
      );
    }

    if (widget.imageFile != null &&
        imageInfo != null &&
        widget.detectedBboxes.length > index &&
        widget.detectedBboxes[index].length == 4) {
      return _buildCroppedImage(
        widget.imageFile!,
        72,
        widget.detectedBboxes[index],
        imageInfo,
      );
    }

    return Image.asset(
      meds[index].imagePath,
      width: 72,
      height: 72,
      fit: BoxFit.cover,
      cacheWidth: 144,
      cacheHeight: 144,
    );
  }

  Future<void> _handleSave(List<MedItem> meds) async {
    final selectedNames = _selectedNames(meds);
    if (selectedNames.isEmpty) return;

    await _saveHistory(selectedNames);
    if (!mounted) return;
    _showSuccessSnackBar();
  }

  @override
  void dispose() {
    for (final notifier in _selectedStates) {
      notifier.dispose();
    }
    for (final notifier in _expandedStates) {
      notifier.dispose();
    }
    _selectedCount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MedItem>>(
      future: _medsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final meds = snapshot.data!;
        return Scaffold(
          backgroundColor: const Color(0xFFF9FAFB),
          appBar: AppBar(
            backgroundColor: const Color(0xFF112C63),
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              'ผลลัพธ์การสแกน',
              style: GoogleFonts.kanit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            centerTitle: true,
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: FutureBuilder<ImageInfo?>(
              future: _imageInfoFuture,
              builder: (context, imageSnapshot) {
                final imageInfo = imageSnapshot.data;
                return ListView.builder(
                  scrollCacheExtent: const ScrollCacheExtent.pixels(600),
                  itemCount: meds.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ScanResultHeader(
                        imageFile: widget.imageFile,
                        showSelectionAction:
                            !widget.isFromHistory && !widget.autosave,
                        selectedCountListenable: _selectedCount,
                        totalCount: _selectedStates.length,
                        onToggleSelectAll: _toggleSelectAll,
                      );
                    }

                    final medIndex = index - 1;
                    return MedicineResultCard(
                      medItem: meds[medIndex],
                      leading: _buildLeadingImage(
                        meds,
                        medIndex,
                        imageInfo,
                      ),
                      selectedListenable: _selectedStates[medIndex],
                      expandedListenable: _expandedStates[medIndex],
                      onToggleSelected: () => _toggleSelected(medIndex),
                      onToggleExpanded: () => _toggleExpanded(medIndex),
                      isInteractive:
                          !widget.isFromHistory && !widget.autosave,
                      highlightSelection:
                          !widget.isFromHistory && !widget.autosave,
                    );
                  },
                );
              },
            ),
          ),
          bottomNavigationBar: widget.isFromHistory || widget.autosave
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: ValueListenableBuilder<int>(
                    valueListenable: _selectedCount,
                    builder: (context, selectedCount, _) {
                      return FilledButton.icon(
                        onPressed:
                            selectedCount == 0 ? null : () => _handleSave(meds),
                        icon: const Icon(Icons.save_alt_rounded),
                        label: Text(
                          'บันทึก History',
                          style: GoogleFonts.kanit(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      );
                    },
                  ),
                ),
        );
      },
    );
  }
}
