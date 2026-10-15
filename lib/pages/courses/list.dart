import 'package:flutter/material.dart';
import 'dart:async';
import 'package:collection/collection.dart';

import '../../api/course.dart';
import '../../api/api_service.dart';
import '../../session/account.dart';
import '../../models/user.dart';
import '../../models/course.dart';
import '../widget/scan.dart';
import '../widget/avatar.dart';
import '../widget/terminal_console_modal.dart';
import '../presentation.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

final GlobalKey coursesPageKey = GlobalKey();

class _CoursesPageState extends State<CoursesPage> with WidgetsBindingObserver {
  List<Course> _courses = [];
  bool _isLoading = true;
  StreamSubscription? _accountChangeSubscription;
  Timer? _refreshTimer;
  List<dynamic> _lastOnLessonCourses = [];
  bool _isVisible = false;

  void refreshCourses() {
    _loadCourses();
  }

  void onVisibilityChanged(bool visible) {
    _isVisible = visible;
    if (visible) {
      _startPeriodicRefresh();
    } else {
      _refreshTimer?.cancel();
    }
  }

  /// 使用在线课堂数据更新课程列表
  void updateWithOnLessonCourses(List<Map<String, dynamic>>? onLessonCourses) {
    _loadCourses(onLessonCourses);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isVisible = true;
    _loadCourses();

    // 监听账户变更事件
    _accountChangeSubscription =
        AccountChangeNotifier().accountChanges.listen((_) {
          if (mounted) {
            _lastOnLessonCourses = [];
            _loadCourses();
          }
          _startPeriodicRefresh();
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _refreshTimer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _startPeriodicRefresh();
    }
  }

  void _startPeriodicRefresh() {
    if (!_isVisible) return;

    if (_refreshTimer != null && _refreshTimer!.isActive) return;

    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || !AccountManager.hasActiveSession()) return;

      try {
        final onLessonCourses = await RCCourseApi.getOnLesson();
        if (onLessonCourses != null && mounted) {
          if (!const DeepCollectionEquality().equals(_lastOnLessonCourses, onLessonCourses)) {
            _lastOnLessonCourses = onLessonCourses;
            _loadCourses(onLessonCourses);
          }
        }
      } catch (e) {
        debugPrint('Periodic refresh error: $e');
      }
    });
  }

  Future<void> _loadCourses([List<dynamic>? onLessonCourses]) async {
    setState(() {
      _isLoading = true;
    });

    if (!AccountManager.hasActiveSession()) {
      setState(() {
        _courses = [];
        _isLoading = false;
      });
      return;
    }

    try {
      final coursesData = await RCCourseApi.getCoursesList(onLessonCourses);

      if (coursesData != null && coursesData.isNotEmpty) {
        setState(() {
          _courses = coursesData;
          _isLoading = false;
        });
      } else {
        setState(() {
          _courses = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _courses = [];
        _isLoading = false;
      });
    }
  }

  Future<void> handleScanContent(String result) async {
    if (!AccountManager.hasActiveSession()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('二维码内容'),
              content: SelectableText(result),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      });
      return;
    }
  
    if (result.startsWith('http')) {
      try {
        final lowerUrl = result.toLowerCase();
        // 识别雨课堂课堂签到二维码 (支持各类域名前缀与扫码/签到/课堂/卡片路径)
        if (lowerUrl.contains('yuketang.cn') &&
            (lowerUrl.contains('lesson') ||
             lowerUrl.contains('check-in') ||
             lowerUrl.contains('checkin') ||
             lowerUrl.contains('dynamic') ||
             lowerUrl.contains('scan') ||
             lowerUrl.contains('classroom') ||
             lowerUrl.contains('card'))) {
          if (!AccountManager.hasActiveSession()) {
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  content: const Text('没有可用账号'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                );
              },
            );
            return;
          }

          await _multiScan(result);
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('扫描到链接'),
                  content: SelectableText(result),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                  ],
                );
              },
            );
          });
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL 解析失败：$e')),
        );
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描结果：$result')),
      );
    }
  }

  /// 批量扫描签到（支持全量签到与针对失败账号的定向补签）
  Future<void> _multiScan(
    String qrCodeUrl, {
    List<User>? targetAccounts,
    TerminalConsoleController? existingController,
  }) async {
    final allAccounts = targetAccounts ?? AccountManager.allAccounts;
    if (allAccounts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的账号进行签到')),
      );
      return;
    }

    final isContinuation = existingController != null;
    final controller = existingController ?? TerminalConsoleController();
    bool isModalOpen = true;

    // 如果是新启动，弹出 macOS 终端控制台
    if (!isContinuation) {
      TerminalConsoleModal.show(
        context,
        controller: controller,
      ).then((_) {
        isModalOpen = false;
      });
      controller.addLog('系统', '启动批量签到通道 (共 ${allAccounts.length} 人)...', type: TerminalLogType.info);
    } else {
      controller.addLog('系统', '收到新动态码，开始补签未成功账号 (共 ${allAccounts.length} 人)...', type: TerminalLogType.info);
    }

    controller.updateStatus('正在签到: 0/${allAccounts.length}');

    int successCount = 0;
    final List<User> failedAccounts = [];
    int completedCount = 0;

    // 全量账号毫秒级并发投递，赶在 3-5 秒动态二维码刷新前全部完成
    await Future.wait(allAccounts.map((user) async {
      controller.addLog(user.name, '发起自适应签到请求...', type: TerminalLogType.info);

      final api = RCCourseApi(user);
      final status = await api.scan(qrCodeUrl);
      final loc = api.lastLocationResult;

      completedCount++;
      controller.updateStatus('正在签到: $completedCount/${allAccounts.length}');

      if (status == 0) {
        successCount++;
        if (loc != null && loc.needLocation) {
          final addr = loc.address ?? '指定教室范围';
          final dist = loc.distanceM != null ? ' (偏差 ${loc.distanceM}m)' : '';
          final lateTag = loc.isLate ? ' [迟到]' : '';
          controller.addLog(
            user.name,
            '位置打卡成功 [$addr$dist$lateTag]',
            type: TerminalLogType.good,
          );
        } else {
          controller.addLog(user.name, '常规扫码签到成功', type: TerminalLogType.good);
        }
      } else {
        failedAccounts.add(user);
        if (status == 51203) {
          controller.addLog(user.name, '动态二维码已过期 (51203)', type: TerminalLogType.bad);
        } else if (status == 51001) {
          controller.addLog(user.name, '位置签到已截止 (51001)', type: TerminalLogType.bad);
        } else if (status == 51002) {
          controller.addLog(user.name, '坐标超出教室允许半径 (51002)', type: TerminalLogType.bad);
        } else {
          final msg = loc?.message ?? '错误码：$status';
          controller.addLog(user.name, '签到失败 ($msg)', type: TerminalLogType.bad);
        }
      }
    }));

    controller.setFinished(hasFailures: failedAccounts.isNotEmpty);
    final scannedLessonId = RCCourseApi.lastScannedLessonId;

    if (failedAccounts.isNotEmpty) {
      controller.updateStatus(
        '已完成: $successCount 成功, ${failedAccounts.length} 待补签',
        color: const Color(0xFFFF9F0A),
      );
      controller.addLog('系统', '部分账号因动态码更新未成功，请重新扫码补签', type: TerminalLogType.info);

      // 激活补签窗口的双按钮：【不管了，直接进入课堂】与【重新扫码补签】
      controller.setAction(
        text: '重新扫码补签 (${failedAccounts.length}人)',
        onPressed: () async {
          // 打开扫码窗口，等待扫出新码并退出后，只对 failedAccounts 执行补签
          final newCode = await Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (scanCtx) => const ScanPage(),
            ),
          );
          if (newCode != null && newCode.isNotEmpty && mounted) {
            _multiScan(
              newCode,
              targetAccounts: failedAccounts,
              existingController: controller,
            );
          }
        },
        secondaryText: '不管了，直接进入课堂',
        onSecondaryPressed: () {
          if (!mounted) return;
          Navigator.of(context).pop(); // 关闭终端弹窗
          if (scannedLessonId != null && scannedLessonId.isNotEmpty) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PresentationPage(
                  lessonId: scannedLessonId,
                  title: '正在进行的课堂',
                ),
              ),
            );
          }
        },
      );
    } else {
      controller.updateStatus(
        '所有账号已全部签到成功！ (5s)',
        color: const Color(0xFF30D158),
      );
      controller.addLog('系统', '全部账号已签到成功，5 秒后自动进入课堂（可点击立即进入）', type: TerminalLogType.good);

      bool hasNavigated = false;
      Timer? countdownTimer;

      void navigateToClass() {
        countdownTimer?.cancel();
        if (hasNavigated || !mounted) return;
        hasNavigated = true;
        if (isModalOpen) {
          Navigator.of(context).pop(); // 关闭终端弹窗
        }
        if (scannedLessonId != null && scannedLessonId.isNotEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PresentationPage(
                lessonId: scannedLessonId,
                title: '正在进行的课堂',
              ),
            ),
          );
        }
      }

      if (scannedLessonId != null && scannedLessonId.isNotEmpty) {
        int remainingSec = 5;
        controller.setAction(
          text: '立即进入课堂 (${remainingSec}s)',
          icon: Icons.login_rounded,
          onPressed: navigateToClass,
        );

        countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted || hasNavigated) {
            timer.cancel();
            return;
          }
          remainingSec--;
          if (remainingSec <= 0) {
            timer.cancel();
            navigateToClass();
          } else {
            controller.updateStatus(
              '所有账号已全部签到成功！ (${remainingSec}s)',
              color: const Color(0xFF30D158),
            );
            controller.setAction(
              text: '立即进入课堂 (${remainingSec}s)',
              icon: Icons.login_rounded,
              onPressed: navigateToClass,
            );
          }
        });
      } else {
        controller.setAction(text: null);
      }
    }
  }

  void _openPresentationPage(Course course) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PresentationPage(
          lessonId: course.lessonId!,
          title: course.name,
        ),
      ),
    );
  }

  /// 智能鉴别签到类型并自适应进班
  Future<void> _handleCourseCardTap(Course course) async {
    final lessonId = course.lessonId;
    if (lessonId == null || lessonId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前课程尚未开课或没有课件数据')),
      );
      return;
    }

    final currentAccount = AccountManager.currentUser;
    if (currentAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未检测到已登录账号，请先添加或切换账号')),
      );
      return;
    }

    final allAccounts = AccountManager.allAccounts;

    // 必须双 Token 强校验！所有账号必须同时持有有效的 lessonToken 与 bearerToken 才能直接复用跳过入课探测
    RCCourseApi.activeLessonId = lessonId;
    final allHaveValidTokens = allAccounts.isNotEmpty &&
        allAccounts.every((acc) {
          final accApi = RCCourseApi(acc);
          return (accApi.getLessonToken(lessonId)?.isNotEmpty == true) &&
              (accApi.getBearerToken(lessonId)?.isNotEmpty == true);
        });
    if (allHaveValidTokens) {
      _openPresentationPage(course);
      return;
    }

    // 显示轻量加载遮罩
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false, // 彻底拦截物理返回键与边缘手势返回穿透，避免网络请求完成后的 pop 误杀主界面
        child: Center(
          child: Card(
            elevation: 6,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  SizedBox(width: 16),
                  Text('正在鉴别课堂签到状态...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 阶段 1：以课中进班通道尝试进入，探测是否在其他设备（微信/网页）已完成签到
    final results = await ApiService.sendForEachUser(
      allAccounts,
      (user) async {
        final userApi = RCCourseApi(user);
        final hasTokens = (userApi.getLessonToken(lessonId)?.isNotEmpty == true) &&
            (userApi.getBearerToken(lessonId)?.isNotEmpty == true);
        if (hasTokens) return 0;
        // 全面兼容 21 移动扫码端与 23 网页卡片端：优先以 21 进班换取 Token，遇阻自动无缝降级切换至 23 容错
        return await userApi.checkIn(lessonId, preferSource: 21);
      },
    );

    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭加载框

    // 检查是否有任一账号返回了 50070（动态二维码签到）
    final hasQrCodeRequirement = results.any((r) => r == 50070);
    if (hasQrCodeRequirement) {
      // 场景 A：精准识别为【动态二维码签到】，且未在其他设备签到
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.qr_code_scanner, color: Colors.blue),
              SizedBox(width: 8),
              Text('需要扫码签到'),
            ],
          ),
          content: Text('该课堂【${course.name}】老师已开启【动态二维码签到】，检测到当前账号尚未在其他设备签到，请扫描大屏幕上的动态二维码完成签到。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('立即扫码'),
              onPressed: () async {
                Navigator.of(ctx).pop();
                final code = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (scanCtx) => const ScanPage(),
                  ),
                );
                if (code != null && code.isNotEmpty && mounted) {
                  handleScanContent(code);
                }
              },
            ),
          ],
        ),
      );
      return;
    }

    // 场景 B：课堂已下课 (50004)
    if (results.any((r) => r == 50004)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前课堂已下课或未开课 (50004)')),
      );
      return;
    }

    // 场景 C：位置签到或常规课堂 —— 直接极致速度秒进课堂，绝不刻意留延迟！
    _openPresentationPage(course);

    // 同步在后台极致并发触发全账号位置打卡，绝不阻塞用户看课
    ApiService.sendForEachUser(allAccounts, (user) async {
      final userApi = RCCourseApi(user);
      return await userApi.executeLocationCheckin(lessonId);
    }).then((locResults) {
      if (!mounted) return;
      final activeLocs = locResults.where((r) => r != null && r.needLocation).toList();
      if (activeLocs.isNotEmpty) {
        final successCount = activeLocs.where((r) => r!.isSuccess).length;
        final first = activeLocs.firstWhere((r) => r!.isSuccess, orElse: () => null);
        final addr = first?.address ?? '指定教室范围';
        final dist = first?.distanceM != null ? ' (偏差 ${first!.distanceM!.toStringAsFixed(1)}m)' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successCount == activeLocs.length
                ? '全部账号已自动完成位置签到：$successCount/${activeLocs.length} 成功 [$addr$dist]'
                : '位置签到：$successCount/${activeLocs.length} 账号成功 [$addr$dist]（未签账号可在课内补卡）'),
            backgroundColor: successCount == activeLocs.length ? const Color(0xFF30D158) : const Color(0xFFFF9500),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              final result = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (context) => const ScanPage(),
                ),
              );
              if (result != null && result.isNotEmpty && mounted) {
                handleScanContent(result);
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCourses,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _courses.isEmpty
            ? const Center(
                child: Text(
                  '暂无课程数据',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              )
            : ListView.builder(
                itemCount: _courses.length,
                itemBuilder: (context, index) {
                  var course = _courses[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: InkWell(
                      onTap: () => _handleCourseCardTap(course),
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (course.image.isNotEmpty)
                                      AvatarWidget(
                                        imageUrl: course.image,
                                        size: 50,
                                        borderRadius: 6,
                                        iconSize: 25,
                                      )
                                    else
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.secondaryContainer,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.school,
                                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                                            size: 25,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            course.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            course.teacher,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
          
                                const SizedBox(height: 5),
                                if (course.note != null)
                                  Text(
                                    course.note!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                if (course.schools != null)
                                  Text(
                                    course.schools!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                if (course.beginDate != null && course.endDate != null)
                                  Text(
                                    '开课时间：${course.beginDate} 至 ${course.endDate}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 16,
                            top: 0,
                            bottom: 0,
                            child: Align(
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.chevron_right,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accountChangeSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}
