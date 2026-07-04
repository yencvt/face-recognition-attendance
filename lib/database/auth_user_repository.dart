import 'app_database.dart';

class AuthUser {
  AuthUser({
    required this.id,
    required this.username,
    required this.password,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String username;
  final String password;
  final String role;
  final int createdAt;
  final int updatedAt;

  bool get isAdmin => role == 'admin';

  AuthUser copyWith({
    int? id,
    String? username,
    String? password,
    String? role,
    int? createdAt,
    int? updatedAt,
  }) {
    return AuthUser(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'username': username,
      'password': password,
      'role': role,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  static AuthUser fromMap(Map<String, Object?> map) {
    return AuthUser(
      id: map['id'] as int?,
      username: map['username'].toString(),
      password: map['password'].toString(),
      role: map['role']?.toString() ?? 'user',
      createdAt: (map['created_at'] as num).toInt(),
      updatedAt: (map['updated_at'] as num).toInt(),
    );
  }
}

class AuthUserRepository {
  static const String _table = 'auth_users';

  Future<List<AuthUser>> getAllUsers() async {
    final db = await AppDatabase.instance();
    final rows = await db.query(_table, orderBy: 'username COLLATE NOCASE ASC');
    return rows.map(AuthUser.fromMap).toList(growable: false);
  }

  Future<AuthUser?> findByUsername(String username) async {
    final db = await AppDatabase.instance();
    final rows = await db.query(
      _table,
      where: 'username = ?',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AuthUser.fromMap(rows.first);
  }

  Future<AuthUser?> findByCredentials(String username, String password) async {
    final db = await AppDatabase.instance();
    final rows = await db.query(
      _table,
      where: 'username = ? AND password = ?',
      whereArgs: [username.trim(), password],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AuthUser.fromMap(rows.first);
  }

  Future<int> insertUser(
    String username,
    String password, {
    String role = 'user',
  }) async {
    final db = await AppDatabase.instance();
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert(
      _table,
      {
        'username': username.trim(),
        'password': password,
        'role': role,
        'created_at': now,
        'updated_at': now,
      },
    );
  }

  Future<int> updateUser({
    required int id,
    required String username,
    required String password,
    required String role,
  }) async {
    final db = await AppDatabase.instance();
    return db.update(
      _table,
      {
        'username': username.trim(),
        'password': password,
        'role': role,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePassword({
    required int id,
    required String password,
  }) async {
    final db = await AppDatabase.instance();
    return db.update(
      _table,
      {
        'password': password,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteUser(int id) async {
    final db = await AppDatabase.instance();
    return db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
