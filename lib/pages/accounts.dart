import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'dart:async';

import '../session/account.dart';
import '../models/user.dart';
import '../platform.dart';
import '../services/cloud_sync_service.dart';
import '../utils/app_logger.dart';
import '../api/login.dart';
import 'widget/avatar.dart';
import 'login.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> with TickerProviderStateMixin {
  List<User> _accounts = [];
  final Set<String> _selectedAccounts = <String>{};
  bool _isMultiSelectMode = false;
  String? _currentAccountId;
  StreamSubscription? _accountChangeSubscription;
  final CloudSyncService _cloudSyncService = CloudSyncService();

  @override
  void initState() {
    super.initState();
    _loadAccounts();

    // 监听账户变更事件
    _accountChangeSubscription =
        AccountChangeNotifier().accountChanges.listen((_) {
          if (mounted) {
            _loadAccounts();
          }
        });
  }

  @override
  void dispose() {
    _accountChangeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _accounts = AccountManager.allAccounts;
      _currentAccountId = AccountManager.currentSessionId;
    });
    _refreshMissingAvatars();
  }

  /// 异步拉取无头像账号的个人资料，确保多账号头像全部正常显示
  Future<void> _refreshMissingAvatars() async {
    bool hasUpdate = false;
    for (var user in _accounts) {
      if (user.avatar.isEmpty && user.status && PlatformManager().isRainClassroom) {
        try {
          final userInfo = await RCLoginApi(user).getUserInfo();
          if (userInfo != null && userInfo.avatar.isNotEmpty) {
            final updatedUser = User(
              name: userInfo.name.isNotEmpty ? userInfo.name : user.name,
              avatar: userInfo.avatar,
              phone: userInfo.phone.isNotEmpty ? userInfo.phone : user.phone,
              uid: user.uid,
              school: userInfo.school.isNotEmpty ? userInfo.school : user.school,
              platform: user.platform,
              remark: user.remark,
              deviceInfo: user.deviceInfo ?? userInfo.deviceInfo,
              status: true,
            );
            await AccountManager.addAccount(updatedUser, autoSync: false);
            hasUpdate = true;
          }
        } catch (_) {}
      }
    }
    if (hasUpdate && mounted) {
      setState(() {
        _accounts = AccountManager.allAccounts;
      });
    }
  }

  bool _isCheckingValidity = false;

  /// 手动检测所有账号有效性
  Future<void> _checkValidity() async {
    if (_isCheckingValidity) return;
    setState(() {
      _isCheckingValidity = true;
    });

    final result = await AccountManager.checkAllAccountsValidity();
    if (mounted) {
      setState(() {
        _accounts = AccountManager.allAccounts;
        _isCheckingValidity = false;
      });

      if (result.hasInvalid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '检测到 ${result.invalidAccounts.length} 个账号登录已失效，请重新登录',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (result.hasNetworkError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('网络连接异常，未能完成账号校验'),
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF16A34A),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  '所有账号均处于有效状态 (共 ${result.totalCount} 个)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _reLogin(User user) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedAccounts.contains(userId)) {
        _selectedAccounts.remove(userId);
      } else {
        _selectedAccounts.add(userId);
      }
      if (_selectedAccounts.isEmpty) _isMultiSelectMode = false;
    });
  }

  void _toggleMultiSelect() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) _selectedAccounts.clear();
    });
  }

  Future<void> _deleteSelectedAccounts() async {
    if (_selectedAccounts.isNotEmpty) {
      await AccountManager.removeAccounts(_selectedAccounts.toList());
      await _loadAccounts();
      _toggleMultiSelect();
    }
  }

  Future<void> _switchToAccount(User user) async {
    if (user.uid == _currentAccountId) {
      return;
    }
    await AccountManager.setCurrentSession(user.uid);
  }

  Future<void> _showKeyDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final savedKey = await _cloudSyncService.getSavedKey() ?? '';
    final controller = TextEditingController(text: savedKey);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('云端同步密钥'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请输入群组/租户同步密钥（Key），用于多设备拉取或备份账号凭据。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '同步密钥 (API Key)',
                hintText: '如: my_secret_sync_key',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final key = controller.text.trim();
              if (key.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('密钥不能为空')),
                );
                return;
              }
              Navigator.pop(dialogContext);
              messenger.showSnackBar(
                const SnackBar(content: Text('正在验证密钥...')),
              );
              final res = await _cloudSyncService.verifyAndSaveKey(key);
              if (!mounted) return;
              if (res['success'] == true) {
                messenger.showSnackBar(
                  SnackBar(content: Text('密钥验证成功！群组：${res['remark']}')),
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(content: Text('验证失败：${res['msg']}')),
                );
              }
            },
            child: const Text('验证并保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLogDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final logDir = await AppLogger().getLogDirectoryPath();
    List<String> logs = await AppLogger().getRecentLogs(maxLines: 200);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.article_outlined, size: 22),
                SizedBox(width: 8),
                Text('运行与错误日志', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '日志目录 (APP私有路径):',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: logDir));
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('已复制日志路径到剪贴板')),
                                );
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text('复制路径', style: TextStyle(fontSize: 12, color: Colors.blue)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          logDir,
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '电脑拉取命令: adb pull <上面路径> .',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('最新日志 (${logs.length} 行):', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      TextButton.icon(
                        onPressed: () async {
                          final refreshed = await AppLogger().getRecentLogs(maxLines: 200);
                          setDialogState(() {
                            logs = refreshed;
                          });
                        },
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('刷新', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 260,
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: logs.isEmpty
                        ? const Center(
                            child: Text('暂无日志记录', style: TextStyle(color: Colors.white54, fontSize: 12)),
                          )
                        : SingleChildScrollView(
                            reverse: true,
                            child: SelectableText(
                              logs.join('\n'),
                              style: const TextStyle(
                                color: Color(0xFFD4D4D4),
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await AppLogger().clearLogs();
                  setDialogState(() {
                    logs = [];
                  });
                  messenger.showSnackBar(
                    const SnackBar(content: Text('已清空所有本地日志')),
                  );
                },
                child: const Text('清空日志', style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                onPressed: logs.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: logs.join('\n')));
                        messenger.showSnackBar(
                          const SnackBar(content: Text('已复制全部日志到剪贴板')),
                        );
                      },
                child: const Text('复制全部'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleCloudPull() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('正在从云端拉取账号...')),
    );
    final res = await _cloudSyncService.downloadAndApplyAccounts();
    if (!mounted) return;
    if (res['success'] == true) {
      await _loadAccounts();
      messenger.showSnackBar(
        SnackBar(content: Text('成功拉取并同步 ${res['count']} 个账号！')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('拉取失败：${res['msg']}')),
      );
    }
  }

  Future<void> _handleCloudPush() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('正在备份本地账号到云端...')),
    );
    final res = await _cloudSyncService.uploadLocalAccounts();
    if (!mounted) return;
    if (res['success'] == true) {
      messenger.showSnackBar(
        SnackBar(content: Text('成功备份 ${res['count']} 个账号到云端！')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('备份失败：${res['msg']}')),
      );
    }
  }

  Future<void> _navigateToPasswordLogin() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage(initialLoginType: 'password')),
    );
    if (result == true) {
      await _loadAccounts();
    }
  }

  Future<void> _navigateToCaptchaLogin() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage(initialLoginType: 'captcha')),
    );
    if (result == true) {
      await _loadAccounts();
    }
  }

  Future<void> _showQRCodeLoginDialog() async {
    final qrState = QRCodeLoginState();
    final qrRemarkController = TextEditingController();

    if (!await qrState.initialize()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取二维码失败')),
        );
      }
      qrState.dispose();
      return;
    }

    qrState.startPolling((bool success) async {
      if (success && await handleLoginSuccess(context, remark: qrRemarkController.text.trim()) && mounted) {
        Navigator.pop(context, true);
        await _loadAccounts();
      }
      qrState.dispose();
    });

    if (!mounted) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            qrState.onRefresh = () {
              setState(() {});
            };
            
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (bool didPop, Object? result) {
                if (didPop) {
                  qrState.isLoginActive = false;
                  qrState.dispose();
                }
              },
              child: AlertDialog(
                title: const Text('二维码登录'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.1),
                              spreadRadius: 2,
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: qrState.qrImageUrl != null
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            qrState.qrImageUrl!,
                            fit: BoxFit.contain,
                          ),
                        )
                            : qrState.isLoading
                            ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 8),
                              Text('生成中...', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        )
                            : const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 48, color: Colors.grey),
                              SizedBox(height: 8),
                              Text('二维码加载失败', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        PlatformManager().isChaoxing ?
                        '使用学习通APP扫码登录' : '使用微信扫码登录',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '二维码失效时会自动刷新',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: qrRemarkController,
                        decoration: const InputDecoration(
                          labelText: '预设账号备注 (选填)',
                          hintText: '如：大号、学委',
                          prefixIcon: Icon(Icons.edit_note, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    child: const Text('取消'),
                    onPressed: () {
                      qrState.isLoginActive = false;
                      qrState.dispose();
                      Navigator.pop(context);
                    }
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    qrState.dispose();
  }

  Future<void> _showEditRemarkDialog(User user) async {
    final controller = TextEditingController(text: user.remark);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('修改备注 - ${user.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '账号备注',
            hintText: '如：大号、学委、张三',
            prefixIcon: Icon(Icons.edit_note),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final newRemark = controller.text.trim();
              Navigator.pop(dialogContext);
              await AccountManager.updateAccountRemark(user.uid, newRemark);
              await _loadAccounts();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('备注已更新，已触发云端同步')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle(User user, bool isCurrentAccount) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Text(
          user.name,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: user.status ? null : const Color(0xFFDC2626),
          ),
        ),
        if (user.remark.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              user.remark,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if (isCurrentAccount)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('当前', style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        // 账号有效性状态徽章
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: user.status ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: user.status ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                user.status ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 11,
                color: user.status ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 3),
              Text(
                user.status ? '有效' : '已失效',
                style: TextStyle(
                  color: user.status ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListItemContent(
      BuildContext context, User user, bool isSelected, bool isCurrentAccount) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: AvatarWidget(key: ValueKey(user.avatar), imageUrl: user.avatar),
      title: _buildTitle(user, isCurrentAccount),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text('ID: ${user.uid}\n手机号: ${user.phone}'),
          if (!user.status)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                onTap: () => _reLogin(user),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFECACA), width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFDC2626)),
                      SizedBox(width: 4),
                      Text(
                        '登录凭证已失效，点击重新登录',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Color(0xFFDC2626)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.edit_note, color: Colors.grey),
              tooltip: '修改备注',
              onPressed: () => _showEditRemarkDialog(user),
            ),
          Visibility(
            visible: _isMultiSelectMode,
            child: Checkbox(
              value: isSelected,
              onChanged: (bool? value) {
                if (value != null) _toggleSelection(user.uid);
              },
            ),
          ),
        ],
      ),
      onTap: _isMultiSelectMode ? null : () => _switchToAccount(user),
      onLongPress: () {
        _toggleMultiSelect();
        _toggleSelection(user.uid);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSelectedAccounts,
              tooltip: '删除选中账号',
            ),
          IconButton(
            icon: _isCheckingValidity
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.verified_user_outlined),
            tooltip: '检测账号有效性',
            onPressed: _isCheckingValidity ? null : _checkValidity,
          ),
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: '运行与错误日志',
            onPressed: _showLogDialog,
          ),
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined),
            tooltip: '云端同步密钥',
            onPressed: _showKeyDialog,
          ),
          StatefulBuilder(
            builder: (context, setState) {
              // 服务器类型与颜色
              const serverColors = {
                RainClassroomServerType.yuketang: Color(0xFF5096F5),
                RainClassroomServerType.pro: Color(0xFF7B3BB5),
                RainClassroomServerType.changjiang: Color(0xFFC21F30),
                RainClassroomServerType.huanghe: Color(0xFFB57232)
              };
              
              final serverColor = serverColors[PlatformManager().currentServer];
              return PopupMenuButton<RainClassroomServerType>(
                icon: Icon(Icons.dns, color: serverColor),
                tooltip: '切换服务器',
                onSelected: (RainClassroomServerType server) async {
                  await PlatformManager().setServer(server);
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem<RainClassroomServerType>(
                    enabled: true,
                    child: StatefulBuilder(
                      builder: (BuildContext context, StateSetter setPopupState) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RadioGroup<RainClassroomServerType>(
                              groupValue: PlatformManager().currentServer,
                              onChanged: (RainClassroomServerType? value) async {
                                if (value != null) {
                                  await PlatformManager().setServer(value);
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  // 延迟执行以确保弹窗关闭后再刷新
                                  Future.microtask(() => setState(() {}));
                                }
                              },
                              child: Column(
                                children: [
                                  RadioListTile<RainClassroomServerType>(
                                    title: const Text('雨课堂'),
                                    value: RainClassroomServerType.yuketang,
                                    dense: true
                                  ),
                                  RadioListTile<RainClassroomServerType>(
                                    title: const Text('荷塘 · 雨课堂'),
                                    value: RainClassroomServerType.pro,
                                    dense: true
                                  ),
                                  RadioListTile<RainClassroomServerType>(
                                    title: const Text('长江 · 雨课堂'),
                                    value: RainClassroomServerType.changjiang,
                                    dense: true
                                  ),
                                  RadioListTile<RainClassroomServerType>(
                                    title: const Text('黄河 · 雨课堂'),
                                    value: RainClassroomServerType.huanghe,
                                    dense: true
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 账号列表顶部的云端操作大按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _handleCloudPull,
                    icon: const Icon(Icons.cloud_download_outlined, size: 20),
                    label: const Text(
                      '从云端拉取',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _handleCloudPush,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                    label: const Text(
                      '备份至云端',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _accounts.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('暂无账号', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('点击右下角添加账号，或点击上方拉取云端账号', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
                : RefreshIndicator(
                    onRefresh: _checkValidity,
                    child: ListView.builder(
                      itemCount: _accounts.length,
                      itemBuilder: (context, index) {
                        final user = _accounts[index];
                        final isSelected = _selectedAccounts.contains(user.uid);
                        final isCurrent = user.uid == _currentAccountId;
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: isCurrent ? Theme.of(context).colorScheme.primaryContainer : null,
                          child: _buildListItemContent(context, user, isSelected, isCurrent),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        spacing: 5,
        spaceBetweenChildren: 2,
        overlayColor: Colors.transparent,
        overlayOpacity: 0.3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        children: [
          SpeedDialChild(
            child: const Icon(Icons.qr_code),
            label: '二维码登录',
            onTap: _showQRCodeLoginDialog,
          ),
          SpeedDialChild(
            child: const Icon(Icons.sms),
            label: '验证码登录',
            onTap: _navigateToCaptchaLogin,
          ),
          SpeedDialChild(
            child: const Icon(Icons.password),
            label: '密码登录',
            onTap: _navigateToPasswordLogin,
          ),
        ],
      ),
    );
  }
}
