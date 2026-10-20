class HistoryRecord {
  final DateTime time;
  final List<String> items;
  final String? imagePath;
  final List<String?>? cropImagePaths;

  HistoryRecord({
    required this.time,
    required this.items,
    this.imagePath,
    this.cropImagePaths,
  });

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'items': items,
    'imagePath': imagePath,
    'cropImagePaths': cropImagePaths,
  };

  static HistoryRecord fromJson(Map<String, dynamic> json) => HistoryRecord(
    time: DateTime.parse(json['time']),
    items: (json['items'] as List).cast<String>(),
    imagePath: json['imagePath'] as String?,
    cropImagePaths: (json['cropImagePaths'] as List?)?.map((e) => e as String?).toList(),
  );
}
