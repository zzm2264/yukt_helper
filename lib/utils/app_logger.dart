import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 专为生产环境与问题排查设计的非阻塞式错误日志服务
/// 严格保存在 App 私有数据目录，异步入队写入，绝对不阻塞主线程与网络交互
class AppLogger {
  static AppLogger? _instance;
  static AppLogger get instance => _instance ??= AppLogger._();
  factory AppLogger() => instance;
  AppLogger._();

  Directory? _logDir;
  File? _currentFile;
  String? _currentDateStr;
  
  // 异步日志管道：以 Stream 缓冲解耦业务逻辑与文件磁盘 I/O
  final StreamController<String> _logQueue = StreamController<String>.broadcast();
  StreamSubscription<String>? _subscription;
  bool _isInitialized = false;

  /// 初始化日志系统（在 main.dart 启动）
  static Future<void> initialize() async {
    await instance._init();
  }

  Future<void> _init() async {
    if (_isInitialized) return;
    try {
      String basePath;
      try {
        final docDir = await getApplicationDocumentsDirectory();
        basePath = docDir.path;
      } catch (_) {
        // 在单元测试或无原生环境时安全降级至系统临时目录，确保测试 100% 通过
        basePath = Directory.systemTemp.path;
      }

      _logDir = Directory('$basePath/app_logs');
      if (!await _logDir!.exists()) {
        await _logDir!.create(recursive: true);
      }

      _updateCurrentLogFile();

      // 启动单消费者顺序异步追加写，避免多账号并发写文件产生锁冲突
      _subscription = _logQueue.stream.listen((logText) async {
        try {
          _updateCurrentLogFile();
          if (_currentFile != null) {
            await _currentFile!.writeAsString(
              '$logText\n',
              mode: FileMode.append,
              flush: false,
            );
          }
        } catch (_) {
          // 写入失败静默处理，严禁影响 App 运行
        }
      });

      // 清理超过 7 天的历史过期日志文件，释放存储空间
      _cleanOldLogs();
      _isInitialized = true;

      logInfo('SYSTEM', 'AppLogger 日志系统初始化完成，存储路径: ${_logDir?.path}');
    } catch (e) {
      debugPrint('AppLogger 初始化异常: $e');
    }
  }

  void _updateCurrentLogFile() {
    if (_logDir == null) return;
    final now = DateTime.now();
    final dateStr = '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}';

    if (_currentDateStr != dateStr || _currentFile == null) {
      _currentDateStr = dateStr;
      _currentFile = File('${_logDir!.path}/error_$dateStr.log');
    }
  }

