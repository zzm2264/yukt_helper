import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'api_service.dart';
import '../models/course.dart';
import '../models/location_checkin.dart';
import '../utils/location_helper.dart';
import '../utils/storage.dart';
import '../session/account.dart';

class RCCourseApi extends Api {
  RCCourseApi([super.user]);

  // key: "${userId}_$lessonId" -> [bearerToken, lessonToken, identityId]
  static final Map<String, List<String>> _tokens = {};

  // 记录当前正在上课的全局活跃 lessonId
  static String? activeLessonId;

  // userId -> lastLocationResult
  static final Map<String, LocationCheckinResult> _lastLocationResults = {};

  /// 构造基于当前用户与课堂的唯一凭证 Key
  String? _makeTokenKey([String? targetLessonId]) {
    final targetUser = user ?? AccountManager.currentUser;
    if (targetUser == null) return null;
    final lid = targetLessonId ?? activeLessonId;
    if (lid == null || lid.isEmpty) return null;
    return '${targetUser.uid}_$lid';
  }

  /// 获取当前用户在指定课堂的 bearerToken
  String? getBearerToken([String? lessonId]) {
    final key = _makeTokenKey(lessonId);
    if (key == null) return null;
    final tokens = _tokens[key];
    if (tokens != null && tokens.isNotEmpty && tokens[0].isNotEmpty) return tokens[0];
    final saved = StorageManager.prefs.getStringList('tokens_$key');
    if (saved != null && saved.isNotEmpty && saved[0].isNotEmpty) return saved[0];
    return null;
  }

  /// 获取当前用户的 bearerToken (来自 Set-Auth 响应头，用于 HTTP 鉴权)
  String? get bearerToken => getBearerToken();

  /// 获取当前用户在指定课堂的 lessonToken
  String? getLessonToken([String? lessonId]) {
    final key = _makeTokenKey(lessonId);
    if (key == null) return null;
    final tokens = _tokens[key];
    if (tokens != null && tokens.length > 1 && tokens[1].isNotEmpty) return tokens[1];
    final saved = StorageManager.prefs.getStringList('tokens_$key');
    if (saved != null && saved.length > 1 && saved[1].isNotEmpty) return saved[1];
    return null;
  }

  /// 获取当前用户的 lessonToken (来自 data.lessonToken，用于 WebSocket 握手)
  String? get lessonToken => getLessonToken();

  /// 获取当前用户在指定课堂的 identityId (身份编号，用于 WebSocket hello 的 userid)
  String? getIdentityId([String? lessonId]) {
    final key = _makeTokenKey(lessonId);
    if (key == null) return null;
    final tokens = _tokens[key];
    if (tokens != null && tokens.length > 2 && tokens[2].isNotEmpty) return tokens[2];
    final saved = StorageManager.prefs.getStringList('tokens_$key');
    if (saved != null && saved.length > 2 && saved[2].isNotEmpty) return saved[2];
    return null;
  }

  /// 获取当前用户的 identityId
  String? get identityId => getIdentityId();

  /// 获取最近一次位置签到执行结果详情
  LocationCheckinResult? get lastLocationResult {
    final targetUser = user ?? AccountManager.currentUser;
    return targetUser != null ? _lastLocationResults[targetUser.uid] : null;
  }

  /// 设置当前课堂凭证（强制与 lessonId 绑定）
  void _setToken(String lessonId, String bearerToken, String lessonToken, [String? identityId]) {
    final targetUser = user ?? AccountManager.currentUser;
    if (targetUser != null && lessonId.isNotEmpty) {
      activeLessonId = lessonId;
      final key = '${targetUser.uid}_$lessonId';
      final list = [bearerToken, lessonToken, identityId ?? ''];
      _tokens[key] = list;
      StorageManager.prefs.setStringList('tokens_$key', list);
    }
  }

  /// 清空所有用户缓存的课堂令牌，防止旧课程 token 污染新课程
  static void clearTokens() {
    _tokens.clear();
    activeLessonId = null;
    for (final key in StorageManager.prefs.getKeys()) {
      if (key.startsWith('tokens_')) {
        StorageManager.prefs.remove(key);
      }
    }
  }

