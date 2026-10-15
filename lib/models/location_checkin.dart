import '../utils/location_helper.dart';

/// 腾讯 LBS 位置打卡 11 级精密状态机阶段枚举
enum LocationCheckinStage {
  init,                  // 初始状态
  credentialsReady,      // 账号 Cookie / 凭证就绪
  locationRequired,      // 探测位置打卡资格中
  eligibilityChecked,    // 资格与时间窗校验通过
  locationReady,         // 极坐标微抖动 GCJ-02 坐标生成就绪
  distanceChecked,       // Haversine 距离校验放行
  geocodeResolved,       // 网关代理 tencent-lbs/proxy 登记成功
  checkinSubmitted,      // source=23 打卡报文提交完成
  checkinSuccess,        // 签到成功并获取课堂凭证
  abortedNoSession,      // 本节课无位置打卡要求 (走常规入课)
  abortedExpired,        // 超过截止时间 (安全拒报)
  abortedOutOfRange,     // 坐标偏离超出教师指定半径 (拒报)
  abortedNetwork,        // 网关通信故障 / 超时
}

/// 位置签到与状态机执行结果
class LocationCheckinResult {
  final bool isSuccess;
  final bool needLocation;
  final LocationCheckinStage stage;
  final int code;
  final String message;
  final String? address;
  final Gcj02Coord? coord;
  final double? distanceM;
  final bool isLate;

  const LocationCheckinResult({
    required this.isSuccess,
    required this.needLocation,
    required this.stage,
    required this.code,
    required this.message,
    this.address,
    this.coord,
    this.distanceM,
    this.isLate = false,
  });

  /// 无需位置打卡（常规扫码或常规进班）
  factory LocationCheckinResult.noLocation({int code = 0, String message = '常规课程，无需位置打卡'}) {
    return LocationCheckinResult(
      isSuccess: code == 0,
      needLocation: false,
      stage: LocationCheckinStage.abortedNoSession,
      code: code,
      message: message,
    );
  }

  /// 位置打卡成功
  factory LocationCheckinResult.success({
    required String? address,
    required Gcj02Coord coord,
    required double distanceM,
    bool isLate = false,
    String message = '位置签到成功',
  }) {
    return LocationCheckinResult(
      isSuccess: true,
      needLocation: true,
      stage: LocationCheckinStage.checkinSuccess,
      code: 0,
      message: message,
      address: address,
      coord: coord,
      distanceM: distanceM,
      isLate: isLate,
    );
  }

  /// 触发门禁中止（已截止、超范围等安全防御拦截）
  factory LocationCheckinResult.abort({
    required LocationCheckinStage stage,
    required int code,
    required String message,
    Gcj02Coord? coord,
    double? distanceM,
  }) {
    return LocationCheckinResult(
      isSuccess: false,
      needLocation: true,
      stage: stage,
      code: code,
      message: message,
      coord: coord,
      distanceM: distanceM,
    );
  }

  /// 通信或未知错误
  factory LocationCheckinResult.failure({
    required int code,
    required String message,
    LocationCheckinStage stage = LocationCheckinStage.abortedNetwork,
  }) {
    return LocationCheckinResult(
      isSuccess: false,
      needLocation: true,
      stage: stage,
      code: code,
      message: message,
    );
  }

  @override
  String toString() {
    return 'LocationCheckinResult(isSuccess: $isSuccess, needLocation: $needLocation, stage: $stage, code: $code, message: $message, address: $address, distance: ${distanceM}m, isLate: $isLate)';
  }
}
