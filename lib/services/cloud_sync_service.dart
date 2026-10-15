import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../session/account.dart';
import '../utils/device.dart';

class CloudSyncService {
  // 默认云端同步服务器地址（部署服务端后可在此修改或在本地持久化设置）
  static const String defaultServerUrl = 'http://127.0.0.1:5000';
  static const String keyPrefServerUrl = 'cached_server_url';
  static const String keyPrefApiKey = 'yuketang_user_api_key';
  static const String keyPrefGroupRemark = 'yuketang_group_remark';

  // 动态服务器地址分发配置源（可选：用户可部署包含 {"server_url":"..."} 的 server_config.json 至自有 GitHub/CDN）
  static final List<String> remoteConfigUrls = [
    // 示例: 'https://raw.githubusercontent.com/your-username/your-repo/main/server_config.json',
  ];

  static Timer? _debounceTimer;

  /// 触发自动静默同步至云端（防抖 800ms）
  static void triggerAutoUpload() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        final service = CloudSyncService();
        final key = await service.getSavedKey();
        if (key != null && key.trim().isNotEmpty) {
          debugPrint('[CloudSync] 检测到已配置密钥，正在自动静默同步账号至云端...');
          final res = await service.uploadLocalAccounts();
          if (res['success'] == true) {
            debugPrint('[CloudSync] 自动同步成功，已更新 ${res['count']} 个账号到云端。');
          } else {
            debugPrint('[CloudSync] 自动同步未完成: ${res['msg']}');
          }
        }
      } catch (e) {
        debugPrint('[CloudSync] 自动同步异常: $e');
      }
    });
  }

  late final Dio _dio;

  CloudSyncService() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 6),
    ));
  }

  // 获取当前服务器 IP
  Future<String> resolveServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    String serverUrl = prefs.getString(keyPrefServerUrl) ?? defaultServerUrl;

    // 后台静默刷新最新 IP
    for (final url in remoteConfigUrls) {
      _dio.get(url).then((res) {
        if (res.statusCode == 200 && res.data != null) {
          dynamic payload = res.data;
          if (payload is String) payload = jsonDecode(payload);
          if (payload is Map && payload['server_url'] != null) {
            final newUrl = payload['server_url'].toString().replaceAll(RegExp(r'/+$'), '');
            prefs.setString(keyPrefServerUrl, newUrl);
          }
        }
      }).catchError((_) {});
    }

    return serverUrl;
  }

  // 1. 验证并保存群组 Key
  Future<Map<String, dynamic>> verifyAndSaveKey(String apiKey) async {
    final trimmedKey = apiKey.trim();
    final serverUrl = await resolveServerUrl();

    try {
      final res = await _dio.get(
        '$serverUrl/api/sync/profile',
        options: Options(headers: {'Authorization': trimmedKey}),
      );

      if (res.statusCode == 200 && res.data is Map && res.data['code'] == 0) {
        final data = res.data['data'] is Map ? res.data['data'] : {};
        final remark = data['remark'] ?? '专属账号组';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(keyPrefApiKey, trimmedKey);
        await prefs.setString(keyPrefGroupRemark, remark);

        return {'success': true, 'remark': remark};
      }
      final msg = res.data is Map ? (res.data['msg'] ?? '密钥无效') : '服务器返回非预期格式 (${res.statusCode})';
      return {'success': false, 'msg': msg};
    } catch (e) {
      return {'success': false, 'msg': '服务器连接失败: $e'};
    }
  }

  // 获取已存的 Key
  Future<String?> getSavedKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyPrefApiKey);
  }

  // 2. 从云端拉取账号列表并写入本地 AccountManager
  Future<Map<String, dynamic>> downloadAndApplyAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(keyPrefApiKey);
    if (apiKey == null || apiKey.isEmpty) {
      return {'success': false, 'msg': '请先设置群组同步密钥'};
    }

    final serverUrl = await resolveServerUrl();
    try {
      final res = await _dio.get(
        '$serverUrl/api/sync/download',
        options: Options(headers: {'Authorization': apiKey}),
      );

      if (res.statusCode == 200 && res.data is Map && res.data['code'] == 0) {
        final list = res.data['data'] as List? ?? [];
        int count = 0;
        for (var item in list) {
          if (item is Map) {
            final phone = User.normalizePhone(item['phone']);
            final uid = item['uid']?.toString() ?? item['id']?.toString() ?? '';
            final name = item['name']?.toString() ?? '云端用户';
            final remark = item['remark']?.toString() ?? '';
            final cookie = item['cookie']?.toString() ?? '';
            final avatar = item['avatar']?.toString() ?? '';
            final school = item['school']?.toString() ?? '';
            
            final existingUser = AccountManager.getAccountById(uid);
            final device = item['device'] is Map
                ? Map<String, dynamic>.from(item['device'])
                : existingUser?.deviceInfo;

            if (uid.isNotEmpty && cookie.isNotEmpty) {
              // 构造 User 对象并写入本地 AccountManager
              final user = User(
                uid: uid,
                name: name,
                phone: phone,
                avatar: avatar,
                school: school,
                remark: remark,
                deviceInfo: device,
                status: true,
              );
              await AccountManager.saveAccount(user, cookie);
              count++;
            }
          }
        }
        return {'success': true, 'count': count};
      }
      final msg = res.data is Map ? (res.data['msg'] ?? '拉取失败') : '服务器返回非预期格式 (${res.statusCode})';
      return {'success': false, 'msg': msg};
    } catch (e) {
      return {'success': false, 'msg': '连接失败: $e'};
    }
  }

  // 3. 将本地账号列表备份到云端
  Future<Map<String, dynamic>> uploadLocalAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(keyPrefApiKey);
    if (apiKey == null || apiKey.isEmpty) {
      return {'success': false, 'msg': '请先设置群组同步密钥'};
    }

    final allUsers = AccountManager.allAccounts;
    if (allUsers.isEmpty) {
      return {'success': false, 'msg': '本地暂无账号'};
    }

    final serverUrl = await resolveServerUrl();
    try {
      // 提取本地账号与 Cookie 及各账号专属设备指纹（纯静态账号信息，无需课堂 Token）
      List<Map<String, dynamic>> accountsPayload = [];
      for (var u in allUsers) {
        final cookie = AccountManager.getCookie(u.uid) ?? '';
        final device = u.deviceInfo ?? DeviceProfileUtil.getOrCreateForUser(u);
        accountsPayload.add({
          'id': u.uid,
          'uid': u.uid,
          'phone': User.normalizePhone(u.phone),
          'name': u.name,
          'avatar': u.avatar,
          'school': u.school,
          'remark': u.remark,
          'cookie': cookie,
          'device': device,
        });
      }

      final res = await _dio.post(
        '$serverUrl/api/sync/upload',
        data: {
          'accounts': accountsPayload,
          'remark': prefs.getString(keyPrefGroupRemark) ?? '',
          'deleted_accounts': [],
        },
        options: Options(headers: {
          'Authorization': apiKey,
          'Content-Type': 'application/json',
        }),
      );

      if (res.statusCode == 200 && res.data is Map && res.data['code'] == 0) {
        return {'success': true, 'count': accountsPayload.length};
      }
      final msg = res.data is Map ? (res.data['msg'] ?? '上传失败') : '服务器返回非预期格式 (${res.statusCode})';
      return {'success': false, 'msg': msg};
    } catch (e) {
      return {'success': false, 'msg': '连接失败: $e'};
    }
  }
}
