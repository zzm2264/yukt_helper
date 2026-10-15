// ignore_for_file: deprecated_member_use
import 'dart:ui';
import 'package:flutter/material.dart';

/// 日志类型与配色
enum TerminalLogType {
  info, // 橙色/提示
  good, // 翠绿/成功
  bad,  // 赤红/失败
}

/// 单行日志项实体
class TerminalLogItem {
  final String time;
  final String tag;
  final String text;
  final TerminalLogType type;

  TerminalLogItem({
    required this.time,
    required this.tag,
    required this.text,
    required this.type,
  });

  Color get tagColor {
    switch (type) {
      case TerminalLogType.info:
        return const Color(0xFFFF9F0A); // Apple Orange
      case TerminalLogType.good:
        return const Color(0xFF30D158); // Apple Green
      case TerminalLogType.bad:
        return const Color(0xFFFF453A); // Apple Red
    }
  }

  Color get textColor {
    switch (type) {
      case TerminalLogType.info:
        return const Color(0xFFE5E5EA);
      case TerminalLogType.good:
        return const Color(0xFF30D158);
      case TerminalLogType.bad:
        return const Color(0xFFFF453A);
    }
  }
}

/// 终端弹窗控制器
class TerminalConsoleController extends ChangeNotifier {
  final List<TerminalLogItem> logs = [];
  String statusText = '准备就绪...';
  Color statusColor = const Color(0xFF30D158);
  bool isRunning = true;

  // 底部补签/重试主按钮动作
  String? actionButtonText;
  VoidCallback? onActionButtonPressed;
  IconData? actionButtonIcon;

  // 底部次要操作动作（例如“不管了，直接进入课堂”）
  String? secondaryActionButtonText;
  VoidCallback? onSecondaryActionButtonPressed;

  /// 添加一条日志并通知视窗滚动
  void addLog(String tag, String text, {TerminalLogType type = TerminalLogType.info}) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    logs.add(TerminalLogItem(
      time: timeStr,
      tag: tag,
      text: text,
      type: type,
    ));
    notifyListeners();
  }

  /// 更新顶部状态栏文案与颜色
  void updateStatus(String status, {Color? color}) {
    statusText = status;
    if (color != null) statusColor = color;
    notifyListeners();
  }

  /// 配置底部主操作按钮及可选的次要操作按钮
  void setAction({
    String? text,
    VoidCallback? onPressed,
    IconData? icon,
    String? secondaryText,
    VoidCallback? onSecondaryPressed,
  }) {
    actionButtonText = text;
    onActionButtonPressed = onPressed;
    actionButtonIcon = icon;
    secondaryActionButtonText = secondaryText;
    onSecondaryActionButtonPressed = onSecondaryPressed;
    notifyListeners();
  }

  /// 标记任务结束
  void setFinished({bool hasFailures = false}) {
    isRunning = false;
    notifyListeners();
  }
}

/// 拟真 macOS 终端风格高颜值执行进度与日志输出控制台弹窗
class TerminalConsoleModal extends StatefulWidget {
  final TerminalConsoleController controller;
  final VoidCallback? onClose;

  const TerminalConsoleModal({
    super.key,
    required this.controller,
    this.onClose,
  });

  /// 呼出终端控制台静态方法（全屏磨砂毛玻璃）
  static Future<T?> show<T>(
    BuildContext context, {
    required TerminalConsoleController controller,
    VoidCallback? onClose,
    bool barrierDismissible = false,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'TerminalModal',
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) {
        return TerminalConsoleModal(
          controller: controller,
          onClose: onClose,
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 14 * curved.value,
            sigmaY: 14 * curved.value,
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  State<TerminalConsoleModal> createState() => _TerminalConsoleModalState();
}

class _TerminalConsoleModalState extends State<TerminalConsoleModal> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    setState(() {});
    // 新增日志时自动滚到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 400,
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E), // Apple Dark Shell Background
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 50,
                spreadRadius: 0,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 顶部 Mac 交通灯与等宽标题栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    // 红黄绿三色 Mac 圆点
                    _buildTrafficLight(const Color(0xFFFF5F56)),
                    const SizedBox(width: 7),
                    _buildTrafficLight(const Color(0xFFFFBD2E)),
                    const SizedBox(width: 7),
                    _buildTrafficLight(const Color(0xFF27C93F)),
                    const SizedBox(width: 12),
                    // 终端等宽标题
                    const Expanded(
                      child: Center(
                        child: Text(
                          'terminal - course_helper',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 47), // 保持标题居中对称
                  ],
                ),
              ),

              // 2. 内部黑屏荧幕 (shell-body)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF000000), // 纯黑
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.06),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顶部状态栏 (>光标 + 整体状态)
                    Row(
                      children: [
                        const Text(
                          '> ',
                          style: TextStyle(
                            color: Color(0xFF30D158),
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            c.statusText,
                            style: TextStyle(
                              color: c.statusColor,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (c.isRunning)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF30D158)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.08),
                    ),
                    const SizedBox(height: 8),

                    // 日志滚动视窗
                    SizedBox(
                      height: 230,
                      child: c.logs.isEmpty
                          ? const Center(
                              child: Text(
                                '等待日志输出...',
                                style: TextStyle(
                                  color: Color(0xFF636366),
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              physics: const ClampingScrollPhysics(),
                              itemCount: c.logs.length,
                              itemBuilder: (context, index) {
                                final log = c.logs[index];
                                return _buildLogRow(log);
                              },
                            ),
                    ),
                  ],
                ),
              ),

              // 3. 底部操作栏 (shell-footer)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    // 次要按钮：若提供了 secondaryActionButtonText 则显示该动作，否则显示默认的“关闭”
                    Expanded(
                      flex: c.secondaryActionButtonText != null ? 3 : 1,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                            width: 1,
                          ),
                        ),
                        child: TextButton(
                          onPressed: () {
                            if (c.onSecondaryActionButtonPressed != null) {
                              c.onSecondaryActionButtonPressed!();
                            } else {
                              widget.onClose?.call();
                              Navigator.of(context).pop();
                            }
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            c.secondaryActionButtonText ?? '关闭',
                            style: const TextStyle(
                              color: Color(0xFFE5E5EA),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),

                    // 若提供了高亮主按钮（例如“重新扫码补签”或“进入课堂”）
                    if (c.actionButtonText != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        flex: c.secondaryActionButtonText != null ? 3 : 2,
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0A84FF), Color(0xFF0071E3)], // Apple Blue
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0A84FF).withOpacity(0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextButton(
                            onPressed: c.onActionButtonPressed,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  c.actionButtonIcon ??
                                      (c.actionButtonText?.contains('扫码') == true
                                          ? Icons.qr_code_scanner
                                          : Icons.arrow_forward_rounded),
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    c.actionButtonText!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 拟真 Mac 交通灯小圆点
  Widget _buildTrafficLight(Color color) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.black.withOpacity(0.18),
          width: 0.5,
        ),
      ),
    );
  }

  /// 单行横向 Flex 日志行 (clean-log-row)
  Widget _buildLogRow(TerminalLogItem log) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. time
          Text(
            log.time,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),

          // 2. tag
          Text(
            '[${log.tag}]',
            style: TextStyle(
              color: log.tagColor,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),

          // 3. msg (超出单行省略)
          Expanded(
            child: Text(
              log.text,
              style: TextStyle(
                color: log.textColor,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
