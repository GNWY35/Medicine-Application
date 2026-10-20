class MedItem {
  final String name;               // ชื่อยาความดันโลหิตสูง(ยี่ห้อยา_ชื่อยา)
  final String description;        // สรรพคุณ (บทย่อ, จาก Excel) - ใช้ในหน้า Home
  final String imagePath;          // พาธภาพ: assets/images/amldac/<sanitized>.jpg
  final String? fullIndication;    // สรรพคุณฉบับเต็ม (จาก DB, indications) - ใช้ในหน้าผลสแกน

  MedItem({
    required this.name,
    required this.description,
    required this.imagePath,
    this.fullIndication,
  });

  /// ชื่อยี่ห้อ (ส่วนก่อน "_" แรกใน [name] เช่น "Ambes" จาก "Ambes_Amlodipine")
  String get brandName {
    final idx = name.indexOf('_');
    return idx == -1 ? name : name.substring(0, idx);
  }

  /// ชื่อสามัญ (ส่วนหลัง "_" แรกใน [name] เช่น "Amlodipine" จาก "Ambes_Amlodipine")
  String get genericName {
    final idx = name.indexOf('_');
    return idx == -1 ? '' : name.substring(idx + 1);
  }
}
