import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:course_helper/pages/widget/location_sign_in_widget.dart';
import 'package:course_helper/pages/widget/terminal_console_modal.dart';
import 'package:course_helper/pages/location_check_in_page.dart';

void main() {
  group('LocationSignInWidget Widget Tests', () {
    testWidgets('renders need_sign state with correct gradient and text', (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationSignInWidget(
              state: LocationSignInState.location_checkin_need_sign,
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('当前未签到，请点击进行签到'), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.tap(find.byType(LocationSignInWidget));
      expect(tapped, isTrue);
    });

    testWidgets('renders signed state with check icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocationSignInWidget(
              state: LocationSignInState.location_checkin_signed,
            ),
          ),
        ),
      );

      expect(find.text('已签到'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('renders signed_late state with access_time icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocationSignInWidget(
              state: LocationSignInState.location_checkin_signed_late,
            ),
          ),
        ),
      );

      expect(find.text('迟到签到'), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('renders ended_unsigned state with timer_off icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocationSignInWidget(
              state: LocationSignInState.location_checkin_ended_unsigned,
            ),
          ),
        ),
      );

      expect(find.text('签到已结束，未签到'), findsOneWidget);
      expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink() when no_active_session (zero height)', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocationSignInWidget(
              state: LocationSignInState.location_checkin_no_active_session,
            ),
          ),
        ),
      );

      expect(find.text('当前未签到，请点击进行签到'), findsNothing);
      expect(find.text('已签到'), findsNothing);
      final sizedBoxFinder = find.byType(SizedBox);
      expect(sizedBoxFinder, findsOneWidget);
      final SizedBox sizedBox = tester.widget(sizedBoxFinder);
      expect(sizedBox.width, 0.0);
      expect(sizedBox.height, 0.0);
    });
  });

  group('TerminalConsoleModal Dual Button Tests', () {
    testWidgets('renders both primary and secondary buttons when configured', (WidgetTester tester) async {
      final controller = TerminalConsoleController();
      bool secondaryClicked = false;
      bool primaryClicked = false;

      controller.setAction(
        text: '重新扫码补签 (2人)',
        onPressed: () {
          primaryClicked = true;
        },
        secondaryText: '不管了，直接进入课堂',
        onSecondaryPressed: () {
          secondaryClicked = true;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalConsoleModal(
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.text('不管了，直接进入课堂'), findsOneWidget);
      expect(find.text('重新扫码补签 (2人)'), findsOneWidget);

      await tester.tap(find.text('不管了，直接进入课堂'));
      expect(secondaryClicked, isTrue);

      await tester.tap(find.text('重新扫码补签 (2人)'));
      expect(primaryClicked, isTrue);
    });
  });

  group('LocationCheckInPage Preview Mode Tests', () {
    testWidgets('renders full radar ripples, countdown, and mock info in preview mode', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LocationCheckInPage(
            lessonId: 'preview_demo',
            isPreview: true,
          ),
        ),
      );

      await tester.pump();

      expect(find.text('位置打卡'), findsOneWidget);
      expect(find.textContaining('签到倒计时'), findsOneWidget);
      expect(find.textContaining('已进入签到范围'), findsOneWidget);
      expect(find.textContaining('清华大学第六教学楼'), findsOneWidget);
      expect(find.text('立即签到'), findsOneWidget);

      // Tap submit button in preview
      await tester.tap(find.text('立即签到'));
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('签到成功！'), findsOneWidget);
      expect(find.text('返回课堂'), findsOneWidget);
    });
  });
}
