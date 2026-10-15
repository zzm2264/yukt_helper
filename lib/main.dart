import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';

import './pages/accounts.dart';
import './pages/courses/list.dart';
import './pages/login.dart';
import './api/api_service.dart';
import './session/cookie.dart';
import './session/account.dart';
import './platform.dart';
import './utils/storage.dart';
import './utils/app_logger.dart';

// 全局Navigator Key,用于在无context时显示dialog
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 App 私有目录错误日志系统并捕获全局未捕获异常
  await AppLogger.initialize();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.instance.logSystemError(
      details.exception,
      details.stack,
      context: 'FlutterError: ${details.context?.toDescription()}',
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.instance.logUnhandledAsyncError(error, stack);
    return true;
  };

  await StorageManager.initialize();

  await ApiService.initialize();

  await PlatformManager().initialize();

  await AccountManager.initialize();

  await CookieManager.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: '雨课堂签到',
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US')
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          theme: ThemeData(
            // Material You
            useMaterial3: true,
            colorScheme: lightDynamic ?? ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkDynamic ?? ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
          ),
          themeMode: ThemeMode.system,
          home: const MyHomePage(),
          routes: {
            '/accounts': (context) => const AccountsPage(),
            '/login': (context) => const LoginPage(),
          },
        );
      }
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return const MainPage();
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      (coursesPageKey.currentState as dynamic)?.onVisibilityChanged(true);
      _checkAccountsValidityOnStartup();
    });
  }

  Future<void> _checkAccountsValidityOnStartup() async {
    final allAccounts = AccountManager.allAccounts;
    if (allAccounts.isEmpty) return;

    final result = await AccountManager.checkAllAccountsValidity();
    if (!mounted) return;

    if (result.hasInvalid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '账号登录凭证已失效',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '检测到 ${result.invalidAccounts.length} 个账号已失效，请重新登录',
                      style: const TextStyle(color: Color(0xFFFEE2E2), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: '去处理',
            textColor: const Color(0xFFFEF08A),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AccountsPage()),
              );
            },
          ),
        ),
      );
    }
    // 正常状态下静默无感，不弹窗打扰用户；只有在账号真正失效时才做警示提示
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          CoursesPage(key: coursesPageKey),
          const AccountsPage(),
        ]
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.school),
            label: '课程',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: '账号',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          (coursesPageKey.currentState as dynamic)?.onVisibilityChanged(index == 0);
        },
      ),
    );
  }
}