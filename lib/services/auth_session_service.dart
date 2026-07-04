import 'dart:async';

import '../database/auth_user_repository.dart';

class AuthSessionService {
  AuthSessionService._();

  static final AuthSessionService instance = AuthSessionService._();

  static const Duration _idleTimeout = Duration(minutes: 10);

  final StreamController<String> _events = StreamController<String>.broadcast();

  bool _initialized = false;
  bool _isAuthenticated = false;
  AuthUser? _currentUser;
  DateTime _lastActivityAt = DateTime.now();
  Timer? _idleTimer;

  Stream<String> get events => _events.stream;

  bool get isAuthenticated => _isAuthenticated;
  AuthUser? get currentUser => _currentUser;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  void updateCurrentUser(AuthUser user) {
    _currentUser = user;
    _events.add('current_user_updated');
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final repo = AuthUserRepository();
    final users = await repo.getAllUsers();
    if (users.isEmpty) {
      await repo.insertUser('admin', 'admin123', role: 'admin');
    }
  }

  Future<bool> login({required String username, required String password}) async {
    await initialize();

    final repo = AuthUserRepository();
    final user = await repo.findByCredentials(username, password);
    final ok = user != null;
    if (!ok) {
      _events.add('login_failed');
      return false;
    }

    _isAuthenticated = true;
    _currentUser = user;
    _events.add('login_success');
    markUserActivity();
    _startIdleWatch();
    return true;
  }

  void markUserActivity() {
    if (!_isAuthenticated) return;
    _lastActivityAt = DateTime.now();
  }

  void logout({bool dueToInactivity = false}) {
    if (!_isAuthenticated) return;
    _isAuthenticated = false;
    _currentUser = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _events.add(dueToInactivity ? 'logout_idle' : 'logout_manual');
  }

  void _startIdleWatch() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isAuthenticated) return;
      final idleFor = DateTime.now().difference(_lastActivityAt);
      if (idleFor >= _idleTimeout) {
        logout(dueToInactivity: true);
      }
    });
  }

  Future<void> dispose() async {
    _idleTimer?.cancel();
    await _events.close();
  }
}
