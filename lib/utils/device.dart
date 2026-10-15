import 'dart:math';
import '../models/user.dart';
import '../session/account.dart';

class DeviceProfileUtil {
  // 预置国内主流 Android 真机机型池
  static const List<String> _deviceModels = [
    'Xiaomi 13',
    'Xiaomi 13 Pro',
    'Xiaomi 14',
    'Xiaomi 14 Pro',
    'Redmi K60 Pro',
    'Redmi K70',
    'HUAWEI Mate 50',
    'HUAWEI Mate 60 Pro',
    'HUAWEI P60 Pro',
    'HUAWEI Nova 11',
    'vivo X90',
    'vivo X100',
    'vivo iQOO 11',
    'vivo iQOO 12',
    'OPPO Find X6',
    'OPPO Find X7',
    'OPPO Reno 10 Pro',
    'OnePlus 11',
    'OnePlus 12',
    'HONOR Magic 5',
    'HONOR Magic 6',
  ];

  static const List<String> _systemVersions = ['12', '13', '14'];
  static const List<String> _buildNumbers = ['1610', '1620', '1630', '1800'];

  /// 生成一套高仿真的随机物理手机特征
  static Map<String, dynamic> generateRandomDevice() {
    final random = Random();
    final model = _deviceModels[random.nextInt(_deviceModels.length)];
    final version = _systemVersions[random.nextInt(_systemVersions.length)];
    final build = _buildNumbers[random.nextInt(_buildNumbers.length)];
    // 生成 8 位数字 incremental（如 43928172）
    final incremental = (10000000 + random.nextInt(90000000)).toString();

    return {
      'user-agent': 'Android',
      'brand': model,
      'uuid': '', // 雨课堂协议关键：必须置空
      'buildnumber': build,
      'xtua': 'client=app&tag=1.3.3&platform=Android',
      'systemversion': version,
      'incremental': incremental,
      'version': '1.3.3',
      'isphysicaldevice': 'true',
      'x-client': 'app',
      'xtbz': 'ykt',
    };
  }

  /// 获取或为指定用户生成并持久化绑定专属设备指纹
  static Map<String, dynamic> getOrCreateForUser(User user) {
    if (user.deviceInfo != null &&
        user.deviceInfo!['brand'] != null &&
        user.deviceInfo!['brand'].toString().isNotEmpty) {
      return user.deviceInfo!;
    }

    final newDevice = generateRandomDevice();
    user.deviceInfo = newDevice;
    // 异步更新到本地存储
    AccountManager.updateUserDevice(user.uid, newDevice);
    return newDevice;
  }
}
