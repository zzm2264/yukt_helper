import '../api/api_service.dart';
import '../utils/storage.dart';

enum PlatformType { rainClassroom }

enum RainClassroomServerType {
  yuketang,
  pro,
  changjiang,
  huanghe
}

class PlatformManager {
  static final PlatformManager _instance = PlatformManager._internal();
  factory PlatformManager() => _instance;
  PlatformManager._internal();

  static const _serverKey = 'current_server';
  RainClassroomServerType _currentServer = RainClassroomServerType.yuketang;

  PlatformType get currentPlatform => PlatformType.rainClassroom;
  bool get isChaoxing => false;
  bool get isRainClassroom => true;
  RainClassroomServerType get currentServer => _currentServer;

  Future<void> initialize() async {
    final serverStr = StorageManager.prefs.getString(_serverKey);
    if (serverStr != null && serverStr.isNotEmpty) {
      _currentServer = RainClassroomServerType.values.firstWhere(
        (e) => e.name == serverStr,
        orElse: () => RainClassroomServerType.yuketang,
      );
    }
    ApiService.onPlatformChange?.call();
  }

  Future<void> setServer(RainClassroomServerType server) async {
    if (_currentServer != server) {
      _currentServer = server;
      await StorageManager.prefs.setString(_serverKey, server.name);
      ApiService.onPlatformChange?.call();
    }
  }
}
