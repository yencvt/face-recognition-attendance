import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class ReportExportConfig {
  const ReportExportConfig({
    this.scheduledExportEnabled = false,
    this.scheduledExportDirectory = '',
    this.scheduledExportTime = '23:55',
    this.apiEnabled = true,
    this.apiHost = '0.0.0.0',
    this.apiPort = 8787,
    this.filePrefix = 'attendance_report',
  });

  final bool scheduledExportEnabled;
  final String scheduledExportDirectory;
  final String scheduledExportTime; // HH:mm
  final bool apiEnabled;
  final String apiHost;
  final int apiPort;
  final String filePrefix;

  Map<String, dynamic> toMap() {
    return {
      'scheduledExportEnabled': scheduledExportEnabled,
      'scheduledExportDirectory': scheduledExportDirectory,
      'scheduledExportTime': scheduledExportTime,
      'apiEnabled': apiEnabled,
      'apiHost': apiHost,
      'apiPort': apiPort,
      'filePrefix': filePrefix,
    };
  }

  factory ReportExportConfig.fromMap(Map<String, dynamic> map) {
    bool readBool(String key, bool fallback) {
      final value = map[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        return normalized == 'true' || normalized == '1';
      }
      return fallback;
    }

    int readInt(String key, int fallback) {
      final value = map[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    String readString(String key, String fallback) {
      final value = map[key];
      if (value == null) return fallback;
      return value.toString();
    }

    return ReportExportConfig(
      scheduledExportEnabled: readBool('scheduledExportEnabled', false),
      scheduledExportDirectory: readString('scheduledExportDirectory', ''),
      scheduledExportTime: readString('scheduledExportTime', '23:55'),
      apiEnabled: readBool('apiEnabled', true),
      apiHost: readString('apiHost', '0.0.0.0'),
      apiPort: readInt('apiPort', 8787),
      filePrefix: readString('filePrefix', 'attendance_report'),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ReportExportConfig.fromJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return ReportExportConfig.fromMap(decoded);
    }
    if (decoded is Map) {
      return ReportExportConfig.fromMap(decoded.cast<String, dynamic>());
    }
    return const ReportExportConfig();
  }
}

class ReportSettingsRepository {
  static const String _settingsTable = 'settings';
  static const String _configKey = 'report_export_config';
  static const String _lastScheduledRunKey = 'report_export_last_scheduled_run';

  static final StreamController<ReportExportConfig> _changes =
      StreamController<ReportExportConfig>.broadcast();

  static Stream<ReportExportConfig> get changes => _changes.stream;

  static Future<ReportExportConfig> getOrCreateDefaultConfig() async {
    final db = await AppDatabase.instance();
    final row = await db.query(
      _settingsTable,
      where: 'key = ?',
      whereArgs: [_configKey],
      limit: 1,
    );

    if (row.isEmpty) {
      const defaults = ReportExportConfig();
      await db.insert(
        _settingsTable,
        {'key': _configKey, 'value': defaults.toJson()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return defaults;
    }

    final raw = row.first['value']?.toString() ?? '{}';
    try {
      return ReportExportConfig.fromJson(raw);
    } catch (_) {
      return const ReportExportConfig();
    }
  }

  static Future<void> saveConfig(ReportExportConfig config) async {
    final db = await AppDatabase.instance();
    await db.insert(
      _settingsTable,
      {'key': _configKey, 'value': config.toJson()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (!_changes.isClosed) {
      _changes.add(config);
    }
  }

  static Future<String?> getLastScheduledRunDay() async {
    final db = await AppDatabase.instance();
    final row = await db.query(
      _settingsTable,
      where: 'key = ?',
      whereArgs: [_lastScheduledRunKey],
      limit: 1,
    );
    if (row.isEmpty) return null;
    final value = row.first['value']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static Future<void> saveLastScheduledRunDay(String dayKey) async {
    final db = await AppDatabase.instance();
    await db.insert(
      _settingsTable,
      {'key': _lastScheduledRunKey, 'value': dayKey},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
