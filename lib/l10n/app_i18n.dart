import 'package:flutter/material.dart';

class AppI18nController {
  static final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(
    const Locale('vi'),
  );

  static void setLocaleCode(String code) {
    localeNotifier.value = Locale(code);
  }
}

class AppI18n {
  AppI18n(this.locale);

  final Locale locale;

  static const Map<String, Map<String, String>> _localizedValues = {
    'vi': {
      'language.vi': 'Tiếng Việt',
      'language.en': 'English',
      'role.admin': 'Quản trị',
      'role.user': 'Người dùng',
      'attendance.title': 'Chấm công khuôn mặt',
      'attendance.addCamera': 'Thêm camera',
      'attendance.systemConfig': 'Cấu hình hệ thống',
      'attendance.logout': 'Đăng xuất',
      'settings.title': 'Cấu hình hệ thống',
      'settings.centerTitle': 'Trung tâm cấu hình hệ thống',
      'settings.centerSubtitle':
          'Quản lý kết nối WebRTC, báo cáo và điều hướng nhanh đến các màn cấu hình chuyên sâu.',
        'settings.overview.preset': 'Mặc định preset',
        'settings.overview.report': 'Báo cáo định kỳ',
        'settings.overview.api': 'API xuất báo cáo',
        'status.on': 'Đang bật',
        'status.off': 'Đang tắt',
      'settings.quick.testConnection': 'Kiểm tra kết nối',
      'settings.quick.people': 'Quản lý người',
      'settings.quick.accounts': 'Quản lý tài khoản',
      'settings.quick.imageTest': 'Mở màn kiểm thử ảnh',
      'settings.section.webrtc.title': 'Kết nối WebRTC',
      'settings.section.report.title': 'Báo cáo CSV và API công khai',
      'settings.section.recognition.title': 'Cấu hình nhận diện nâng cao',
      'settings.reset': 'Đặt lại mặc định',
      'settings.save': 'Lưu cấu hình',
      'login.subtitle': 'Nhận diện khuôn mặt và chấm công',
      'login.idleHint': 'Nếu không thao tác 10 phút, hệ thống sẽ tự động đăng xuất.',
      'login.username': 'Tài khoản',
      'login.password': 'Mật khẩu',
      'login.submit': 'Đăng nhập',
      'main.autoLogout': 'Đã tự động đăng xuất do không thao tác trong 10 phút.',
      'main.loginFailed': 'Sai tài khoản hoặc mật khẩu.',
    },
    'en': {
      'language.vi': 'Vietnamese',
      'language.en': 'English',
      'role.admin': 'Admin',
      'role.user': 'User',
      'attendance.title': 'Face Attendance',
      'attendance.addCamera': 'Add camera',
      'attendance.systemConfig': 'System settings',
      'attendance.logout': 'Logout',
      'settings.title': 'System Settings',
      'settings.centerTitle': 'System Configuration Center',
      'settings.centerSubtitle':
          'Manage WebRTC connectivity, reports, and quick navigation to advanced configuration screens.',
        'settings.overview.preset': 'Default preset',
        'settings.overview.report': 'Scheduled reports',
        'settings.overview.api': 'Report API',
        'status.on': 'Enabled',
        'status.off': 'Disabled',
      'settings.quick.testConnection': 'Test connection',
      'settings.quick.people': 'Manage people',
      'settings.quick.accounts': 'Manage accounts',
      'settings.quick.imageTest': 'Open image test screen',
      'settings.section.webrtc.title': 'WebRTC Connectivity',
      'settings.section.report.title': 'CSV Reports and Public API',
      'settings.section.recognition.title': 'Advanced Recognition Settings',
      'settings.reset': 'Reset defaults',
      'settings.save': 'Save settings',
      'login.subtitle': 'Face recognition and attendance',
      'login.idleHint': 'If there is no activity for 10 minutes, the system logs out automatically.',
      'login.username': 'Username',
      'login.password': 'Password',
      'login.submit': 'Login',
      'main.autoLogout': 'Automatically logged out due to 10 minutes of inactivity.',
      'main.loginFailed': 'Invalid username or password.',
    },
  };

  String t(String key) {
    final languageCode = locale.languageCode;
    final languageMap = _localizedValues[languageCode] ?? _localizedValues['vi']!;
    return languageMap[key] ?? _localizedValues['vi']![key] ?? key;
  }

  static AppI18n of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_AppI18nScope>();
    if (scope == null) {
      return AppI18n(AppI18nController.localeNotifier.value);
    }
    return AppI18n(scope.locale);
  }
}

class _AppI18nScope extends InheritedWidget {
  const _AppI18nScope({
    required this.locale,
    required super.child,
  });

  final Locale locale;

  @override
  bool updateShouldNotify(_AppI18nScope oldWidget) => oldWidget.locale != locale;
}

class AppI18nProvider extends StatelessWidget {
  const AppI18nProvider({
    super.key,
    required this.locale,
    required this.child,
  });

  final Locale locale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _AppI18nScope(
      locale: locale,
      child: child,
    );
  }
}
