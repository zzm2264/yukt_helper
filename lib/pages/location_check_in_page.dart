// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../api/course.dart';
import '../api/api_service.dart';
import '../session/account.dart';
import '../utils/location_helper.dart';

/// 课中位置签到 5 级状态枚举（严格对标官方 _SignState 定义）
enum _SignState {
  outOfRange,     // 0: 超出教室围栏范围
  inRangeOnTime,  // 1: 范围内准时打卡
  inRangeLate,    // 2: 范围内迟到打卡
  submitted,      // 3: 签到成功已提交
  ended,          // 4: 签到活动已截止
}

/// 官方独立全屏位置打卡页（严格对标 package:rain LocationCheckInPage）
class LocationCheckInPage extends StatefulWidget {
  final String lessonId;
  final VoidCallback? onCheckInSuccess;
  final bool isPreview;

  const LocationCheckInPage({
    super.key,
    required this.lessonId,
    this.onCheckInSuccess,
    this.isPreview = false,
  });

  @override
  State<LocationCheckInPage> createState() => _LocationCheckInPageState();
}

class _LocationCheckInPageState extends State<LocationCheckInPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isSubmitting = false;
  _SignState _signState = _SignState.inRangeOnTime;

  Gcj02Coord? _studentCoord;
  String? _address;
  double? _distanceM;
  double _radiusM = 20.0;
  double? _centerLat;
  double? _centerLng;

  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  DateTime? _checkInTime;
  bool _isLate = false;
  List<User> _succeededAccounts = [];
  List<User> _failedAccounts = [];

  int _startMs = 0;
  int _lateAfterMs = 0;
  int _endMs = 0;
  String? _errorMessage;

  late AnimationController _rippleController;
  late Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _rippleAnimation = CurvedAnimation(
      parent: _rippleController,
      curve: Curves.easeOutQuad,
    );

    _loadEligibility();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _rippleController.dispose();
    super.dispose();
  }

  bool _isLateNow() {
    if (_lateAfterMs <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now > _lateAfterMs;
  }

  double? _parseCoord(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.trim());
    return null;
  }

  /// 加载签到资格与配置 (对标官方 _loadEligibility)
  Future<void> _loadEligibility() async {
    if (widget.isPreview) {
      final allAccounts = AccountManager.allAccounts;
      setState(() {
        _isLoading = false;
        _signState = _SignState.inRangeOnTime;
        _remainingSeconds = 180;
        _distanceM = 8.5;
        _radiusM = 20.0;
        _address = '北京市海淀区清华大学第六教学楼6A102';
        _studentCoord = const Gcj02Coord(39.9998, 116.3265);
        _succeededAccounts = allAccounts.isNotEmpty
            ? allAccounts
            : [User(name: '演示账号', avatar: '', phone: '13800000000', uid: '10001', remark: '大号')];
        _failedAccounts = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final api = RCCourseApi(AccountManager.currentUser);
      final eligData = await api.getLocationEligibility(widget.lessonId);

      if (eligData == null || eligData['code'] != 0) {
        setState(() {
          _isLoading = false;
          _errorMessage = eligData?['msg'] as String? ?? '网络请求失败，请稍后重试';
        });
        return;
      }

      final data = eligData['data'];
      if (data is! Map) {
        setState(() {
          _isLoading = false;
          _errorMessage = '当前课堂无有效签到数据';
        });
        return;
      }

      // 检查是否已经签到完成
      final bool alreadySigned = data['signed'] == true || data['checkInTime'] != null;
      if (alreadySigned) {
        final checkInMs = (data['checkInTime'] as num?)?.toInt();

        // 探测多账号环境下所有账号的具体签到状态
        final allAccounts = AccountManager.allAccounts;
        final List<User> succ = [];
        final List<User> fail = [];

        final eligList = await ApiService.sendForEachUser(
          allAccounts,
          (user) async {
            final last = RCCourseApi(user).lastLocationResult;
            if (last != null && last.isSuccess) {
              return true;
            }
            final res = await RCCourseApi(user).getLocationEligibility(widget.lessonId);
            if (res != null && res['code'] == 0 && res['data'] is Map) {
              final d = res['data'];
              return d['signed'] == true || d['checkInTime'] != null;
            }
            return false;
          },
        );

        for (int i = 0; i < allAccounts.length; i++) {
          final user = allAccounts[i];
          final isUserSigned = (i < eligList.length && eligList[i] == true);
          if (isUserSigned) {
            succ.add(user);
          } else {
            fail.add(user);
          }
        }

        if (succ.isEmpty && AccountManager.currentUser != null) {
          succ.add(AccountManager.currentUser!);
        }

        setState(() {
          _isLoading = false;
          _signState = _SignState.submitted;
          _isLate = data['isLate'] == true;
          _checkInTime = checkInMs != null
              ? DateTime.fromMillisecondsSinceEpoch(checkInMs)
              : DateTime.now();
          _address = data['address'] as String? ?? '教室内已登记定位';
          _succeededAccounts = succ;
          _failedAccounts = fail;
        });
        return;
      }

      final session = data['session'];
      if (session is! Map) {
        setState(() {
          _isLoading = false;
          _errorMessage = '当前课堂未开启位置签到';
        });
        return;
      }

      _startMs = (session['startMs'] as num?)?.toInt() ?? 0;
      _endMs = (session['endMs'] as num?)?.toInt() ?? 0;
      _lateAfterMs = (session['lateAfterMs'] as num?)?.toInt() ?? 0;

      _centerLat = _parseCoord(session['centerLat'] ?? session['latitude'] ?? session['lat']);
      _centerLng = _parseCoord(session['centerLng'] ?? session['longitude'] ?? session['lng']);
      _radiusM = _parseCoord(session['radiusM'] ?? session['radius']) ?? 20.0;

      final now = DateTime.now().millisecondsSinceEpoch;

      // 判断是否未到开始时间
      if (_startMs > 0 && now < _startMs) {
        setState(() {
          _isLoading = false;
          _errorMessage = '位置签到尚未开始';
        });
        return;
      }

      // 判断是否已截止
      if (_endMs > 0 && now > _endMs) {
        // 探测各账号在截止前的实际签到状态
        final allAccounts = AccountManager.allAccounts;
        final List<User> succ = [];
        final List<User> fail = [];
        final eligList = await ApiService.sendForEachUser(
          allAccounts,
          (user) async {
            final last = RCCourseApi(user).lastLocationResult;
            if (last != null && last.isSuccess) return true;
            final res = await RCCourseApi(user).getLocationEligibility(widget.lessonId);
            if (res != null && res['code'] == 0 && res['data'] is Map) {
              final d = res['data'];
              return d['signed'] == true || d['checkInTime'] != null;
            }
            return false;
          },
        );

        for (int i = 0; i < allAccounts.length; i++) {
          final user = allAccounts[i];
          final isUserSigned = (i < eligList.length && eligList[i] == true);
          if (isUserSigned) {
            succ.add(user);
          } else {
            fail.add(user);
          }
        }

        setState(() {
          _isLoading = false;
          _signState = _SignState.ended;
          _succeededAccounts = succ;
          _failedAccounts = fail;
        });
        return;
      }

      // 计算倒计时秒数
      if (_endMs > 0) {
        _remainingSeconds = max(0, (_endMs - now) ~/ 1000);
        _startCountdown();
      }

      // 执行定位与逆地理编码
      await _locate();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('加载位置签到资格异常: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = '获取签到配置失败: $e';
      });
    }
  }

  /// 启动 1 秒高精度倒计时 (对标官方 _startCountdown)
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
          // 若进入迟到时间窗且原状态为准时，自动迁移为迟到
          if (_signState == _SignState.inRangeOnTime && _isLateNow()) {
            _signState = _SignState.inRangeLate;
          }
        });
      } else {
        timer.cancel();
        if (_signState != _SignState.submitted) {
          setState(() {
            _signState = _SignState.ended;
          });
        }
      }
    });
  }

  /// 生成/获取坐标并校验围栏 (对标官方 _locate & _updateRangeState)
  Future<void> _locate({bool forceCalibrate = false}) async {
    if (_centerLat == null || _centerLng == null) return;

    // 生成极坐标高保真微抖动火星坐标 (GCJ-02)，确保严格处于教师指定半径以内
    final coord = LocationHelper.generateJitteredCoord(_centerLat!, _centerLng!, _radiusM);
    final distanceM = LocationHelper.calculateDistanceMeters(
      coord.lat,
      coord.lng,
      _centerLat!,
      _centerLng!,
    );

    _studentCoord = coord;
    _distanceM = distanceM;

    // 状态流转
    if (distanceM <= _radiusM) {
      _signState = _isLateNow() ? _SignState.inRangeLate : _SignState.inRangeOnTime;
    } else {
      _signState = _SignState.outOfRange;
    }

    // 逆地理编码换取地名快照 (对标官方 _reverseGeocode)
    try {
      final api = RCCourseApi(AccountManager.currentUser);
      final proxyRes = await api.registerLocationProxy(coord.lat, coord.lng, widget.lessonId);
      if (proxyRes != null && proxyRes['result'] is Map) {
        final result = proxyRes['result'];
        final addr = result['formatted_addresses']?['recommend'] ??
            result['address'] ??
            result['formatted_addresses']?['rough'] ??
            result['formatted_addresses']?['standard_address'];
        if (addr is String && addr.isNotEmpty) {
          _address = addr;
        }
      }
    } catch (e) {
      debugPrint('逆地理编码请求异常: $e');
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// 提交签到 (对标官方 _submit，调用 source: 27 与双通道容错，支持全量提交或定向补签)
  Future<void> _submit({List<User>? targetAccounts}) async {
    if (_isSubmitting) return;

    if (widget.isPreview) {
      final allAccounts = targetAccounts ?? AccountManager.allAccounts;
      setState(() {
        _isSubmitting = false;
        _signState = _SignState.submitted;
        _checkInTime = DateTime.now();
        _isLate = false;
        _address = '北京市海淀区清华大学第六教学楼6A102';
        _distanceM = 8.5;
        _succeededAccounts = allAccounts.isNotEmpty
            ? allAccounts
            : [User(name: '演示账号', avatar: '', phone: '13800000000', uid: '10001', remark: '大号')];
        _failedAccounts = [];
      });
      widget.onCheckInSuccess?.call();
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final accountsToSubmit = targetAccounts ?? AccountManager.allAccounts;
      final results = await ApiService.sendForEachUser(
        accountsToSubmit,
        (user) async {
          final api = RCCourseApi(user);
          return await api.executeLocationCheckin(widget.lessonId);
        },
      );

      if (!mounted) return;

      final List<User> newlySucc = [];
      final List<User> stillFail = [];
      for (int i = 0; i < accountsToSubmit.length; i++) {
        final user = accountsToSubmit[i];
        final res = i < results.length ? results[i] : null;
        if (res != null && res.isSuccess) {
          newlySucc.add(user);
        } else {
          stillFail.add(user);
        }
      }

      final currentResult = results.isNotEmpty ? results.first : null;

      if (targetAccounts != null) {
        // 定向补签模式：合并成功名单，更新待补签名单
        final updatedSucc = List<User>.from(_succeededAccounts);
        for (final u in newlySucc) {
          if (!updatedSucc.any((existing) => existing.uid == u.uid)) {
            updatedSucc.add(u);
          }
        }
        setState(() {
          _isSubmitting = false;
          _signState = _SignState.submitted;
          _checkInTime = DateTime.now();
          _isLate = currentResult?.isLate ?? _isLate;
          if (currentResult?.address != null && currentResult!.address!.isNotEmpty) {
            _address = currentResult.address;
          }
          if (currentResult?.distanceM != null) {
            _distanceM = currentResult!.distanceM;
          }
          _succeededAccounts = updatedSucc;
          _failedAccounts = stillFail;
        });

        if (newlySucc.isNotEmpty) {
          widget.onCheckInSuccess?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('成功补签 ${newlySucc.length} 个账号！'),
              backgroundColor: const Color(0xFF34C759),
            ),
          );
        } else {
          final errorMsg = currentResult?.message.isNotEmpty == true
              ? currentResult!.message
              : '补签未成功，请检查定位或重试';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: const Color(0xFFFF3B30),
            ),
          );
        }
      } else {
        // 全量提交模式
        final successCount = newlySucc.length;
        if (successCount > 0) {
          setState(() {
            _isSubmitting = false;
            _signState = _SignState.submitted;
            _checkInTime = DateTime.now();
            _isLate = currentResult?.isLate ?? false;
            if (currentResult?.address != null && currentResult!.address!.isNotEmpty) {
              _address = currentResult.address;
            }
            if (currentResult?.distanceM != null) {
              _distanceM = currentResult!.distanceM;
            }
            _succeededAccounts = newlySucc;
            _failedAccounts = stillFail;
          });
          widget.onCheckInSuccess?.call();
          final label = (currentResult?.isLate == true) ? '迟到签到' : '位置签到';
          final multiTag = accountsToSubmit.length > 1 ? ' ($successCount/${accountsToSubmit.length} 账号成功)' : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$label成功！$multiTag'),
              backgroundColor: const Color(0xFF34C759),
            ),
          );
        } else {
          setState(() {
            _isSubmitting = false;
            _failedAccounts = accountsToSubmit;
          });
          final errorMsg = currentResult?.message.isNotEmpty == true
              ? currentResult!.message
              : '签到失败，请重试';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: const Color(0xFFFF3B30),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('提交位置打卡异常: $e');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('提交异常: $e'),
          backgroundColor: const Color(0xFFFF3B30),
        ),
      );
    }
  }

  String _formatTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }

  String _formatRemaining(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          '位置打卡',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1C1C1E),
        elevation: 0.5,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                backgroundColor: const Color(0xFFF0FDF4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFB7EB8F), width: 0.8),
                ),
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: Color(0xFF16A34A)),
                    )
                  : const Icon(Icons.replay_rounded, size: 15, color: Color(0xFF16A34A)),
              label: const Text(
                '补签',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF16A34A)),
              ),
              onPressed: (_isLoading || _isSubmitting)
                  ? null
                  : () async {
                      await _locate(forceCalibrate: true);
                      final targets = _failedAccounts.isNotEmpty ? _failedAccounts : null;
                      await _submit(targetAccounts: targets);
                    },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新探测定位',
            onPressed: _isLoading ? null : () => _locate(forceCalibrate: true),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在探测课堂签到范围与配置...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : _errorMessage != null
              ? _buildErrorView()
              : _signState == _SignState.submitted
                  ? _buildSuccessView()
                  : _signState == _SignState.ended
                      ? _buildEndedView()
                      : _buildActiveSignInView(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Color(0xFFFF9500)),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? '获取签到配置异常',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Color(0xFF1C1C1E)),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadEligibility,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 签到成功结算视图 (对标官方 _LocationCheckInSuccessView)
  Widget _buildSuccessView() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 40),
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isLate ? const Color(0xFFFF9500) : const Color(0xFF34C759),
                boxShadow: [
                  BoxShadow(
                    color: (_isLate ? const Color(0xFFFF9500) : const Color(0xFF34C759))
                        .withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check,
                size: 52,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isLate ? '迟到签到已完成' : '签到成功！',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _succeededAccounts.length > 1
                  ? '已成功为 ${_succeededAccounts.length} 个账号在指定范围内完成打卡'
                  : (_isLate ? '您已在迟到宽限时段完成签到' : '您已准时在教师指定范围内完成打卡'),
              style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
            ),
            const SizedBox(height: 36),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildResultRow('签到状态', _isLate ? '迟到签到' : '正常出勤',
                      color: _isLate ? const Color(0xFFFF9500) : const Color(0xFF34C759)),
                  const Divider(height: 24),
                  _buildResultRow('签到时间', _checkInTime != null ? _formatTime(_checkInTime!) : '--'),
                  const Divider(height: 24),
                  _buildResultRow('签到地点', _address ?? '教室内已定位'),
                  if (_distanceM != null) ...[
                    const Divider(height: 24),
                    _buildResultRow('物理偏差', '${_distanceM!.toStringAsFixed(1)} 米 (允许 ${_radiusM.toInt()} 米)'),
                  ],
                  if (_succeededAccounts.isNotEmpty) ...[
                    const Divider(height: 24),
                    _buildAccountsSection(
                      title: '成功账号',
                      accounts: _succeededAccounts,
                      isSuccess: true,
                    ),
                  ],
                  if (_failedAccounts.isNotEmpty) ...[
                    const Divider(height: 24),
                    _buildAccountsSection(
                      title: '未签账号',
                      accounts: _failedAccounts,
                      isSuccess: false,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 36),
            if (_failedAccounts.isNotEmpty) ...[
              // 有未签账号时：主按钮为【为未签账号补签】，次按钮为【返回课堂】
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => _submit(targetAccounts: _failedAccounts),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.replay_rounded, size: 20),
                  label: Text(
                    _isSubmitting ? '正在补签中...' : '为未签账号补签 (${_failedAccounts.length}人)',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9500),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1C1C1E),
                    side: const BorderSide(color: Color(0xFFD1D1D6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: const Text('返回课堂', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ] else ...[
              // 全员出勤时：主按钮为【返回课堂】，次按钮为【重新打卡 / 补签】
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: const Text('返回课堂', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          await _locate(forceCalibrate: true);
                          await _submit();
                        },
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_isSubmitting ? '正在重新打卡...' : '重新定位打卡 / 补签'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF007AFF),
                    side: const BorderSide(color: Color(0xFF007AFF), width: 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 签到截止视图 (对标官方 _LocationCheckInEndedView)
  Widget _buildEndedView() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 60),
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF8E8E93),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8E8E93).withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.timer_off_outlined,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '签到已结束',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '本堂课位置签到时间已截止，无法继续打卡',
              style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
            ),
            if (_succeededAccounts.isNotEmpty || _failedAccounts.isNotEmpty) ...[
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildResultRow('活动状态', '签到已截止', color: const Color(0xFF8E8E93)),
                    if (_succeededAccounts.isNotEmpty) ...[
                      const Divider(height: 24),
                      _buildAccountsSection(
                        title: '已签账号',
                        accounts: _succeededAccounts,
                        isSuccess: true,
                      ),
                    ],
                    if (_failedAccounts.isNotEmpty) ...[
                      const Divider(height: 24),
                      _buildAccountsSection(
                        title: '未签账号',
                        accounts: _failedAccounts,
                        isSuccess: false,
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        await _locate(forceCalibrate: true);
                        final targets = _failedAccounts.isNotEmpty ? _failedAccounts : null;
                        await _submit(targetAccounts: targets);
                      },
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.replay_rounded, size: 20),
                label: Text(
                  _isSubmitting ? '正在尝试补签...' : '尝试补签打卡',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9500),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1C1C1E),
                  side: const BorderSide(color: Color(0xFFD1D1D6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: const Text('返回课堂', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 课中打卡进行时主视图 (对标官方 _LocationSignInView)
  Widget _buildActiveSignInView() {
    final bool inRange = _signState == _SignState.inRangeOnTime || _signState == _SignState.inRangeLate;
    final bool isLateStage = _signState == _SignState.inRangeLate;

    return Column(
      children: [
        // 顶部脉冲雷达动态水波纹区域
        Expanded(
          flex: 5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 雷达水波纹
              AnimatedBuilder(
                animation: _rippleAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(260, 260),
                    painter: _SignInRipplePainter(
                      progress: _rippleAnimation.value,
                      color: inRange
                          ? (isLateStage ? const Color(0xFFFF9500) : const Color(0xFF34C759))
                          : const Color(0xFFFF3B30),
                    ),
                  );
                },
              ),
              // 中心定位徽章图标
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: inRange
                        ? (isLateStage
                            ? [const Color(0xFFFFCC00), const Color(0xFFFF9500)]
                            : [const Color(0xFF34C759), const Color(0xFF30D158)])
                        : [const Color(0xFFFF5E3A), const Color(0xFFFF3B30)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (inRange
                              ? (isLateStage ? const Color(0xFFFF9500) : const Color(0xFF34C759))
                              : const Color(0xFFFF3B30))
                          .withOpacity(0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_on,
                  size: 42,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),

        // 底部打卡详情卡片 (对标官方 _SignInBottomCard)
        Expanded(
          flex: 6,
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 16,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. 倒计时徽标行 (对标官方 _SignInCountdownSection)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time_rounded,
                                    size: 18,
                                    color: isLateStage ? const Color(0xFFFF9500) : const Color(0xFF007AFF),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _remainingSeconds > 0
                                        ? '签到倒计时: ${_formatRemaining(_remainingSeconds)}'
                                        : '签到已截止',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isLateStage ? const Color(0xFFFF9500) : const Color(0xFF007AFF),
                                    ),
                                  ),
                                ],
                              ),
                              if (isLateStage)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF4E5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    '迟到阶段',
                                    style: TextStyle(
                                      color: Color(0xFFFF9500),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // 2. 状态提示行 (对标官方 _SignInStatusRow)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: inRange ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: inRange ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  inRange ? Icons.check_circle : Icons.warning_rounded,
                                  size: 20,
                                  color: inRange ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    inRange
                                        ? '已进入签到范围 (偏差 ${_distanceM?.toStringAsFixed(1) ?? '0'}m / 半径 ${_radiusM.toInt()}m)'
                                        : '未在签到范围内 (偏差 ${_distanceM?.toStringAsFixed(1) ?? '0'}m / 半径 ${_radiusM.toInt()}m)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: inRange ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 3. 当前位置与逆地理编码栏 (对标官方 _SignInLocationBar)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.place_outlined, size: 20, color: Color(0xFF6B7280)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _address ?? '正在解析教室附近高保真地理位置...',
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _locate(forceCalibrate: true),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    child: Text(
                                      '重新定位',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF007AFF),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_studentCoord != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                              child: Text(
                                '微抖动火星坐标: ${_studentCoord!.toParamString()}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                              ),
                            ),

                          // 4. 超范围预警卡 (对标官方 _SignInWarningCard)
                          if (!inRange) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: Color(0xFFD97706)),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '提示：点击【智能校准至教室】可自动修正微抖动坐标至围栏内部。',
                                      style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 5. 底部打卡按钮 (对标官方 _SignInButton)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSubmitting
                          ? null
                          : inRange
                              ? _submit
                              : () async {
                                  // 超范围时一键智能校准并打卡
                                  await _locate(forceCalibrate: true);
                                  await _submit();
                                },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: inRange
                            ? (isLateStage ? const Color(0xFFFF9500) : const Color(0xFF007AFF))
                            : const Color(0xFF34C759),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              inRange ? '立即签到' : '智能校准至教室并签到',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultRow(String label, String value, {Color? color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color ?? const Color(0xFF1C1C1E),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountsSection({
    required String title,
    required List<User> accounts,
    required bool isSuccess,
  }) {
    if (accounts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF8E8E93),
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSuccess ? const Color(0xFFE8F9EE) : const Color(0xFFFEECEB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${accounts.length}人',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSuccess ? const Color(0xFF34C759) : const Color(0xFFFF3B30),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: accounts.map((user) {
              final trimmedName = user.name.trim();
              final trimmedRemark = user.remark.trim();
              final bool hasDistinctRemark =
                  trimmedRemark.isNotEmpty && trimmedRemark != trimmedName;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSuccess ? const Color(0xFFF6FBF7) : const Color(0xFFFFF7F7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSuccess ? const Color(0xFFB7EB8F) : const Color(0xFFFFA39E),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSuccess ? const Color(0xFF52C41A) : const Color(0xFFFF4D4F),
                      ),
                      child: Icon(
                        isSuccess ? Icons.check : Icons.close,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      trimmedName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF262626),
                      ),
                    ),
                    if (hasDistinctRemark) ...[
                      const SizedBox(width: 3),
                      Text(
                        '($trimmedRemark)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8C8C8C),
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// 中心雷达脉冲水波纹动效绘制器（对标官方 _SignInRipplePainter）
class _SignInRipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  _SignInRipplePainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const double maxRadius = 130.0;
    const double minRadius = 45.0;

    for (int i = 0; i < 3; i++) {
      final double waveProgress = (progress + i / 3.0) % 1.0;
      final double currentRadius = minRadius + (maxRadius - minRadius) * waveProgress;
      final double opacity = (1.0 - waveProgress) * 0.45;

      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(center, currentRadius, paint);

      final strokePaint = Paint()
        ..color = color.withOpacity(opacity * 1.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      canvas.drawCircle(center, currentRadius, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignInRipplePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