  static void clearUserTokens(String userId, [String? lessonId]) {
    if (lessonId != null) {
      final key = '${userId}_$lessonId';
      _tokens.remove(key);
      StorageManager.prefs.remove('tokens_$key');
    } else {
      _tokens.removeWhere((k, _) => k.startsWith('${userId}_'));
      for (final key in StorageManager.prefs.getKeys()) {
        if (key.startsWith('tokens_${userId}_')) {
          StorageManager.prefs.remove(key);
        }
      }
    }
  }

  void _setLastLocationResult(LocationCheckinResult result) {
    final targetUser = user ?? AccountManager.currentUser;
    if (targetUser != null) {
      _lastLocationResults[targetUser.uid] = result;
    }
  }

  static Future<Map<String, dynamic>?> getCourses() async {
    final url = '/v/course_meta/learning_list/';
    final response = await ApiService.sendRequest(url);
    return response?.data;
  }

  /// 获取正在上课的课程
  static Future<List<dynamic>?> getOnLesson() async {
    final url = '/api/v3/classroom/on-lesson';
    final response = await ApiService.sendRequest(url);
    if (response?.data['code'] == 0){
      return response?.data['data']['onLessonClassrooms'];
    }
    return null;
  }

  /// 获取处理后的课程列表
  static Future<List<Course>?> getCoursesList([List<dynamic>? onLessonCourses]) async {
    late Map<String, dynamic>? courses;
    if (onLessonCourses == null) {
      final results = await Future.wait([getCourses(), getOnLesson()]);
      courses = results[0] as Map<String, dynamic>?;
      onLessonCourses = results[1] as List<dynamic>?;
    } else {
      courses = await getCourses();
    }

    if (courses == null || onLessonCourses == null) {
      return null;
    }
    if (courses['data'].isEmpty) {
      return null;
    }

    Map<String, dynamic> coursesMap = {
      for (var courseItem in courses['data']) courseItem['course_id'].toString(): courseItem
    };

    List<Course> contentList = [];

    for (var onLessonCourseItem in onLessonCourses){
      final String courseId = onLessonCourseItem['courseId'];
      if (coursesMap.containsKey(courseId)) {
        var courseItem = coursesMap[courseId];
        courseItem['lesson_id'] = onLessonCourseItem['lessonId'];
        final courseObject = Course.fromRCJson(courseItem);
        contentList.add(courseObject);
      }
    }

    return contentList;
  }

  /// 探测课程是否开启位置打卡及获取中心圆与时间窗配置
  Future<Map<String, dynamic>?> getLocationEligibility(String lessonId) async {
    final url = '/api/v3/lesson/location-checkin/eligibility?lesson_id=$lessonId';
    final headers = <String, String>{};
    final token = getBearerToken(lessonId) ?? bearerToken;
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    final response = await ApiService.sendRequest(
      url,
      headers: headers.isNotEmpty ? headers : null,
      userId: user?.uid,
    );
    return response?.data;
  }

  /// 在雨课堂网关代理 tencent-lbs/proxy 登记经纬度快照并换取物理建筑 POI
  Future<Map<String, dynamic>?> registerLocationProxy(double lat, double lng, [String? lessonId]) async {
    final latLngStr = '${lat.toStringAsFixed(6)}%2C${lng.toStringAsFixed(6)}';
    final url = '/api/v3/tencent-lbs/proxy?lbsPath=geocoder%2Fv1&location=$latLngStr&get_poi=2';
    final headers = <String, String>{};
    final token = (lessonId != null ? getBearerToken(lessonId) : null) ?? bearerToken;
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    final response = await ApiService.sendRequest(
      url,
      headers: headers.isNotEmpty ? headers : null,
      userId: user?.uid,
    );
    return response?.data;
  }