  Future<void> _cleanOldLogs() async {
    if (_logDir == null) return;
    try {
      final now = DateTime.now();
      final entities = _logDir!.listSync();
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.log')) {
          final stat = entity.statSync();
          if (now.difference(stat.modified).inDays > 7) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// 内部核心入队方法（毫秒级无锁推送）
  void _enqueue(String level, String tag, String message, [String? extra]) {
    try {
      final now = DateTime.now();
      final timeStr = '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)} '
          '${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:${_twoDigits(now.second)}.${now.millisecond.toString().padLeft(3, '0')}';

      final sb = StringBuffer();
      sb.write('[$timeStr] [$level] [$tag] $message');
      if (extra != null && extra.isNotEmpty) {
        sb.write('\n$extra');
      }

      // 非阻塞入队
      _logQueue.add(sb.toString());

      // 在 Debug 模式同步打印到控制台
      if (kDebugMode) {
        debugPrint(sb.toString());
      }
    } catch (_) {}
  }

  static String _twoDigits(int n) => n >= 10 ? '$n' : '0$n';

  // -------------------------------------------------------------
  // 结构化日志记录接口
  // -------------------------------------------------------------

  /// 记录 Flutter 系统级错误（如渲染树、Widget 抛出异常）
  void logSystemError(Object error, StackTrace? stackTrace, {String? context}) {
    final extra = StringBuffer();
    if (context != null) extra.writeln('Context: $context');
    extra.writeln('Exception: $error');
    if (stackTrace != null) extra.writeln('StackTrace:\n$stackTrace');
    _enqueue('FATAL', 'FLUTTER_SYSTEM', error.toString(), extra.toString().trim());
  }

  /// 记录未捕获的根 Isolate 异步错误
  void logUnhandledAsyncError(Object error, StackTrace stackTrace) {
    final extra = StringBuffer();
    extra.writeln('Unhandled Async Exception: $error');
    extra.writeln('StackTrace:\n$stackTrace');
    _enqueue('FATAL', 'ASYNC_ERROR', error.toString(), extra.toString().trim());
  }

  /// 详细记录 API 网络请求故障（包含请求路径、方法、参数、状态码、响应体、耗时与用户ID）
  void logApiError({
    required String url,
    String method = 'GET',
    int? statusCode,
    dynamic requestBody,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
    dynamic responseData,
    String? errorMessage,
    StackTrace? stackTrace,
    String? userId,
    int? durationMs,
  }) {
    final extra = StringBuffer();
    extra.writeln('  URL: [$method] $url');
    if (userId != null) extra.writeln('  UserId: $userId');
    if (statusCode != null) extra.writeln('  StatusCode: $statusCode');
    if (durationMs != null) extra.writeln('  Duration: ${durationMs}ms');
    if (queryParams != null && queryParams.isNotEmpty) extra.writeln('  Params: $queryParams');
    if (requestBody != null) extra.writeln('  Body: $requestBody');
    if (headers != null && headers.isNotEmpty) {
      final safeHeaders = Map<String, String>.from(headers);
      if (safeHeaders.containsKey('authorization')) {
        safeHeaders['authorization'] = 'Bearer ***';
      }
      extra.writeln('  Headers: $safeHeaders');
    }
    if (errorMessage != null) extra.writeln('  Error: $errorMessage');
    if (responseData != null) extra.writeln('  Response: $responseData');
    if (stackTrace != null) extra.writeln('  StackTrace:\n$stackTrace');

    _enqueue('ERROR', 'API_HTTP', '[$method] $url -> Status: $statusCode', extra.toString().trim());
  }

  /// 记录雨课堂网关返回的业务错误码（如 50070 扫码、51001 截止、51002 超出范围、50017 Token失效）
  void logApiBusinessError({
    required String url,
    required int code,
    String? msg,
    dynamic data,
    String? userId,
  }) {
    final extra = StringBuffer();
    extra.writeln('  URL: $url');
    if (userId != null) extra.writeln('  UserId: $userId');
    extra.writeln('  BusinessCode: $code, Message: $msg');
    if (data != null) extra.writeln('  Data: $data');

    _enqueue('WARN', 'API_BIZ_CODE', '接口业务报错 code: $code ($msg)', extra.toString().trim());
  }

  /// 记录 WebSocket 长连接异常与重连
  void logWebSocketError(String message, {dynamic error, StackTrace? stackTrace}) {
    final extra = StringBuffer();
    if (error != null) extra.writeln('Error: $error');
    if (stackTrace != null) extra.writeln('StackTrace:\n$stackTrace');
    _enqueue('ERROR', 'WEBSOCKET', message, extra.toString().trim());
  }

  /// 记录位置签到全生命周期关键事件
  void logCheckIn(String action, {required String lessonId, required int code, String? message, String? address, double? distanceM}) {
    final extra = StringBuffer();
    extra.writeln('  LessonId: $lessonId');
    extra.writeln('  ResultCode: $code, Msg: $message');
    if (address != null) extra.writeln('  Address: $address');
    if (distanceM != null) extra.writeln('  Distance: ${distanceM}m');

    final level = code == 0 ? 'INFO' : 'WARN';
    _enqueue(level, 'CHECKIN', '$action -> code: $code', extra.toString().trim());
  }

  /// 普通信息级日志
  void logInfo(String tag, String message) {
    _enqueue('INFO', tag, message);
  }

  /// 警告级日志
  void logWarning(String tag, String message, [Map<String, dynamic>? extras]) {
    final extraStr = extras?.toString();
    _enqueue('WARN', tag, message, extraStr);
  }

  // -------------------------------------------------------------
  // 便捷提取与管理接口（供后续排查与导出使用）
  // -------------------------------------------------------------

  /// 获取日志文件保存的绝对目录路径（用于 ADB pull 或开发者定位）
  Future<String> getLogDirectoryPath() async {
    if (_logDir != null) return _logDir!.path;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      return '${docDir.path}/app_logs';
    } catch (_) {
      return '${Directory.systemTemp.path}/app_logs';
    }
  }

  static Future<String> getDirectoryPath() => instance.getLogDirectoryPath();

  /// 获取所有已保存的日志文件列表（按时间倒序）
  Future<List<File>> getLogFiles() async {
    final path = await getLogDirectoryPath();
    final dir = Directory(path);
    if (!await dir.exists()) return [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList();

    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  static Future<List<File>> getAllFiles() => instance.getLogFiles();

  /// 获取最近若干行的日志列表（方便在 App 界面快速查看或复制）
  Future<List<String>> getRecentLogs({int maxLines = 200}) async {
    final files = await getLogFiles();
    if (files.isEmpty) return [];

    final buffer = <String>[];
    for (var file in files) {
      try {
        final lines = await file.readAsLines();
        for (var i = lines.length - 1; i >= 0; i--) {
          buffer.add(lines[i]);
          if (buffer.length >= maxLines) break;
        }
      } catch (_) {}
      if (buffer.length >= maxLines) break;
    }

    return buffer.reversed.toList();
  }

  /// 获取最近若干行的完整日志字符串
  Future<String> getRecentLogsText({int maxLines = 200}) async {
    final lines = await getRecentLogs(maxLines: maxLines);
    if (lines.isEmpty) return '暂无错误日志记录。';
    return lines.join('\n');
  }

  /// 清空所有历史日志文件
  Future<void> clearLogs() async {
    final files = await getLogFiles();
    for (var f in files) {
      try {
        await f.delete();
      } catch (_) {}
    }
    logInfo('SYSTEM', '用户已主动清空历史日志。');
  }

  /// 释放日志资源
  void dispose() {
    _subscription?.cancel();
    _logQueue.close();
  }
}
