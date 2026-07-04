import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class RecognitionRuntimeConfig {
  const RecognitionRuntimeConfig({
    this.knownMatchThreshold = 0.965,
    this.knownStrongThreshold = 0.985,
    this.knownCalibratedThreshold = 0.94,
    this.knownMatchMargin = 0.26,
    this.minTemplateSharpness = 38.0,
    this.cameraCalibrationDurationMs = 25000,
    this.calibrationLogThrottleMs = 750,
    this.fallbackSkipLogIntervalMs = 3000,
    this.fallbackCaptureIntervalMs = 100,
    this.fallbackMaxInputEdge = 960,
    this.processFrameIntervalMs = 70,
    this.detectorInputWidth = 640,
    this.detectorInputHeight = 480,
    this.trackKeepAliveMs = 1200,
    this.trackMatchMinScore = 0.42,
    this.bboxSmoothingAlpha = 0.34,
    this.annotatedFrameMinIntervalMs = 100,
    this.eventPublishIntervalMs = 80000,
    this.minRealtimeFrameQuality = 0.30,
    this.minRealtimeFaceAreaRatio = 0.055,
    this.minRealtimeFacePixels = 76,
    this.voteWindowSize = 8,
    this.voteMinCount = 6,
    this.voteMaxAgeMs = 2600,
    this.minEnrollmentFaceAreaRatio = 0.07,
    this.maxEnrollmentFaceAreaRatio = 0.75,
    this.minEnrollmentFaceAspectRatio = 0.65,
    this.maxEnrollmentFaceAspectRatio = 1.55,
    this.minEnrollmentFacePixels = 72,
    this.scrfdInputSize = 640,
    this.scrfdScoreThreshold = 0.64,
    this.scrfdNmsThreshold = 0.33,
    this.hnswM = 24,
    this.hnswEfConstruction = 200,
    this.hnswEfSearch = 220,
    this.eyeRegionMinQuality = 0.30,
    this.noseRegionMinQuality = 0.28,
    this.mouthRegionMinQuality = 0.28,
    this.autoTuneRecognitionParameters = false,
    this.debugRealtimeOverlay = true,
  });

  final double knownMatchThreshold;
  final double knownStrongThreshold;
  final double knownCalibratedThreshold;
  final double knownMatchMargin;
  final double minTemplateSharpness;
  final int cameraCalibrationDurationMs;
  final int calibrationLogThrottleMs;
  final int fallbackSkipLogIntervalMs;
  final int fallbackCaptureIntervalMs;
  final int fallbackMaxInputEdge;
  final int processFrameIntervalMs;
  final int detectorInputWidth;
  final int detectorInputHeight;
  final int trackKeepAliveMs;
  final double trackMatchMinScore;
  final double bboxSmoothingAlpha;
  final int annotatedFrameMinIntervalMs;
  final int eventPublishIntervalMs;
  final double minRealtimeFrameQuality;
  final double minRealtimeFaceAreaRatio;
  final int minRealtimeFacePixels;
  final int voteWindowSize;
  final int voteMinCount;
  final int voteMaxAgeMs;
  final double minEnrollmentFaceAreaRatio;
  final double maxEnrollmentFaceAreaRatio;
  final double minEnrollmentFaceAspectRatio;
  final double maxEnrollmentFaceAspectRatio;
  final int minEnrollmentFacePixels;
  final int scrfdInputSize;
  final double scrfdScoreThreshold;
  final double scrfdNmsThreshold;
  final int hnswM;
  final int hnswEfConstruction;
  final int hnswEfSearch;
  final double eyeRegionMinQuality;
  final double noseRegionMinQuality;
  final double mouthRegionMinQuality;
  final bool autoTuneRecognitionParameters;
  final bool debugRealtimeOverlay;

  Map<String, dynamic> toMap() {
    return {
      'knownMatchThreshold': knownMatchThreshold,
      'knownStrongThreshold': knownStrongThreshold,
      'knownCalibratedThreshold': knownCalibratedThreshold,
      'knownMatchMargin': knownMatchMargin,
      'minTemplateSharpness': minTemplateSharpness,
      'cameraCalibrationDurationMs': cameraCalibrationDurationMs,
      'calibrationLogThrottleMs': calibrationLogThrottleMs,
      'fallbackSkipLogIntervalMs': fallbackSkipLogIntervalMs,
      'fallbackCaptureIntervalMs': fallbackCaptureIntervalMs,
      'fallbackMaxInputEdge': fallbackMaxInputEdge,
      'processFrameIntervalMs': processFrameIntervalMs,
      'detectorInputWidth': detectorInputWidth,
      'detectorInputHeight': detectorInputHeight,
      'trackKeepAliveMs': trackKeepAliveMs,
      'trackMatchMinScore': trackMatchMinScore,
      'bboxSmoothingAlpha': bboxSmoothingAlpha,
      'annotatedFrameMinIntervalMs': annotatedFrameMinIntervalMs,
      'eventPublishIntervalMs': eventPublishIntervalMs,
      'minRealtimeFrameQuality': minRealtimeFrameQuality,
      'minRealtimeFaceAreaRatio': minRealtimeFaceAreaRatio,
      'minRealtimeFacePixels': minRealtimeFacePixels,
      'voteWindowSize': voteWindowSize,
      'voteMinCount': voteMinCount,
      'voteMaxAgeMs': voteMaxAgeMs,
      'minEnrollmentFaceAreaRatio': minEnrollmentFaceAreaRatio,
      'maxEnrollmentFaceAreaRatio': maxEnrollmentFaceAreaRatio,
      'minEnrollmentFaceAspectRatio': minEnrollmentFaceAspectRatio,
      'maxEnrollmentFaceAspectRatio': maxEnrollmentFaceAspectRatio,
      'minEnrollmentFacePixels': minEnrollmentFacePixels,
      'scrfdInputSize': scrfdInputSize,
      'scrfdScoreThreshold': scrfdScoreThreshold,
      'scrfdNmsThreshold': scrfdNmsThreshold,
      'hnswM': hnswM,
      'hnswEfConstruction': hnswEfConstruction,
      'hnswEfSearch': hnswEfSearch,
      'eyeRegionMinQuality': eyeRegionMinQuality,
      'noseRegionMinQuality': noseRegionMinQuality,
      'mouthRegionMinQuality': mouthRegionMinQuality,
      'autoTuneRecognitionParameters': autoTuneRecognitionParameters,
      'debugRealtimeOverlay': debugRealtimeOverlay,
    };
  }

  factory RecognitionRuntimeConfig.fromMap(Map<String, dynamic> map) {
    double d(String key, double fallback) {
      final value = map[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    int i(String key, int fallback) {
      final value = map[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    bool b(String key, bool fallback) {
      final value = map[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') return true;
        if (normalized == 'false' || normalized == '0') return false;
      }
      return fallback;
    }

    return RecognitionRuntimeConfig(
      knownMatchThreshold: d('knownMatchThreshold', 0.92),
      knownStrongThreshold: d('knownStrongThreshold', 0.96),
      knownCalibratedThreshold: d('knownCalibratedThreshold', 0.78),
      knownMatchMargin: d('knownMatchMargin', 0.18),
      minTemplateSharpness: d('minTemplateSharpness', 28.0),
      cameraCalibrationDurationMs: i('cameraCalibrationDurationMs', 25000),
      calibrationLogThrottleMs: i('calibrationLogThrottleMs', 750),
      fallbackSkipLogIntervalMs: i('fallbackSkipLogIntervalMs', 3000),
      fallbackCaptureIntervalMs: i('fallbackCaptureIntervalMs', 100),
      fallbackMaxInputEdge: i('fallbackMaxInputEdge', 960),
      processFrameIntervalMs: i('processFrameIntervalMs', 50),
      detectorInputWidth: i('detectorInputWidth', 640),
      detectorInputHeight: i('detectorInputHeight', 480),
      trackKeepAliveMs: i('trackKeepAliveMs', 1200),
      trackMatchMinScore: d('trackMatchMinScore', 0.42),
      bboxSmoothingAlpha: d('bboxSmoothingAlpha', 0.34),
      annotatedFrameMinIntervalMs: i('annotatedFrameMinIntervalMs', 100),
      eventPublishIntervalMs: i('eventPublishIntervalMs', 60000),
      minRealtimeFrameQuality: d('minRealtimeFrameQuality', 0.22),
      minRealtimeFaceAreaRatio: d('minRealtimeFaceAreaRatio', 0.035),
      minRealtimeFacePixels: i('minRealtimeFacePixels', 56),
      voteWindowSize: i('voteWindowSize', 5),
      voteMinCount: i('voteMinCount', 3),
      voteMaxAgeMs: i('voteMaxAgeMs', 1800),
      minEnrollmentFaceAreaRatio: d('minEnrollmentFaceAreaRatio', 0.07),
      maxEnrollmentFaceAreaRatio: d('maxEnrollmentFaceAreaRatio', 0.75),
      minEnrollmentFaceAspectRatio: d('minEnrollmentFaceAspectRatio', 0.65),
      maxEnrollmentFaceAspectRatio: d('maxEnrollmentFaceAspectRatio', 1.55),
      minEnrollmentFacePixels: i('minEnrollmentFacePixels', 72),
      scrfdInputSize: i('scrfdInputSize', 640),
      scrfdScoreThreshold: d('scrfdScoreThreshold', 0.55),
      scrfdNmsThreshold: d('scrfdNmsThreshold', 0.38),
      hnswM: i('hnswM', 20),
      hnswEfConstruction: i('hnswEfConstruction', 144),
      hnswEfSearch: i('hnswEfSearch', 160),
      eyeRegionMinQuality: d('eyeRegionMinQuality', 0.24),
      noseRegionMinQuality: d('noseRegionMinQuality', 0.22),
      mouthRegionMinQuality: d('mouthRegionMinQuality', 0.22),
      autoTuneRecognitionParameters: b('autoTuneRecognitionParameters', false),
      debugRealtimeOverlay: b('debugRealtimeOverlay', true),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory RecognitionRuntimeConfig.fromJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return RecognitionRuntimeConfig.fromMap(decoded);
    }
    if (decoded is Map) {
      return RecognitionRuntimeConfig.fromMap(decoded.cast<String, dynamic>());
    }
    return const RecognitionRuntimeConfig();
  }
}

class RecognitionSettingsRepository {
  static const String _settingsTable = 'settings';
  static const String _configKey = 'recognition_runtime_config';
  static final StreamController<RecognitionRuntimeConfig> _changes =
      StreamController<RecognitionRuntimeConfig>.broadcast();

  static Stream<RecognitionRuntimeConfig> get changes => _changes.stream;

  static Future<RecognitionRuntimeConfig> getOrCreateDefaultConfig() async {
    final db = await AppDatabase.instance();
    final row = await db.query(
      _settingsTable,
      where: 'key = ?',
      whereArgs: [_configKey],
      limit: 1,
    );

    if (row.isEmpty) {
      const defaults = RecognitionRuntimeConfig();
      await db.insert(
        _settingsTable,
        {'key': _configKey, 'value': defaults.toJson()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return defaults;
    }

    final raw = row.first['value']?.toString() ?? '{}';
    try {
      return RecognitionRuntimeConfig.fromJson(raw);
    } catch (_) {
      return const RecognitionRuntimeConfig();
    }
  }

  static Future<void> saveConfig(RecognitionRuntimeConfig config) async {
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
}