  /// 官方专属位置打卡提交接口 (POST /api/v3/lesson/location-checkin/submit)
  /// 官方 App 中在 LocationCheckInPage 使用 source: 27 提交，携带 lat, lng, lessonId, address
  Future<Response?> _submitLocationCheckinDedicated({
    required String lessonId,
    required double lat,
    required double lng,
    String? address,
  }) async {
    final url = '/api/v3/lesson/location-checkin/submit';
    final jsonData = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'lessonId': int.tryParse(lessonId) ?? lessonId,
      'source': 27,
      'address': address ?? '',
    };
    final headers = <String, String>{};
    final token = getBearerToken(lessonId) ?? bearerToken;
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    return await ApiService.sendRequest(
      url,
      method: 'POST',
      headers: headers.isNotEmpty ? headers : null,
      body: jsonData,
      userId: user?.uid,
    );
  }

  /// 内部提交签到报文
  Future<Response?> _submitCheckinRaw({
    required String lessonId,
    required int source,
    double? latitude,
    double? longitude,
  }) async {
    final url = '/api/v3/lesson/checkin';
    final jsonData = <String, dynamic>{
      'source': source,
      'lessonId': lessonId.toString(),
      'joinIfNotIn': true,
    };
    if (latitude != null && longitude != null) {
      jsonData['latitude'] = latitude;
      jsonData['longitude'] = longitude;
    }
    // 签到请求是换取课堂凭证的入口，以 Session Cookie 鉴权；切忌携带可能过期或来自上一节课的旧 Bearer Token，避免 401 拒签
    return await ApiService.sendRequest(
      url,
      method: 'POST',
      body: jsonData,
      userId: user?.uid,
    );
  }

  /// 带有 21/23 双通道自适应容错回退的签到/入课提交
  /// 优先尝试 primarySource（默认 21），若返回未成功（code != 0 或网络异常），
  /// 自动无缝降级切换至备用通道 alternateSource（通常为 23）进行二次尝试；
  /// 反之若 primarySource 为 23 则容错回退至 21。
  Future<Response?> _submitCheckinWithFallback({
    required String lessonId,
    int primarySource = 21,
    int? fallbackSource,
    double? latitude,
    double? longitude,
  }) async {
    final alternateSource = fallbackSource ?? (primarySource == 21 ? 23 : 21);

    // 1. 优先尝试首选通道（如 source 21 移动/扫码通道）
    Response? response = await _submitCheckinRaw(
      lessonId: lessonId,
      source: primarySource,
      latitude: latitude,
      longitude: longitude,
    );

    final isSuccess = response != null &&
        response.data is Map &&
        response.data['code'] == 0;

    if (isSuccess) {
      return response;
    }

    final primaryCode = response?.data is Map ? response?.data['code'] : null;
    debugPrint(
      '打卡通道 source=$primarySource 未成功 (code: $primaryCode)，自动触发双通道容错切换至 source=$alternateSource...',
    );

    // 2. 自动切换至备选通道（如 source 23 网页/卡片通道）进行容错补救
    Response? fallbackResponse;
    try {
      fallbackResponse = await _submitCheckinRaw(
        lessonId: lessonId,
        source: alternateSource,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      debugPrint('备用打卡通道 source=$alternateSource 请求异常: $e');
    }

    final isFallbackSuccess = fallbackResponse != null &&
        fallbackResponse.data is Map &&
        fallbackResponse.data['code'] == 0;

    if (isFallbackSuccess) {
      debugPrint('备用打卡通道 source=$alternateSource 容错成功！');
      return fallbackResponse;
    }

    // 若备用通道也未成功：若首选通道具有明确特征错误码（如 50070 动态二维码拦截），优先返回首选响应供前端识别；否则返回备用响应或首选响应
    if (primaryCode == 50070) {
      return response;
    }
    return fallbackResponse ?? response;
  }

  /// 执行腾讯 LBS 11 级精密位置打卡状态机
  Future<LocationCheckinResult> executeLocationCheckin(String lessonId) async {
    final result = await _executeLocationCheckinInternal(lessonId);
    _setLastLocationResult(result);
    return result;
  }

  Future<LocationCheckinResult> _executeLocationCheckinInternal(String lessonId) async {
    // 阶段 1: LOCATION_REQUIRED (资格探测)
    final dynamic eligData = await getLocationEligibility(lessonId);
    if (eligData == null || eligData is! Map || eligData['code'] != 0) {
      // 若接口无响应或非正常课堂，降级回退为无位置限制
      return LocationCheckinResult.noLocation();
    }

    final data = eligData['data'];
    if (data is! Map) {
      return LocationCheckinResult.noLocation();
    }

    // 防重安全校验：若雨课堂服务端记录该账号已签到（旧版本签到/网页签到/异地签到），坚决直接复用成功状态，绝不重复提交覆盖
    final bool alreadySigned = data['signed'] == true || data['checkInTime'] != null;
    if (alreadySigned) {
      return LocationCheckinResult.success(
        coord: const Gcj02Coord(0, 0),
        address: data['address'] as String? ?? '教室内已登记定位',
        distanceM: (data['distance'] as num?)?.toDouble() ?? 0.0,
        isLate: data['isLate'] == true,
      );
    }

    final bool needLocation = data['needLocationSignIn'] == true;
    final session = data['session'];

    // 若本节课未启用位置打卡，平稳过渡到常规模式
    if (!needLocation || session is! Map) {
      return LocationCheckinResult.noLocation();
    }

    // 阶段 2: ELIGIBILITY_CHECKED (门禁与时间窗校验)
    final now = DateTime.now().millisecondsSinceEpoch;
    final int startMs = (session['startMs'] as num?)?.toInt() ?? 0;
    final int endMs = (session['endMs'] as num?)?.toInt() ?? 0;
    final int lateAfterMs = (session['lateAfterMs'] as num?)?.toInt() ?? 0;

    // 未到开始时间
    if (startMs > 0 && now < startMs) {
      return LocationCheckinResult.abort(
        stage: LocationCheckinStage.abortedExpired,
        code: 51003,
        message: '位置签到尚未开始',
      );
    }

    // 超过截止时间，严禁强行打卡
    if (endMs > 0 && now > endMs) {
      return LocationCheckinResult.abort(
        stage: LocationCheckinStage.abortedExpired,
        code: 51001,
        message: '位置签到已截止，放弃上报',
      );
    }

    final bool isLate = lateAfterMs > 0 && now > lateAfterMs && (endMs == 0 || now <= endMs);

    double? parseCoord(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val.trim());
      return null;
    }

    final double? centerLat = parseCoord(session['centerLat'] ?? session['latitude'] ?? session['lat']);
    final double? centerLng = parseCoord(session['centerLng'] ?? session['longitude'] ?? session['lng']);
    final double radiusM = parseCoord(session['radiusM'] ?? session['radius']) ?? 20.0;

    if (centerLat == null || centerLng == null) {
      debugPrint('位置签到配置缺失有效中心经纬度，安全回退。');
      return LocationCheckinResult.noLocation();
    }

    // 阶段 3: LOCATION_READY (极坐标高保真微抖动火星坐标生成)
    final coord = LocationHelper.generateJitteredCoord(centerLat, centerLng, radiusM);

    // 阶段 4: DISTANCE_CHECKED (球面大圆 Haversine 距离校验)
    final distanceM = LocationHelper.calculateDistanceMeters(
      coord.lat,
      coord.lng,
      centerLat,
      centerLng,
    );

    if (distanceM > radiusM) {
      return LocationCheckinResult.abort(
        stage: LocationCheckinStage.abortedOutOfRange,
        code: 51002,
        message: '坐标偏离超出教师指定半径 ($distanceM > $radiusM)',
        coord: coord,
        distanceM: distanceM,
      );
    }

    // 阶段 5: GEOCODE_RESOLVED (通过网关代理换取地名并登记学生位置快照)
    String? address;
    try {
      final proxyRes = await registerLocationProxy(coord.lat, coord.lng, lessonId);
      if (proxyRes != null && proxyRes['result'] is Map) {
        final result = proxyRes['result'];
        address = result['formatted_addresses']?['recommend'] ??
            result['address'] ??
            result['formatted_addresses']?['rough'];
      }
    } catch (_) {
      // 逆地理编码失败不影响后续打卡投递
    }

    // 阶段 6: CHECKIN_SUBMITTED (优先使用官方专用位置打卡接口 source: 27，未响应则双通道容错回退)
    Response? response = await _submitLocationCheckinDedicated(
      lessonId: lessonId,
      lat: coord.lat,
      lng: coord.lng,
      address: address,
    );

    // 若专用接口未成功（例如特定镜像网关未开 /submit），自动平稳回退至通用双通道打卡
    if (response == null || response.data is! Map || response.data['code'] != 0) {
      final fallbackResponse = await _submitCheckinWithFallback(
        lessonId: lessonId,
        primarySource: 21,
        latitude: coord.lat,
        longitude: coord.lng,
      );
      if (fallbackResponse != null &&
          fallbackResponse.data is Map &&
          fallbackResponse.data['code'] == 0) {
        response = fallbackResponse;
      } else {
        response = response ?? fallbackResponse;
      }
    }

    if (response == null) {
      return LocationCheckinResult.failure(
        code: -1,
        message: '网络通信超时或网关连接断开',
      );
    }

    final resData = response.data;
    final int code = resData is Map ? (resData['code'] ?? -1) : -1;

    if (code == 0) {
      final bearerToken = response.headers.value('set-auth');
      final lessonToken = resData['data']?['lessonToken'];
      final identityId = resData['data']?['identityId']?.toString();
      if (bearerToken != null || lessonToken != null) {
        _setToken(
          lessonId,
          bearerToken ?? getBearerToken(lessonId) ?? '',
          lessonToken?.toString() ?? getLessonToken(lessonId) ?? '',
          identityId ?? getIdentityId(lessonId) ?? this.identityId,
        );
      }
      return LocationCheckinResult.success(
        address: address,
        coord: coord,
        distanceM: distanceM,
        isLate: isLate,
      );
    } else {
      final String msg = resData is Map ? (resData['msg'] ?? '签到失败') : '签到失败';
      return LocationCheckinResult.failure(
        code: code,
        message: msg,
      );
    }
  }

  /// 签到核心统一入口（全面兼容 21 移动/扫码端 与 23 网页/卡片端 双通道自适应容错）
  /// - [preferSource]: 首选进班通道（默认 21 原版移动扫码通道，完全兼容 23 网页卡片通道）
  /// - [forcedSource]: 兼容旧参数名（优先取非空值）
  /// 容错机制：优先以首选通道请求；若返回非 0 或网络异常，自动无缝降级切换至备用通道（21 <=> 23）进行二次重试；
  /// 无论哪个通道成功，均自动双向解析 set-auth / Bearer Token 与 lessonToken 注入凭据池。
  Future<int?> checkIn(String lessonId, {int? preferSource, int? forcedSource}) async {
    final primary = preferSource ?? forcedSource ?? 21;
    final response = await _submitCheckinWithFallback(
      lessonId: lessonId,
      primarySource: primary,
    );
    if (response == null) return null;

    final int code = response.data is Map ? (response.data['code'] ?? -1) : -1;
    if (code == 0) {
      final bearerToken = response.headers.value('set-auth') ??
          response.data['data']?['bearerToken']?.toString() ??
          response.data['data']?['auth']?.toString();
      final lessonToken = response.data['data']?['lessonToken'];
      final identityId = response.data['data']?['identityId']?.toString();
      if (bearerToken != null || lessonToken != null) {
        _setToken(
          lessonId,
          bearerToken ?? getBearerToken(lessonId) ?? '',
          lessonToken?.toString() ?? getLessonToken(lessonId) ?? '',
          identityId ?? getIdentityId(lessonId) ?? this.identityId,
        );
      }
      return 0;
    }
    return code;
  }

  static String? _lastScannedLessonId;
  static String? get lastScannedLessonId => _lastScannedLessonId;

  /// 官方原版标准扫码进班接口（严格保持原版原状）
  Future<int?> scan(String qrCodeUrl) async {
    final url = '/api/v3/app/scan';
    final jsonData = {'url': qrCodeUrl};
    final response = await ApiService.sendRequest(
      url,
      method: 'POST',
      body: jsonData,
      userId: user?.uid,
    );
    if (response == null) return null;

    final data = response.data;
    final int code = data is Map ? (data['code'] ?? -1) : -1;
    if (code == 0) {
      final lessonId = data['data']?['value']?.toString();
      if (lessonId != null && lessonId.isNotEmpty) {
        _lastScannedLessonId = lessonId;
        RCCourseApi.activeLessonId = lessonId;
        // 原版标准：扫码成功后直接使用官方标准 source: 21 进班换取 Token
        final checkinResponse = await _submitCheckinRaw(lessonId: lessonId, source: 21);
        if (checkinResponse == null) return null;
        final resData = checkinResponse.data;
        final int checkinCode = resData is Map ? (resData['code'] ?? -1) : -1;
        if (checkinCode == 0) {
          final bearerToken = checkinResponse.headers.value('set-auth') ??
              resData['data']?['bearerToken']?.toString() ??
              resData['data']?['auth']?.toString();
          final lessonToken = resData['data']?['lessonToken'];
          final identityId = resData['data']?['identityId']?.toString();
          if (bearerToken != null || lessonToken != null) {
            _setToken(
              lessonId,
              bearerToken ?? getBearerToken(lessonId) ?? '',
              lessonToken?.toString() ?? getLessonToken(lessonId) ?? '',
              identityId ?? getIdentityId(lessonId) ?? this.identityId,
            );
          }
          return 0;
        }
        return checkinCode;
      }
      return 0;
    } else {
      return code;
    }
  }

  Future<Map<String, dynamic>?> getPresentation(String presentationId, [String? lessonId]) async {
    final url = '/api/v3/lesson/presentation/fetch?presentation_id=$presentationId';
    final token = (lessonId != null ? getBearerToken(lessonId) : null) ?? bearerToken;
    if (token == null || token.isEmpty) {
      return null;
    }
    final headers = {'authorization': 'Bearer $token'};
    final response = await ApiService.sendRequest(url, headers: headers, userId: user?.uid);
    return response?.data['data'];
  }

  /// 提交答案
  Future<Map<String, dynamic>?> answer(String problemId, int problemType,
      {bool retry = false, int? time, List<String>? options, String? content, List<String>? imageUrls, String? lessonId}) async {
    final url = retry ?
    '/api/v3/lesson/problem/retry' : '/api/v3/lesson/problem/answer';
    final token = (lessonId != null ? getBearerToken(lessonId) : null) ?? bearerToken;
    if (token == null || token.isEmpty) {
      return null;
    }
    final headers = {'authorization': 'Bearer $token'};
    final timeStampMS = time ?? DateTime.now().millisecondsSinceEpoch;
    late dynamic result;
    if (problemType == 5) {
      var pics = [];
      if (imageUrls != null) {
        for (var imageUrl in imageUrls) {
          pics.add({
            'pic': imageUrl,
            'thumb': '$imageUrl?imageView2/2/w/568'
          });
        }
      } else {
        pics = [{'pic': '', 'thumb': ''}];
      }
      result = {'content': content ?? '', 'pics': pics, 'videos': []};
    } else if (problemType == 4) {
      result = options ?? (content != null && content.isNotEmpty ? [content] : []);
    } else {
      result = options;
    }
    var jsonData = {
      'problemId': problemId,
      'dt': timeStampMS,
      'problemType': problemType,
      'result': result
    };
    if (retry) {
      jsonData['retry_times'] = null;
      jsonData = {'problems': [jsonData]};
    }
    final response = await ApiService.sendRequest(url, method: 'POST', headers: headers, body: jsonData, userId: user?.uid);
    return response?.data;
  }
}