// ignore_for_file: constant_identifier_names, deprecated_member_use
import 'package:flutter/material.dart';

/// 课中位置签到状态枚举（严格对标官方 package:rain 定义）
enum LocationSignInState {
  location_checkin_need_sign,         // 老师已开启签到，当前未签到（可打卡）
  location_checkin_signed,            // 正常已签到
  location_checkin_signed_late,       // 迟到签到已完成
  location_checkin_ended_unsigned,    // 签到已截止，且未签到（缺勤）
  location_checkin_no_active_session, // 当前课堂无签到活动（返回 SizedBox.shrink()）
}

/// 课中位置签到顶部常驻通知条组件（严格对标官方 LocationSignInWidget）
class LocationSignInWidget extends StatelessWidget {
  final LocationSignInState state;
  final VoidCallback? onTap;

  const LocationSignInWidget({
    super.key,
    required this.state,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 若当前课堂无活跃位置签到活动，返回 SizedBox.shrink() 完全折叠不占空间
    if (state == LocationSignInState.location_checkin_no_active_session) {
      return const SizedBox.shrink();
    }

    final style = _styleFor(state);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      height: 36.0,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: style.gradientColors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(8.0),
        boxShadow: [
          BoxShadow(
            color: style.gradientColors.first.withOpacity(0.35),
            blurRadius: 5.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Icon(
                  style.icon,
                  size: 18.0,
                  color: Colors.white,
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    style.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (style.showArrow)
                  const Icon(
                    Icons.chevron_right,
                    size: 20.0,
                    color: Colors.white,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static _SignInStyle _styleFor(LocationSignInState state) {
    switch (state) {
      case LocationSignInState.location_checkin_need_sign:
        return const _SignInStyle(
          gradientColors: [Color(0xFFFF9500), Color(0xFFFF5E3A)],
          icon: Icons.location_on,
          text: '当前未签到，请点击进行签到',
          showArrow: true,
        );
      case LocationSignInState.location_checkin_signed:
        return const _SignInStyle(
          gradientColors: [Color(0xFF34C759), Color(0xFF30D158)],
          icon: Icons.check_circle_outline,
          text: '已签到',
          showArrow: true,
        );
      case LocationSignInState.location_checkin_signed_late:
        return const _SignInStyle(
          gradientColors: [Color(0xFFFFCC00), Color(0xFFFF9500)],
          icon: Icons.access_time,
          text: '迟到签到',
          showArrow: true,
        );
      case LocationSignInState.location_checkin_ended_unsigned:
        return const _SignInStyle(
          gradientColors: [Color(0xFF8E8E93), Color(0xFF636366)],
          icon: Icons.timer_off_outlined,
          text: '签到已结束，未签到',
          showArrow: true,
        );
      case LocationSignInState.location_checkin_no_active_session:
        return const _SignInStyle(
          gradientColors: [Colors.transparent, Colors.transparent],
          icon: Icons.info_outline,
          text: '',
          showArrow: false,
        );
    }
  }
}

class _SignInStyle {
  final List<Color> gradientColors;
  final IconData icon;
  final String text;
  final bool showArrow;

  const _SignInStyle({
    required this.gradientColors,
    required this.icon,
    required this.text,
    required this.showArrow,
  });
}
