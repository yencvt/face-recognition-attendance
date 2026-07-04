import 'app_database.dart';

class WebRTCSettings {
  WebRTCSettings({
    required this.id,
    required this.signalingServerUrl,
    required this.stunServers,
    required this.turnServers,
    required this.turnUsername,
    required this.turnPassword,
    this.iceTransportPolicy = 'all',
    this.enableAudioProcessing = true,
  });

  final String id;
  final String signalingServerUrl;
  final String stunServers; // JSON string
  final String turnServers; // JSON string
  final String turnUsername;
  final String turnPassword;
  final String iceTransportPolicy;
  final bool enableAudioProcessing;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'signaling_server_url': signalingServerUrl,
      'stun_servers': stunServers,
      'turn_servers': turnServers,
      'turn_username': turnUsername,
      'turn_password': turnPassword,
      'ice_transport_policy': iceTransportPolicy,
      'enable_audio_processing': enableAudioProcessing ? 1 : 0,
    };
  }

  static WebRTCSettings fromMap(Map<String, dynamic> map) {
    return WebRTCSettings(
      id: map['id'].toString(),
      signalingServerUrl: map['signaling_server_url']?.toString() ?? '',
      stunServers: map['stun_servers']?.toString() ?? '[]',
      turnServers: map['turn_servers']?.toString() ?? '[]',
      turnUsername: map['turn_username']?.toString() ?? '',
      turnPassword: map['turn_password']?.toString() ?? '',
      iceTransportPolicy: map['ice_transport_policy']?.toString() ?? 'all',
      enableAudioProcessing: (map['enable_audio_processing'] ?? 1) == 1,
    );
  }
}

class SettingsRepository {
  static const String _settingsTable = 'webrtc_settings';

  static Future<void> initializeSettingsTable() async {
    final db = await AppDatabase.instance();
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_settingsTable (
        id TEXT PRIMARY KEY,
        signaling_server_url TEXT NOT NULL,
        stun_servers TEXT NOT NULL,
        turn_servers TEXT NOT NULL,
        turn_username TEXT,
        turn_password TEXT,
        ice_transport_policy TEXT DEFAULT 'all',
        enable_audio_processing INTEGER DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  static Future<WebRTCSettings?> getSettings() async {
    final db = await AppDatabase.instance();
    final result = await db.query(_settingsTable, limit: 1);
    if (result.isEmpty) {
      return null;
    }
    return WebRTCSettings.fromMap(result.first);
  }

  static Future<void> saveSettings(WebRTCSettings settings) async {
    final db = await AppDatabase.instance();
    
    // Check if settings exist
    final existing = await db.query(
      _settingsTable,
      where: 'id = ?',
      whereArgs: [settings.id],
      limit: 1,
    );

    final map = settings.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();

    if (existing.isEmpty) {
      map['created_at'] = DateTime.now().toIso8601String();
      await db.insert(_settingsTable, map);
    } else {
      await db.update(
        _settingsTable,
        map,
        where: 'id = ?',
        whereArgs: [settings.id],
      );
    }
  }

  static Future<void> deleteSettings(String id) async {
    final db = await AppDatabase.instance();
    await db.delete(
      _settingsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<WebRTCSettings> getOrCreateDefaultSettings() async {
    var settings = await getSettings();
    if (settings == null) {
      settings = WebRTCSettings(
        id: 'default_webrtc_config',
        signalingServerUrl: 'wss://signaling.example.com',
        stunServers: '["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]',
        turnServers: '["turn:turnserver.example.com:3478"]',
        turnUsername: '',
        turnPassword: '',
      );
      await saveSettings(settings);
    }
    return settings;
  }
}
