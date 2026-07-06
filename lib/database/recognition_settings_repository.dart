import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class RecognitionRuntimeConfig {
  const RecognitionRuntimeConfig({
    this.knownMatchThreshold = 0.945,
    this.knownCalibratedThreshold = 0.905,
    this.knownMatchMargin = 0.185,
    this.minTemplateSharpness = 34.0,
    this.cameraCalibrationDurationMs = 25000,
    this.calibrationLogThrottleMs = 750,
    this.fallbackSkipLogIntervalMs = 3000,
    this.fallbackCaptureIntervalMs = 100,
    this.fallbackMaxInputEdge = 960,
    this.processFrameIntervalMs = 82,
    this.maxConcurrentFrameWorkers = 2,
    this.singleFlightKeepLatestFrames = 1,
    this.detectorInputWidth = 640,
    this.detectorInputHeight = 480,
    this.trackKeepAliveMs = 1200,
    this.trackMatchMinScore = 0.42,
    this.bboxSmoothingAlpha = 0.34,
    this.annotatedFrameMinIntervalMs = 140,
    this.eventPublishIntervalMs = 80000,
    this.minRealtimeFrameQuality = 0.28,
    this.minRealtimeFaceAreaRatio = 0.030,
    this.minRealtimeFacePixels = 52,
    this.realtimePartialMinFrameQuality = 0.60,
    this.realtimePartialMinFaceAreaRatio = 0.035,
    this.realtimePartialMinFacePixels = 64,
    this.realtimePartialMode = 0,
    this.realtimePartialEnabledRegions =
      'forehead,leftEye,rightEye,nose,leftCheek,rightCheek,mouth,chin',
    this.realtimePartialFrameCycle = 2,
    this.minEnrollmentFaceAreaRatio = 0.08,
    this.maxEnrollmentFaceAreaRatio = 0.75,
    this.minEnrollmentFaceAspectRatio = 0.65,
    this.maxEnrollmentFaceAspectRatio = 1.55,
    this.minEnrollmentFacePixels = 84,
    this.scrfdInputSize = 640,
    this.scrfdScoreThreshold = 0.60,
    this.scrfdNmsThreshold = 0.35,
    this.hnswM = 24,
    this.hnswEfConstruction = 200,
    this.hnswEfSearch = 220,
    this.eyeRegionMinQuality = 0.28,
    this.noseRegionMinQuality = 0.26,
    this.mouthRegionMinQuality = 0.26,
    this.enableRealtimeAutoSharpen = true,
    this.debugRealtimeOverlay = true,
    this.enableTraceLogs = false,
    this.enablePerfLogs = false,
    this.showRealtimeFpsBadge = true,
    this.realtimeCropFacesFromCameraImage = false,
    this.enableIsolatePreprocessing = true,
    this.autoTuneMaxSharpenAmount = 1.0,
  });

  final double knownMatchThreshold;
  final double knownCalibratedThreshold;
  final double knownMatchMargin;
  final double minTemplateSharpness;
  final int cameraCalibrationDurationMs;
  final int calibrationLogThrottleMs;
  final int fallbackSkipLogIntervalMs;
  final int fallbackCaptureIntervalMs;
  final int fallbackMaxInputEdge;
  final int processFrameIntervalMs;
  final int maxConcurrentFrameWorkers;
  final int singleFlightKeepLatestFrames;
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
  final double realtimePartialMinFrameQuality;
  final double realtimePartialMinFaceAreaRatio;
  final int realtimePartialMinFacePixels;
  final int realtimePartialMode;
  final String realtimePartialEnabledRegions;
  final int realtimePartialFrameCycle;
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
  final bool enableRealtimeAutoSharpen;
  final bool debugRealtimeOverlay;
  final bool enableTraceLogs;
  final bool enablePerfLogs;
  final bool showRealtimeFpsBadge;
  final bool realtimeCropFacesFromCameraImage;
  final bool enableIsolatePreprocessing;
  final double autoTuneMaxSharpenAmount;

  RecognitionRuntimeConfig copyWith({
    double? knownMatchThreshold,
    double? knownCalibratedThreshold,
    double? knownMatchMargin,
    double? minTemplateSharpness,
    int? cameraCalibrationDurationMs,
    int? calibrationLogThrottleMs,
    int? fallbackSkipLogIntervalMs,
    int? fallbackCaptureIntervalMs,
    int? fallbackMaxInputEdge,
    int? processFrameIntervalMs,
    int? maxConcurrentFrameWorkers,
    int? singleFlightKeepLatestFrames,
    int? detectorInputWidth,
    int? detectorInputHeight,
    int? trackKeepAliveMs,
    double? trackMatchMinScore,
    double? bboxSmoothingAlpha,
    int? annotatedFrameMinIntervalMs,
    int? eventPublishIntervalMs,
    double? minRealtimeFrameQuality,
    double? minRealtimeFaceAreaRatio,
    int? minRealtimeFacePixels,
    double? realtimePartialMinFrameQuality,
    double? realtimePartialMinFaceAreaRatio,
    int? realtimePartialMinFacePixels,
    int? realtimePartialMode,
    String? realtimePartialEnabledRegions,
    int? realtimePartialFrameCycle,
    double? minEnrollmentFaceAreaRatio,
    double? maxEnrollmentFaceAreaRatio,
    double? minEnrollmentFaceAspectRatio,
    double? maxEnrollmentFaceAspectRatio,
    int? minEnrollmentFacePixels,
    int? scrfdInputSize,
    double? scrfdScoreThreshold,
    double? scrfdNmsThreshold,
    int? hnswM,
    int? hnswEfConstruction,
    int? hnswEfSearch,
    double? eyeRegionMinQuality,
    double? noseRegionMinQuality,
    double? mouthRegionMinQuality,
    bool? enableRealtimeAutoSharpen,
    bool? debugRealtimeOverlay,
    bool? enableTraceLogs,
    bool? enablePerfLogs,
    bool? showRealtimeFpsBadge,
    bool? realtimeCropFacesFromCameraImage,
    bool? enableIsolatePreprocessing,
    double? autoTuneMaxSharpenAmount,
  }) {
    return RecognitionRuntimeConfig(
      knownMatchThreshold: knownMatchThreshold ?? this.knownMatchThreshold,
      knownCalibratedThreshold:
          knownCalibratedThreshold ?? this.knownCalibratedThreshold,
      knownMatchMargin: knownMatchMargin ?? this.knownMatchMargin,
      minTemplateSharpness: minTemplateSharpness ?? this.minTemplateSharpness,
      cameraCalibrationDurationMs:
          cameraCalibrationDurationMs ?? this.cameraCalibrationDurationMs,
      calibrationLogThrottleMs:
          calibrationLogThrottleMs ?? this.calibrationLogThrottleMs,
      fallbackSkipLogIntervalMs:
          fallbackSkipLogIntervalMs ?? this.fallbackSkipLogIntervalMs,
      fallbackCaptureIntervalMs:
          fallbackCaptureIntervalMs ?? this.fallbackCaptureIntervalMs,
      fallbackMaxInputEdge: fallbackMaxInputEdge ?? this.fallbackMaxInputEdge,
      processFrameIntervalMs:
          processFrameIntervalMs ?? this.processFrameIntervalMs,
        maxConcurrentFrameWorkers:
          maxConcurrentFrameWorkers ?? this.maxConcurrentFrameWorkers,
      singleFlightKeepLatestFrames:
          singleFlightKeepLatestFrames ?? this.singleFlightKeepLatestFrames,
      detectorInputWidth: detectorInputWidth ?? this.detectorInputWidth,
      detectorInputHeight: detectorInputHeight ?? this.detectorInputHeight,
      trackKeepAliveMs: trackKeepAliveMs ?? this.trackKeepAliveMs,
      trackMatchMinScore: trackMatchMinScore ?? this.trackMatchMinScore,
      bboxSmoothingAlpha: bboxSmoothingAlpha ?? this.bboxSmoothingAlpha,
      annotatedFrameMinIntervalMs:
          annotatedFrameMinIntervalMs ?? this.annotatedFrameMinIntervalMs,
      eventPublishIntervalMs:
          eventPublishIntervalMs ?? this.eventPublishIntervalMs,
      minRealtimeFrameQuality:
          minRealtimeFrameQuality ?? this.minRealtimeFrameQuality,
      minRealtimeFaceAreaRatio:
          minRealtimeFaceAreaRatio ?? this.minRealtimeFaceAreaRatio,
      minRealtimeFacePixels:
          minRealtimeFacePixels ?? this.minRealtimeFacePixels,
      realtimePartialMinFrameQuality:
          realtimePartialMinFrameQuality ?? this.realtimePartialMinFrameQuality,
      realtimePartialMinFaceAreaRatio:
          realtimePartialMinFaceAreaRatio ??
          this.realtimePartialMinFaceAreaRatio,
      realtimePartialMinFacePixels:
          realtimePartialMinFacePixels ?? this.realtimePartialMinFacePixels,
      realtimePartialMode: realtimePartialMode ?? this.realtimePartialMode,
      realtimePartialEnabledRegions:
          realtimePartialEnabledRegions ?? this.realtimePartialEnabledRegions,
      realtimePartialFrameCycle:
          realtimePartialFrameCycle ?? this.realtimePartialFrameCycle,
      minEnrollmentFaceAreaRatio:
          minEnrollmentFaceAreaRatio ?? this.minEnrollmentFaceAreaRatio,
      maxEnrollmentFaceAreaRatio:
          maxEnrollmentFaceAreaRatio ?? this.maxEnrollmentFaceAreaRatio,
      minEnrollmentFaceAspectRatio:
          minEnrollmentFaceAspectRatio ?? this.minEnrollmentFaceAspectRatio,
      maxEnrollmentFaceAspectRatio:
          maxEnrollmentFaceAspectRatio ?? this.maxEnrollmentFaceAspectRatio,
      minEnrollmentFacePixels:
          minEnrollmentFacePixels ?? this.minEnrollmentFacePixels,
      scrfdInputSize: scrfdInputSize ?? this.scrfdInputSize,
      scrfdScoreThreshold: scrfdScoreThreshold ?? this.scrfdScoreThreshold,
      scrfdNmsThreshold: scrfdNmsThreshold ?? this.scrfdNmsThreshold,
      hnswM: hnswM ?? this.hnswM,
      hnswEfConstruction: hnswEfConstruction ?? this.hnswEfConstruction,
      hnswEfSearch: hnswEfSearch ?? this.hnswEfSearch,
      eyeRegionMinQuality: eyeRegionMinQuality ?? this.eyeRegionMinQuality,
      noseRegionMinQuality: noseRegionMinQuality ?? this.noseRegionMinQuality,
      mouthRegionMinQuality:
          mouthRegionMinQuality ?? this.mouthRegionMinQuality,
        enableRealtimeAutoSharpen:
          enableRealtimeAutoSharpen ?? this.enableRealtimeAutoSharpen,
      debugRealtimeOverlay: debugRealtimeOverlay ?? this.debugRealtimeOverlay,
      enableTraceLogs: enableTraceLogs ?? this.enableTraceLogs,
      enablePerfLogs: enablePerfLogs ?? this.enablePerfLogs,
        showRealtimeFpsBadge: showRealtimeFpsBadge ?? this.showRealtimeFpsBadge,
      realtimeCropFacesFromCameraImage:
          realtimeCropFacesFromCameraImage ??
          this.realtimeCropFacesFromCameraImage,
        enableIsolatePreprocessing:
          enableIsolatePreprocessing ?? this.enableIsolatePreprocessing,
      autoTuneMaxSharpenAmount:
          autoTuneMaxSharpenAmount ?? this.autoTuneMaxSharpenAmount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'knownMatchThreshold': knownMatchThreshold,
      'knownCalibratedThreshold': knownCalibratedThreshold,
      'knownMatchMargin': knownMatchMargin,
      'minTemplateSharpness': minTemplateSharpness,
      'cameraCalibrationDurationMs': cameraCalibrationDurationMs,
      'calibrationLogThrottleMs': calibrationLogThrottleMs,
      'fallbackSkipLogIntervalMs': fallbackSkipLogIntervalMs,
      'fallbackCaptureIntervalMs': fallbackCaptureIntervalMs,
      'fallbackMaxInputEdge': fallbackMaxInputEdge,
      'processFrameIntervalMs': processFrameIntervalMs,
      'maxConcurrentFrameWorkers': maxConcurrentFrameWorkers,
      'singleFlightKeepLatestFrames': singleFlightKeepLatestFrames,
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
      'realtimePartialMinFrameQuality': realtimePartialMinFrameQuality,
      'realtimePartialMinFaceAreaRatio': realtimePartialMinFaceAreaRatio,
      'realtimePartialMinFacePixels': realtimePartialMinFacePixels,
      'realtimePartialMode': realtimePartialMode,
      'realtimePartialEnabledRegions': realtimePartialEnabledRegions,
      'realtimePartialFrameCycle': realtimePartialFrameCycle,
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
      'enableRealtimeAutoSharpen': enableRealtimeAutoSharpen,
      'debugRealtimeOverlay': debugRealtimeOverlay,
      'enableTraceLogs': enableTraceLogs,
      'enablePerfLogs': enablePerfLogs,
      'showRealtimeFpsBadge': showRealtimeFpsBadge,
      'realtimeCropFacesFromCameraImage': realtimeCropFacesFromCameraImage,
      'enableIsolatePreprocessing': enableIsolatePreprocessing,
      'autoTuneMaxSharpenAmount': autoTuneMaxSharpenAmount,
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

    String s(String key, String fallback) {
      final value = map[key];
      if (value is String) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? fallback : trimmed;
      }
      return fallback;
    }

    return RecognitionRuntimeConfig(
      knownMatchThreshold: d('knownMatchThreshold', 0.945),
      knownCalibratedThreshold: d('knownCalibratedThreshold', 0.905),
      knownMatchMargin: d('knownMatchMargin', 0.185),
      minTemplateSharpness: d('minTemplateSharpness', 34.0),
      cameraCalibrationDurationMs: i('cameraCalibrationDurationMs', 25000),
      calibrationLogThrottleMs: i('calibrationLogThrottleMs', 750),
      fallbackSkipLogIntervalMs: i('fallbackSkipLogIntervalMs', 3000),
      fallbackCaptureIntervalMs: i('fallbackCaptureIntervalMs', 100),
      fallbackMaxInputEdge: i('fallbackMaxInputEdge', 960),
      processFrameIntervalMs: i('processFrameIntervalMs', 82),
      maxConcurrentFrameWorkers: i('maxConcurrentFrameWorkers', 2),
      singleFlightKeepLatestFrames: i('singleFlightKeepLatestFrames', 1),
      detectorInputWidth: i('detectorInputWidth', 640),
      detectorInputHeight: i('detectorInputHeight', 480),
      trackKeepAliveMs: i('trackKeepAliveMs', 1200),
      trackMatchMinScore: d('trackMatchMinScore', 0.42),
      bboxSmoothingAlpha: d('bboxSmoothingAlpha', 0.34),
      annotatedFrameMinIntervalMs: i('annotatedFrameMinIntervalMs', 140),
      eventPublishIntervalMs: i('eventPublishIntervalMs', 80000),
      minRealtimeFrameQuality: d('minRealtimeFrameQuality', 0.28),
      minRealtimeFaceAreaRatio: d('minRealtimeFaceAreaRatio', 0.030),
      minRealtimeFacePixels: i('minRealtimeFacePixels', 52),
      realtimePartialMinFrameQuality: d('realtimePartialMinFrameQuality', 0.60),
      realtimePartialMinFaceAreaRatio: d('realtimePartialMinFaceAreaRatio', 0.035),
      realtimePartialMinFacePixels: i('realtimePartialMinFacePixels', 64),
      realtimePartialMode: i('realtimePartialMode', 0),
      realtimePartialEnabledRegions: s(
        'realtimePartialEnabledRegions',
        'forehead,leftEye,rightEye,nose,leftCheek,rightCheek,mouth,chin',
      ),
      realtimePartialFrameCycle: i('realtimePartialFrameCycle', 2),
      minEnrollmentFaceAreaRatio: d('minEnrollmentFaceAreaRatio', 0.08),
      maxEnrollmentFaceAreaRatio: d('maxEnrollmentFaceAreaRatio', 0.75),
      minEnrollmentFaceAspectRatio: d('minEnrollmentFaceAspectRatio', 0.65),
      maxEnrollmentFaceAspectRatio: d('maxEnrollmentFaceAspectRatio', 1.55),
      minEnrollmentFacePixels: i('minEnrollmentFacePixels', 84),
      scrfdInputSize: i('scrfdInputSize', 640),
      scrfdScoreThreshold: d('scrfdScoreThreshold', 0.60),
      scrfdNmsThreshold: d('scrfdNmsThreshold', 0.35),
      hnswM: i('hnswM', 24),
      hnswEfConstruction: i('hnswEfConstruction', 200),
      hnswEfSearch: i('hnswEfSearch', 220),
      eyeRegionMinQuality: d('eyeRegionMinQuality', 0.28),
      noseRegionMinQuality: d('noseRegionMinQuality', 0.26),
      mouthRegionMinQuality: d('mouthRegionMinQuality', 0.26),
      enableRealtimeAutoSharpen: b(
        'enableRealtimeAutoSharpen',
        b('autoTuneRecognitionParameters', true),
      ),
      debugRealtimeOverlay: b('debugRealtimeOverlay', true),
      enableTraceLogs: b('enableTraceLogs', false),
      enablePerfLogs: b('enablePerfLogs', false),
      showRealtimeFpsBadge: b('showRealtimeFpsBadge', true),
      realtimeCropFacesFromCameraImage: b(
        'realtimeCropFacesFromCameraImage',
        false,
      ),
      enableIsolatePreprocessing: b('enableIsolatePreprocessing', true),
      autoTuneMaxSharpenAmount: d('autoTuneMaxSharpenAmount', 1.0),
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
      await db.insert(_settingsTable, {
        'key': _configKey,
        'value': defaults.toJson(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    await db.insert(_settingsTable, {
      'key': _configKey,
      'value': config.toJson(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (!_changes.isClosed) {
      _changes.add(config);
    }
  }
}
