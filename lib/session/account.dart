import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import 'cookie.dart';
import '../utils/storage.dart';
import '../services/cloud_sync_service.dart';
import '../api/api_service.dart';

class AccountChangeNotifier {
  static final AccountChangeNotifier _instance = AccountChangeNotifier._internal();
  factory AccountChangeNotifier() => _instance;
  AccountChangeNotifier._internal();

  final StreamController<void> _controller = StreamController.broadcast();

  Stream<void> get accountChanges => _controller.stream;

  void notifyAccountChanged() {
    _controller.add(null);
  }
}

/// 统一的账户管理器
class AccountManager {
  static const _rainClassroomSessionKey = 'rainclassroom_current_session';
  static const _rainClassroomAccountsKey = 'rainclassroom_accounts';

  static String get _sessionKey => _rainClassroomSessionKey;
  static String get _accountsKey => _rainClassroomAccountsKey;

  static List<User> _accounts = [];
  static String? _currentSessionId;

  /// 获取所有账户
  static List<User> get allAccounts => _accounts;

  /// 获取当前会话的用户 ID（同步，使用缓存）
  static String? get currentSessionId => _currentSessionId;

  static User? get currentUser => _currentSessionId != null ? getAccountById(_currentSessionId!) : null;

  /// 初始化账户管理器
  static Future<void> initialize() async {
    _accounts = await _getAllAccountsFromStorage();
    _currentSessionId = await getCurrentSession();
  }

  /// 从存储中获取所有账户（异步）
  static Future<List<User>> _getAllAccountsFromStorage() async {
    final accountsJson = StorageManager.prefs.getString(_accountsKey);
    if (accountsJson != null) {
      final List<dynamic> accountsData = json.decode(accountsJson);
      return accountsData.map((data) => User.fromJson(data)).toList();
    }
    return [];
  }

  /// 保存账户列表到存储
  static Future<void> _saveAccounts() async {
    final accountsJson = json.encode(_accounts.map((u) => u.toJson()).toList());
    await StorageManager.prefs.setString(_accountsKey, accountsJson);
  }
  
  /// 获取当前会话的用户 ID
  static Future<String?> getCurrentSession() async {
    _currentSessionId = StorageManager.prefs.getString(_sessionKey);
    return _currentSessionId;
  }

  /// 设置当前会话的用户 ID
  static Future<void> setCurrentSession(String? userId) async {
    _currentSessionId = userId;

    if (userId != null) {
      StorageManager.prefs.setString(_sessionKey, userId);
      final user = getAccountById(userId);
      if (user != null) {
        _accounts.remove(user);
        _accounts.insert(0, user);
        _saveAccounts();
      }
    } else {
      StorageManager.prefs.remove(_sessionKey);
    }
    AccountChangeNotifier().notifyAccountChanged();
  }

  /// 临时设置当前会话的用户 ID 修改内存
  static void setCurrentSessionTemp(String? userId) {
    _currentSessionId = userId;
  }

  /// 检查是否存在活跃会话（同步，使用内存缓存）
  static bool hasActiveSession() {
    return _currentSessionId != null && _currentSessionId!.isNotEmpty;
  }

  /// 根据ID获取账户（同步，使用缓存）
  static User? getAccountById(String userId) {
    try {
      return _accounts.firstWhere((acc) => acc.uid == userId);
    } catch (e) {
      return null;
    }
  }

  /// 添加账户（如果已存在则更新）
  static Future<void> addAccount(User user, {bool autoSync = true}) async {
    final index = _accounts.indexWhere((acc) => acc.uid == user.uid);

    // 将临时Cookie迁移到该账号
    await CookieManager.saveTempCookies(user.uid);

    if (index != -1) {
      // 若原账号有备注且新对象无备注，保留原备注
      if (user.remark.isEmpty && _accounts[index].remark.isNotEmpty) {
        user.remark = _accounts[index].remark;
      }
      _accounts[index] = user;
      if (user.uid == _currentSessionId) {
        AccountChangeNotifier().notifyAccountChanged();
      }
    } else {
      _accounts.add(user);
      // 如果没有当前会话，自动设置为当前账户
      if (!hasActiveSession()) {
        await setCurrentSession(user.uid);
      }
    }
    await _saveAccounts();
    if (autoSync) {
      CloudSyncService.triggerAutoUpload();
    }
  }

  /// 修改指定账号的备注
  static Future<void> updateAccountRemark(String userId, String newRemark) async {
    final user = getAccountById(userId);
    if (user != null) {
      user.setRemark(newRemark);
      await _saveAccounts();
      AccountChangeNotifier().notifyAccountChanged();
      CloudSyncService.triggerAutoUpload();
    }
  }

  /// 保存指定账号绑定的专属设备指纹
  static Future<void> updateUserDevice(String userId, Map<String, dynamic> device) async {
    final user = getAccountById(userId);
    if (user != null) {
      user.deviceInfo = device;
      await _saveAccounts();
    }
  }

  /// 获取用户的 Cookie 字符串
  static String? getCookie(String userId) {
    return CookieManager.getCookieString(userId);
  }

  /// 保存账号与 Cookie（供云端拉取注入使用，不反向触发自动上传）
  static Future<void> saveAccount(User user, String cookie) async {
    await CookieManager.saveCookieString(user.uid, cookie);
    await addAccount(user, autoSync: false);
  }

