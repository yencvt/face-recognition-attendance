import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database/app_database.dart';
import 'database/settings_repository.dart';
import 'log/log_service.dart';
import 'screens/attendance_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_session_service.dart';
import 'services/camera_stream_service.dart';
import 'services/face_recognition_service.dart';
import 'services/report_automation_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService().init();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  await AppDatabase.instance();
  await SettingsRepository.initializeSettingsTable();
  await AuthSessionService.instance.initialize();
  await CameraStreamService.instance.initialize();
  await FaceRecognitionService.instance.initialize();
  await ReportAutomationService.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AuthSessionService _auth = AuthSessionService.instance;
  final FocusNode _keyFocusNode = FocusNode();
  String? _loginError;

  @override
  void initState() {
    super.initState();
    _auth.events.listen((event) {
      if (!mounted) return;
      if (event == 'logout_idle') {
        setState(() {
          _loginError = 'Da tu dong dang xuat do khong thao tac trong 10 phut.';
        });
      }
      if (event == 'logout_manual') {
        setState(() {
          _loginError = null;
        });
      }
      if (event == 'login_success') {
        setState(() {
          _loginError = null;
        });
      }
      if (event == 'current_user_updated') {
        setState(() {});
      }
    });
  }

  void _markActivity() {
    _auth.markUserActivity();
  }

  Future<bool> _handleLogin(String username, String password) async {
    final ok = await _auth.login(username: username, password: password);
    if (!mounted) return ok;
    setState(() {
      _loginError = ok ? null : 'Sai tai khoan hoac mat khau.';
    });
    return ok;
  }

  @override
  void dispose() {
    _keyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Camera Conference',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _markActivity(),
          onPointerMove: (_) => _markActivity(),
          onPointerSignal: (_) => _markActivity(),
          child: KeyboardListener(
            focusNode: _keyFocusNode,
            autofocus: true,
            onKeyEvent: (_) => _markActivity(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  ignoring: !_auth.isAuthenticated,
                  child: const AttendanceScreen(),
                ),
                if (!_auth.isAuthenticated)
                  LoginScreen(
                    onLogin: _handleLogin,
                    errorText: _loginError,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
