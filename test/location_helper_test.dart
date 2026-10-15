import 'package:flutter_test/flutter_test.dart';
import 'package:course_helper/utils/location_helper.dart';
import 'package:course_helper/models/location_checkin.dart';

void main() {
  group('LocationHelper Tests', () {
    test('calculateDistanceMeters returns 0 for identical points', () {
      final dist = LocationHelper.calculateDistanceMeters(39.181190, 117.131450, 39.181190, 117.131450);
      expect(dist, 0.0);
    });

    test('calculateDistanceMeters calculates accurate physical distance', () {
      // 北京天安门 (39.9087, 116.3975) 到 故宫博物院神武门 (39.9242, 116.3975) 约 1720 米
      final dist = LocationHelper.calculateDistanceMeters(39.9087, 116.3975, 39.9242, 116.3975);
      expect(dist, greaterThan(1700));
      expect(dist, lessThan(1750));
    });

    test('generateJitteredCoord generates coordinates strictly within safe radius', () {
      const centerLat = 39.181190;
      const centerLng = 117.131450;
      const maxRadius = 30.0; // 老师设定的围栏半径 30 米

      final generatedCoords = <String>{};

      for (int i = 0; i < 500; i++) {
        final coord = LocationHelper.generateJitteredCoord(centerLat, centerLng, maxRadius);
        final paramStr = coord.toParamString();
        
        // 6位小数格式验证
        final parts = paramStr.split(',');
        expect(parts.length, 2);
        expect(parts[0].split('.')[1].length, 6);
        expect(parts[1].split('.')[1].length, 6);

        // 测距验证：严禁越出围栏半径
        final dist = LocationHelper.calculateDistanceMeters(coord.lat, coord.lng, centerLat, centerLng);
        expect(dist, lessThanOrEqualTo(maxRadius), reason: 'Jittered coord must not exceed maxRadius');
        expect(dist, greaterThanOrEqualTo(2.8), reason: 'Jittered coord should maintain safe distance');

        generatedCoords.add(paramStr);
      }

      // 验证 500 次生成的坐标离散度，无大量完全重复
      expect(generatedCoords.length, greaterThan(450));
    });
  });

  group('LocationCheckinResult Tests', () {
    test('noLocation factory', () {
      final res = LocationCheckinResult.noLocation();
      expect(res.needLocation, false);
      expect(res.isSuccess, true);
      expect(res.stage, LocationCheckinStage.abortedNoSession);
    });

    test('abort factory for expired', () {
      final res = LocationCheckinResult.abort(
        stage: LocationCheckinStage.abortedExpired,
        code: 51001,
        message: '已截止',
      );
      expect(res.needLocation, true);
      expect(res.isSuccess, false);
      expect(res.code, 51001);
      expect(res.stage, LocationCheckinStage.abortedExpired);
    });

    test('success factory', () {
      final coord = Gcj02Coord(39.182754, 117.123588);
      final res = LocationCheckinResult.success(
        address: '天津农学院第2教学楼',
        coord: coord,
        distanceM: 5.2,
      );
      expect(res.isSuccess, true);
      expect(res.needLocation, true);
      expect(res.code, 0);
      expect(res.address, '天津农学院第2教学楼');
      expect(res.distanceM, 5.2);
    });
  });
}
