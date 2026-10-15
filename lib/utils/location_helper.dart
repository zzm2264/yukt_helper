import 'dart:math';

/// 火星坐标 (GCJ-02) 实体
class Gcj02Coord {
  final double lat;
  final double lng;

  const Gcj02Coord(this.lat, this.lng);

  /// 格式化为 API 所需的 6 位小数字符串，例如 "39.182754,117.123588"
  String toParamString() => '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

  @override
  String toString() => 'Gcj02Coord(lat: ${lat.toStringAsFixed(6)}, lng: ${lng.toStringAsFixed(6)})';
}

/// 腾讯 LBS 地理位置算法与极坐标微抖动工具类
class LocationHelper {
  static const double _earthRadiusMeters = 6378137.0; // WGS-84 / CGCS2000 地球平均半径 (米)

  /// 使用球面大圆公式 (Haversine Formula) 精确计算两点间物理距离 (米)
  static double calculateDistanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final radLat1 = lat1 * pi / 180.0;
    final radLat2 = lat2 * pi / 180.0;
    final deltaLat = radLat1 - radLat2;
    final deltaLng = (lng1 * pi / 180.0) - (lng2 * pi / 180.0);

    final a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(radLat1) * cos(radLat2) * sin(deltaLng / 2) * sin(deltaLng / 2);
    final s = 2 * asin(sqrt(a));

    return double.parse((s * _earthRadiusMeters).toStringAsFixed(1));
  }

  /// 在教师指定的圆形地理围栏内部，生成高保真极坐标微抖动火星坐标 (GCJ-02)
  ///
  /// - [centerLat]: 教师设定的围栏中心纬度
  /// - [centerLng]: 教师设定的围栏中心经度
  /// - [maxRadiusMeters]: 教师允许的最大签到半径 (米)
  ///
  /// 算法保障：
  /// 1. 约束安全最大步长：取老师半径的一半与 15 米的较小值，下限 3 米，确保绝对不越界；
  /// 2. 极坐标随机离散：在 [3m, safeMax] 之间生成随机半径，在 [0, 2π] 之间生成随机方位角；
  /// 3. 输出严格保留 6 位小数。
  static Gcj02Coord generateJitteredCoord(
    double centerLat,
    double centerLng,
    double maxRadiusMeters,
  ) {
    final random = Random();

    // 1. 安全最大半径约束：取教师指定半径的 50%，且不超过 15 米，下限 3 米
    final double safeMax = min(max(3.0, maxRadiusMeters * 0.5), 15.0);

    // 2. 生成随机距离与航向角
    final double radiusInMeters = 3.0 + random.nextDouble() * (safeMax - 3.0);
    final double angle = random.nextDouble() * 2.0 * pi;

    // 3. 局部切平面微小位移映射 (1 纬度 ≈ 111111 米)
    final double deltaLat = (radiusInMeters * cos(angle)) / 111111.0;
    final double deltaLng = (radiusInMeters * sin(angle)) /
        (111111.0 * cos(centerLat * pi / 180.0));

    final double finalLat = double.parse((centerLat + deltaLat).toStringAsFixed(6));
    final double finalLng = double.parse((centerLng + deltaLng).toStringAsFixed(6));

    return Gcj02Coord(finalLat, finalLng);
  }
}
