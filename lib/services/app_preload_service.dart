import '../repositories/med_repository.dart';

class AppPreloadService {
  static Future<void>? _preloadFuture;

  static Future<void> warmUp() {
    return _preloadFuture ??= _runWarmUp();
  }

  static Future<void> _runWarmUp() async {
    await MedRepository().loadAll();
  }
}
