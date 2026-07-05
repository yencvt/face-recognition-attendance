import 'package:flutter_cam/log/log_service.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static Database? _db;

  static Future<Database> instance() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    LogService().info('DB path: $dbPath');

    final path = join(dbPath, 'my_app.db');

    _db = await openDatabase(
      path,
      version: 12,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            age INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE auth_users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password TEXT NOT NULL,
            role TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            price REAL
          )
        ''');

        await db.execute('''
          CREATE TABLE cameras(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            source TEXT NOT NULL,
            endpoint TEXT,
            color TEXT NOT NULL,
            connection_state TEXT,
            status_message TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE settings(
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE face_cache_state(
            key TEXT PRIMARY KEY,
            value INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE face_people(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            employee_code TEXT,
            department TEXT,
            notes TEXT,
            image_base64 TEXT,
            image_crop_base64 TEXT,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE face_person_images(
            id TEXT PRIMARY KEY,
            person_id TEXT NOT NULL,
            image_base64 TEXT NOT NULL,
            image_crop_base64 TEXT,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE face_vector_cache(
            source_id TEXT PRIMARY KEY,
            person_id TEXT NOT NULL,
            source_type TEXT NOT NULL,
            vector_blob BLOB NOT NULL,
            eye_vector_blob BLOB,
            nose_vector_blob BLOB,
            mouth_vector_blob BLOB,
            forehead_vector_blob BLOB,
            left_eye_vector_blob BLOB,
            right_eye_vector_blob BLOB,
            left_cheek_vector_blob BLOB,
            right_cheek_vector_blob BLOB,
            chin_vector_blob BLOB,
            quality REAL NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE recognition_zones(
            id TEXT PRIMARY KEY,
            camera_id TEXT NOT NULL,
            label TEXT NOT NULL,
            left_ratio REAL NOT NULL,
            top_ratio REAL NOT NULL,
            width_ratio REAL NOT NULL,
            height_ratio REAL NOT NULL,
            rotation_degrees REAL NOT NULL,
            enabled INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE recognition_events(
            id TEXT PRIMARY KEY,
            person_id TEXT,
            person_name TEXT NOT NULL,
            camera_id TEXT,
            confidence REAL NOT NULL,
            is_stranger INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            snapshot_base64 TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings(
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
        }

        if (oldVersion < 4) {
          await db.execute('ALTER TABLE cameras ADD COLUMN connection_state TEXT');
          await db.execute('ALTER TABLE cameras ADD COLUMN status_message TEXT');
        }

        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS face_people(
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              employee_code TEXT,
              department TEXT,
              notes TEXT,
              image_base64 TEXT,
              image_crop_base64 TEXT,
              created_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS recognition_zones(
              id TEXT PRIMARY KEY,
              camera_id TEXT NOT NULL,
              label TEXT NOT NULL,
              left_ratio REAL NOT NULL,
              top_ratio REAL NOT NULL,
              width_ratio REAL NOT NULL,
              height_ratio REAL NOT NULL,
              rotation_degrees REAL NOT NULL,
              enabled INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS recognition_events(
              id TEXT PRIMARY KEY,
              person_id TEXT,
              person_name TEXT NOT NULL,
              camera_id TEXT,
              confidence REAL NOT NULL,
              is_stranger INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              snapshot_base64 TEXT
            )
          ''');
        }

        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS face_person_images(
              id TEXT PRIMARY KEY,
              person_id TEXT NOT NULL,
              image_base64 TEXT NOT NULL,
              image_crop_base64 TEXT,
              created_at INTEGER NOT NULL
            )
          ''');
        }

        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS face_cache_state(
              key TEXT PRIMARY KEY,
              value INTEGER NOT NULL
            )
          ''');
        }

        if (oldVersion < 8) {
          try {
            await db.execute('ALTER TABLE face_people ADD COLUMN image_crop_base64 TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE face_person_images ADD COLUMN image_crop_base64 TEXT');
          } catch (_) {}
        }

        if (oldVersion < 9) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS face_vector_cache(
              source_id TEXT PRIMARY KEY,
              person_id TEXT NOT NULL,
              source_type TEXT NOT NULL,
              vector_blob BLOB NOT NULL,
              eye_vector_blob BLOB,
              nose_vector_blob BLOB,
              mouth_vector_blob BLOB,
              quality REAL NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        }

        if (oldVersion < 10) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS auth_users(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              password TEXT NOT NULL,
              role TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');

          final existingUsers = await db.query('auth_users', limit: 1);
          if (existingUsers.isEmpty) {
            final legacyUsername = await db.query(
              'settings',
              where: 'key = ?',
              whereArgs: ['auth_username'],
              limit: 1,
            );
            final legacyPassword = await db.query(
              'settings',
              where: 'key = ?',
              whereArgs: ['auth_password'],
              limit: 1,
            );
            final now = DateTime.now().millisecondsSinceEpoch;
            await db.insert('auth_users', {
              'username': legacyUsername.isNotEmpty
                  ? legacyUsername.first['value'].toString()
                  : 'admin',
              'password': legacyPassword.isNotEmpty
                  ? legacyPassword.first['value'].toString()
                  : 'admin123',
              'role': 'admin',
              'created_at': now,
              'updated_at': now,
            });
          }
        }

        if (oldVersion < 11) {
          try {
            await db.execute(
              "ALTER TABLE auth_users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'",
            );
          } catch (_) {}

          await db.update(
            'auth_users',
            {'role': 'admin'},
            where: 'username = ?',
            whereArgs: ['admin'],
          );
        }

        if (oldVersion < 12) {
          try {
            await db.execute('ALTER TABLE face_vector_cache ADD COLUMN forehead_vector_blob BLOB');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE face_vector_cache ADD COLUMN left_eye_vector_blob BLOB');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE face_vector_cache ADD COLUMN right_eye_vector_blob BLOB');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE face_vector_cache ADD COLUMN left_cheek_vector_blob BLOB');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE face_vector_cache ADD COLUMN right_cheek_vector_blob BLOB');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE face_vector_cache ADD COLUMN chin_vector_blob BLOB');
          } catch (_) {}
        }
      },
    );

    return _db!;
  }

  static Future<void> saveCamera(Map<String, dynamic> camera) async {
    final db = await instance();
    await db.insert(
      'cameras',
      camera,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getCameras() async {
    final db = await instance();
    return db.query('cameras', orderBy: 'name ASC');
  }

  static Future<void> updateCamera(Map<String, dynamic> camera) async {
    final db = await instance();
    await db.update(
      'cameras',
      camera,
      where: 'id = ?',
      whereArgs: [camera['id']],
    );
  }

  static Future<void> deleteCamera(String id) async {
    final db = await instance();
    await db.delete('cameras', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> saveSelectedCameraId(String id) async {
    final db = await instance();
    await db.insert(
      'settings',
      {'key': 'selected_camera_id', 'value': id},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> setSettingValue(String key, String value) async {
    final db = await instance();
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<String?> getSettingValue(String key) async {
    final db = await instance();
    final result = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first['value']?.toString();
  }

  static Future<String?> getSelectedCameraId() async {
    final db = await instance();
    final result = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['selected_camera_id'],
    );
    if (result.isEmpty) return null;
    return result.first['value'].toString();
  }

  static Future<void> clearCameras() async {
    final db = await instance();
    await db.delete('cameras');
  }
}