  /// 批量删除账户
  static Future<void> removeAccounts(List<String> userIds) async {
    _accounts.removeWhere((acc) => userIds.contains(acc.uid));
    await _saveAccounts();

    for (var uid in userIds) {
      if (uid == currentSessionId) {
        setCurrentSession(null);
      }
      await CookieManager.clearCookiesForUser(uid);
    }
    AccountChangeNotifier().notifyAccountChanged();
    CloudSyncService.triggerAutoUpload();
  }

  /// 刷新账号列表
  static Future<void> reloadAccounts() async {
    _accounts = await _getAllAccountsFromStorage();
    await CookieManager.loadAllCookies();
    final currentSession = await getCurrentSession();
    await setCurrentSession(currentSession);
  }

  /// 更新指定账号的有效性状态并持久化保存
  static Future<void> updateAccountStatus(String userId, bool isValid) async {
    final user = getAccountById(userId);
    if (user != null) {
      if (user.status != isValid) {
        user.setStatus(isValid);
        await _saveAccounts();
        AccountChangeNotifier().notifyAccountChanged();
      }
    }
  }

  /// 校验单个账号凭证的有效性
  /// 返回: true (有效), false (明确失效), null (网络超时或无法连接)
  static Future<bool?> verifyAccount(User user) async {
    try {
      final url = '/v/course_meta/user_info';
      final response = await ApiService.sendRequest(
        url,
        userId: user.uid,
        receiveTimeoutSeconds: 8,
      );

      // response 为 null，通常为网络超时、断网或 DNS 异常，保持原有状态避免误报
      if (response == null) {
        return null;
      }

      // HTTP 401/403 明确未授权/凭证失效
      if (response.statusCode == 401 || response.statusCode == 403) {
        await updateAccountStatus(user.uid, false);
        return false;
      }

      // 检查返回内容是否为 HTML（未登录 302 重定向到网页端登录页）
      if (response.data is String) {
        final content = (response.data as String).trim().toLowerCase();
        if (content.contains('<html') ||
            content.contains('<!doctype') ||
            content.contains('login') ||
            content.contains('/v2/web/index')) {
          await updateAccountStatus(user.uid, false);
          return false;
        }
        return null;
      }

      if (response.data is Map) {
        final resMap = response.data as Map;
        final data = resMap['data'];
        final code = resMap['code'];

        // 1. 成功解析到 user_profile -> 凭证有效！
        // 雨课堂 Django /v/course_meta/user_info 接口返回 {"data": {"user_profile": {...}}, "success": true}，无 code 字段
        if (data is Map && data['user_profile'] != null && data['user_profile'] is Map) {
          final userProfile = data['user_profile'] as Map;
          final avatar = (userProfile['avatar']?.toString().isNotEmpty == true)
              ? userProfile['avatar'].toString()
              : (userProfile['avatar_96']?.toString() ?? '');
          final name = userProfile['name']?.toString() ?? '';
          // 若头像或姓名有缺失，自动更新个人资料
          if (avatar.isNotEmpty && user.avatar.isEmpty) {
            final updated = User(
              uid: user.uid,
              name: name.isNotEmpty ? name : user.name,
              avatar: avatar,
              phone: user.phone,
              school: userProfile['school']?.toString() ?? user.school,
              remark: user.remark,
              platform: user.platform,
              deviceInfo: user.deviceInfo,
              imAccount: user.imAccount,
              status: true,
            );
            await addAccount(updated, autoSync: false);
          } else {
            await updateAccountStatus(user.uid, true);
          }
          return true;
        }

        // 2. 明确的业务错误码或失效标识（如 token 失效 50017，或 success == false，或 error != null）
        final bool isExplicitFailure = (code != null && code != 0) ||
            resMap['error'] != null ||
            resMap['success'] == false ||
            (data is Map && data['user_profile'] == null && (data.isEmpty || resMap['error'] != null));

        if (isExplicitFailure) {
          await updateAccountStatus(user.uid, false);
          return false;
        }
      }

      return null;
    } catch (e) {
      debugPrint('校验账号 [${user.name}] 状态异常: $e');
      return null;
    }
  }

  /// 并发校验所有账号的登录有效性
  static Future<AccountCheckResult> checkAllAccountsValidity() async {
    final accounts = List<User>.from(_accounts);
    if (accounts.isEmpty) {
      return const AccountCheckResult(
        totalCount: 0,
        validCount: 0,
        invalidAccounts: [],
      );
    }

    final results = await Future.wait(
      accounts.map((acc) => verifyAccount(acc)),
    );

    int validCount = 0;
    final List<User> invalidAccounts = [];
    bool hasNetworkError = false;

    for (int i = 0; i < accounts.length; i++) {
      final res = results[i];
      final acc = accounts[i];
      if (res == true) {
        validCount++;
      } else if (res == false) {
        invalidAccounts.add(acc);
      } else {
        // 网络异常
        hasNetworkError = true;
        if (!acc.status) {
          invalidAccounts.add(acc);
        } else {
          validCount++;
        }
      }
    }

    return AccountCheckResult(
      totalCount: accounts.length,
      validCount: validCount,
      invalidAccounts: invalidAccounts,
      hasNetworkError: hasNetworkError && invalidAccounts.isEmpty && validCount == 0,
    );
  }
}

/// 账号有效性检测结果封装
class AccountCheckResult {
  final int totalCount;
  final int validCount;
  final List<User> invalidAccounts;
  final bool hasNetworkError;

  const AccountCheckResult({
    required this.totalCount,
    required this.validCount,
    required this.invalidAccounts,
    this.hasNetworkError = false,
  });

  bool get allValid => invalidAccounts.isEmpty && !hasNetworkError;
  bool get hasInvalid => invalidAccounts.isNotEmpty;
}