import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show
        HttpRequest,
        HttpServer,
        InternetAddress,
        Platform,
        WebSocket,
        WebSocketTransformer;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart' as tfl;
import 'package:flutter_cam/models/face_person.dart';
import 'package:flutter_cam/models/face_template.dart' as face_template;
import 'package:flutter_cam/models/recognition_event.dart';
import 'package:flutter_cam/models/face_overlay_box.dart';
import 'package:flutter_cam/models/recognition_frame_packet.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv.dart' as opencv;
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_cam/cacher/hnsw_vector_index.dart';
import 'package:flutter_cam/cacher/person_score_bucket.dart';

import '../database/face_attendance_repository.dart';
import '../database/recognition_settings_repository.dart';
import '../log/log_service.dart';

class CameraTrackRuntimeStats {
  const CameraTrackRuntimeStats({
    required this.windowStartedAtMs,
    required this.windowDurationMs,
    required this.observedFaces,
    required this.reusedFaces,
    required this.refreshedFaces,
    required this.refreshByAssociation,
    required this.refreshByTtl,
    required this.refreshByPose,
    required this.refreshByGeometry,
  });

  final int windowStartedAtMs;
  final int windowDurationMs;
  final int observedFaces;
  final int reusedFaces;
  final int refreshedFaces;
  final int refreshByAssociation;
  final int refreshByTtl;
  final int refreshByPose;
  final int refreshByGeometry;

  double get reuseRate =>
      observedFaces <= 0 ? 0.0 : reusedFaces / observedFaces;
}

class CameraWorkerRuntimeStats {
  const CameraWorkerRuntimeStats({
    required this.activeWorkers,
    required this.configuredWorkers,
    required this.totalWorkerFps,
    required this.perWorkerFps,
  });

  final int activeWorkers;
  final int configuredWorkers;
  final double totalWorkerFps;
  final List<double> perWorkerFps;
}

class _WorkerRuntimeAccumulator {
  _WorkerRuntimeAccumulator({required this.maxWorkers});

  static const double _emaKeep = 0.80;
  static const double _emaAdd = 0.20;

  int maxWorkers;
  int activeWorkers = 0;
  int configuredWorkers = 1;
  final List<double> _perWorkerFpsEma = <double>[];

  void resetForMaxWorkers(int value) {
    maxWorkers = value;
    configuredWorkers = value;
    activeWorkers = 0;
    for (var i = 0; i < _perWorkerFpsEma.length; i++) {
      _perWorkerFpsEma[i] *= _emaKeep;
      if (_perWorkerFpsEma[i] < 0.01) {
        _perWorkerFpsEma[i] = 0.0;
      }
    }
  }

  void updateBatch({
    required int configured,
    required int active,
    required int elapsedMs,
    required List<int> processedPerWorker,
  }) {
    configuredWorkers = configured;
    activeWorkers = active;
    if (_perWorkerFpsEma.length < processedPerWorker.length) {
      _perWorkerFpsEma.addAll(
        List<double>.filled(
          processedPerWorker.length - _perWorkerFpsEma.length,
          0.0,
        ),
      );
    }
    final safeElapsed = math.max(1, elapsedMs);

    for (var i = 0; i < _perWorkerFpsEma.length; i++) {
      final processed = i < processedPerWorker.length
          ? processedPerWorker[i]
          : 0;
      final instant = processed <= 0 ? 0.0 : (processed * 1000.0) / safeElapsed;
      final prev = _perWorkerFpsEma[i];
      _perWorkerFpsEma[i] = prev <= 0
          ? instant
          : (prev * _emaKeep) + (instant * _emaAdd);
      if (_perWorkerFpsEma[i] < 0.01) {
        _perWorkerFpsEma[i] = 0.0;
      }
    }
  }

  CameraWorkerRuntimeStats snapshot() {
    final visibleCount = math
        .max(activeWorkers, configuredWorkers)
        .clamp(0, _perWorkerFpsEma.length);
    final perWorker = List<double>.generate(
      visibleCount,
      (index) => _perWorkerFpsEma[index],
      growable: false,
    );
    final total = perWorker.fold<double>(0.0, (sum, value) => sum + value);
    return CameraWorkerRuntimeStats(
      activeWorkers: activeWorkers,
      configuredWorkers: configuredWorkers,
      totalWorkerFps: total,
      perWorkerFps: perWorker,
    );
  }
}

class _TrackStatsAccumulator {
  _TrackStatsAccumulator({required this.windowStartedAtMs});

  static const int windowDurationMs = 10000;
  int windowStartedAtMs;
  int observedFaces = 0;
  int reusedFaces = 0;
  int refreshedFaces = 0;
  int refreshByAssociation = 0;
  int refreshByTtl = 0;
  int refreshByPose = 0;
  int refreshByGeometry = 0;

  void reset(int nowMs) {
    windowStartedAtMs = nowMs;
    observedFaces = 0;
    reusedFaces = 0;
    refreshedFaces = 0;
    refreshByAssociation = 0;
    refreshByTtl = 0;
    refreshByPose = 0;
    refreshByGeometry = 0;
  }

  void onReuse() {
    observedFaces++;
    reusedFaces++;
  }

  void onRefresh(_TrackReuseRejectReason reason) {
    observedFaces++;
    refreshedFaces++;
    switch (reason) {
      case _TrackReuseRejectReason.association:
        refreshByAssociation++;
      case _TrackReuseRejectReason.ttl:
        refreshByTtl++;
      case _TrackReuseRejectReason.pose:
        refreshByPose++;
      case _TrackReuseRejectReason.geometry:
        refreshByGeometry++;
    }
  }

  CameraTrackRuntimeStats snapshot() {
    return CameraTrackRuntimeStats(
      windowStartedAtMs: windowStartedAtMs,
      windowDurationMs: windowDurationMs,
      observedFaces: observedFaces,
      reusedFaces: reusedFaces,
      refreshedFaces: refreshedFaces,
      refreshByAssociation: refreshByAssociation,
      refreshByTtl: refreshByTtl,
      refreshByPose: refreshByPose,
      refreshByGeometry: refreshByGeometry,
    );
  }
}

enum _TrackReuseRejectReason { association, ttl, pose, geometry }

class FaceRecognitionNotification {
  FaceRecognitionNotification({required this.cameraId, required this.event});

  final String cameraId;
  final RecognitionEvent event;
}

class EnrollmentFaceCropResult {
  EnrollmentFaceCropResult({
    required this.ok,
    required this.message,
    this.imageBytes,
    this.faceAreaRatio,
    this.faceAspectRatio,
    this.sharpness,
  });

  final bool ok;
  final String message;
  final Uint8List? imageBytes;
  final double? faceAreaRatio;
  final double? faceAspectRatio;
  final double? sharpness;
}

class UploadedImageRecognitionCandidateScore {
  UploadedImageRecognitionCandidateScore({
    required this.personId,
    required this.personName,
    required this.score,
  });

  final String personId;
  final String personName;
  final double score;
}

class UploadedImageRecognitionFaceMatch {
  UploadedImageRecognitionFaceMatch({
    required this.rect,
    required this.name,
    required this.personId,
    required this.score,
  });

  final Rect rect;
  final String name;
  final String? personId;
  final double score;

  bool get isKnown => personId != null && personId!.isNotEmpty;
}

class UploadedImageRecognitionFaceDebugInfo {
  UploadedImageRecognitionFaceDebugInfo({
    required this.faceIndex,
    required this.rect,
    required this.originalFaceBytes,
    required this.cleanedFaceBytes,
    required this.vector,
    required this.vectorNorm,
    required this.detectorScore,
    required this.areaRatio,
    required this.aspectRatio,
    required this.minFacePixels,
    required this.originalLuma,
    required this.cleanedLuma,
    required this.originalSharpness,
    required this.cleanedSharpness,
    required this.matchThreshold,
    required this.topCandidates,
  });

  final int faceIndex;
  final Rect rect;
  final Uint8List originalFaceBytes;
  final Uint8List cleanedFaceBytes;
  final List<double> vector;
  final double vectorNorm;
  final double detectorScore;
  final double areaRatio;
  final double aspectRatio;
  final int minFacePixels;
  final double originalLuma;
  final double cleanedLuma;
  final double originalSharpness;
  final double cleanedSharpness;
  final double matchThreshold;
  final List<UploadedImageRecognitionCandidateScore> topCandidates;
}

class UploadedImageRecognitionResult {
  UploadedImageRecognitionResult({
    required this.pass,
    required this.message,
    required this.annotatedImageBytes,
    required this.matches,
    required this.faceDebugInfos,
    required this.recognizedPersonIds,
    required this.missingPersonIds,
    required this.matchThreshold,
  });

  final bool pass;
  final String message;
  final Uint8List annotatedImageBytes;
  final List<UploadedImageRecognitionFaceMatch> matches;
  final List<UploadedImageRecognitionFaceDebugInfo> faceDebugInfos;
  final Set<String> recognizedPersonIds;
  final List<String> missingPersonIds;
  final double matchThreshold;
}

class _PartialEmbeddingBundle {
  const _PartialEmbeddingBundle({
    this.eyeVector,
    this.leftEyeVector,
    this.rightEyeVector,
    this.noseVector,
    this.mouthVector,
    this.foreheadVector,
    this.leftCheekVector,
    this.rightCheekVector,
    this.chinVector,
    this.eyeWeight = 0.0,
    this.leftEyeWeight = 0.0,
    this.rightEyeWeight = 0.0,
    this.noseWeight = 0.0,
    this.mouthWeight = 0.0,
    this.foreheadWeight = 0.0,
    this.leftCheekWeight = 0.0,
    this.rightCheekWeight = 0.0,
    this.chinWeight = 0.0,
  });

  final List<double>? eyeVector;
  final List<double>? leftEyeVector;
  final List<double>? rightEyeVector;
  final List<double>? noseVector;
  final List<double>? mouthVector;
  final List<double>? foreheadVector;
  final List<double>? leftCheekVector;
  final List<double>? rightCheekVector;
  final List<double>? chinVector;
  final double eyeWeight;
  final double leftEyeWeight;
  final double rightEyeWeight;
  final double noseWeight;
  final double mouthWeight;
  final double foreheadWeight;
  final double leftCheekWeight;
  final double rightCheekWeight;
  final double chinWeight;

  double get totalWeight =>
      eyeWeight +
      leftEyeWeight +
      rightEyeWeight +
      noseWeight +
      mouthWeight +
      foreheadWeight +
      leftCheekWeight +
      rightCheekWeight +
      chinWeight;
  bool get hasAny =>
      eyeVector != null ||
      leftEyeVector != null ||
      rightEyeVector != null ||
      noseVector != null ||
      mouthVector != null ||
      foreheadVector != null ||
      leftCheekVector != null ||
      rightCheekVector != null ||
      chinVector != null;
}

class _MatchResult {
  _MatchResult({
    required this.template,
    required this.score,
    required this.calibratedScore,
    required this.margin,
    required this.templateScore,
    required this.globalScore,
    required this.partialScore,
    required this.partialCoverage,
    required this.eyeWeight,
    required this.noseWeight,
    required this.mouthWeight,
    required this.centroidScore,
    required this.dualConsensus,
  });

  final face_template.FaceTemplate template;
  final double score;
  final double calibratedScore;
  final double margin;
  final double templateScore;
  final double globalScore;
  final double partialScore;
  final double partialCoverage;
  final double eyeWeight;
  final double noseWeight;
  final double mouthWeight;
  final double centroidScore;
  final bool dualConsensus;
}

class _CandidateScore {
  _CandidateScore({
    required this.bucket,
    required this.template,
    required this.templateScore,
    required this.multiPoseScore,
    required this.partialScore,
    required this.partialCoverage,
    required this.centroidScore,
    required this.blendedScore,
    required this.calibratedScore,
    required this.decisionScore,
  });

  final PersonScoreBucket bucket;
  final face_template.FaceTemplate template;
  final double templateScore;
  final double multiPoseScore;
  final double partialScore;
  final double partialCoverage;
  final double centroidScore;
  final double blendedScore;
  final double calibratedScore;
  final double decisionScore;
}

class _CameraThresholdProfile {
  _CameraThresholdProfile({
    required this.matchThreshold,
    required this.calibratedThreshold,
    required this.strongThreshold,
    required this.marginThreshold,
    required this.lockedAtMs,
  });

  final double matchThreshold;
  final double calibratedThreshold;
  final double strongThreshold;
  final double marginThreshold;
  final int lockedAtMs;
}

class _CalibrationSample {
  _CalibrationSample({
    required this.top1Raw,
    required this.top1Cal,
    required this.top1Quality,
    required this.top2Raw,
    required this.top2Cal,
    required this.top2Quality,
    required this.margin,
    required this.frameQuality,
    required this.accepted,
  });

  final double top1Raw;
  final double top1Cal;
  final double top1Quality;
  final double top2Raw;
  final double top2Cal;
  final double top2Quality;
  final double margin;
  final double frameQuality;
  final bool accepted;
}

class _CalibrationWindow {
  _CalibrationWindow({
    required this.cameraId,
    required this.startedAtMs,
    required this.endsAtMs,
  });

  final String cameraId;
  final int startedAtMs;
  final int endsAtMs;
  final List<_CalibrationSample> samples = [];
  final Map<String, int> lastLogAtByFaceKey = {};
  Timer? timer;
}

class _Processor {
  _Processor({required this.controller});

  final CameraController controller;
  bool busy = false;
  bool draining = false;
  int frameCount = 0;
  int lastProcessAtMs = 0;
  int lastAnnotatedFrameAtMs = 0;
  String lastOverlaySignature = '';
  Uint8List? lastOverlayPng;
  final List<CameraImage> pendingFrames = <CameraImage>[];
  Timer? pendingDrainTimer;
  Timer? stillCaptureTimer;
  int lastInputFrameAtMs = 0;
  int lastRecognitionFrameAtMs = 0;
  double inputFpsEma = 0.0;
  double recognitionFpsEma = 0.0;
}

class _CameraFrameInput {
  _CameraFrameInput({required this.image, required this.rotationDegrees});

  final Object image;
  final int rotationDegrees;
}

class _CameraTrack {
  _CameraTrack({
    required this.key,
    required this.currentRect,
    required this.targetRect,
    required this.event,
    required this.lastSeenAt,
    required this.lastRecognitionAt,
    required this.lastTrackingConfidence,
    this.lastYawDeg,
    this.lastPitchDeg,
    this.reuseCount = 0,
    this.cachedEmbedding,
    this.cachedEmbeddingAtMs = 0,
  });

  final String key;
  Rect currentRect;
  Rect targetRect;
  RecognitionEvent event;
  int lastSeenAt;
  int lastRecognitionAt;
  double lastTrackingConfidence;
  double? lastYawDeg;
  double? lastPitchDeg;
  int reuseCount;
  List<double>? cachedEmbedding;
  int cachedEmbeddingAtMs;
}

class _DetectedFace {
  _DetectedFace({required this.rect, this.alignedCrop, this.score = 1.0});

  final Rect rect;
  final img.Image? alignedCrop;
  final double score;
}

class _NativePendingRecognition {
  _NativePendingRecognition({
    required this.tracked,
    required this.ratio,
    required this.rect,
    required this.pose,
    required this.relaxedAssociation,
    required this.minFacePixels,
    required this.faceAreaRatio,
    required this.adaptiveFarDistance,
    required this.frameQuality,
    required this.spoofScore,
    required this.workingCrop,
  });

  final (String, _CameraTrack, double)? tracked;
  final Rect ratio;
  final Rect rect;
  final (double?, double?) pose;
  final bool relaxedAssociation;
  final int minFacePixels;
  final double faceAreaRatio;
  final bool adaptiveFarDistance;
  final double frameQuality;
  final double spoofScore;
  final img.Image workingCrop;
}

class _NativeComputedRecognition {
  _NativeComputedRecognition({
    required this.pending,
    required this.vector,
    required this.partialBundle,
  });

  final _NativePendingRecognition pending;
  final List<double> vector;
  final _PartialEmbeddingBundle partialBundle;
}

class _FallbackPendingRecognition {
  _FallbackPendingRecognition({
    required this.tracked,
    required this.ratio,
    required this.rect,
    required this.relaxedAssociation,
    required this.minFacePixels,
    required this.faceAreaRatio,
    required this.adaptiveFarDistance,
    required this.frameQuality,
    required this.spoofScore,
    required this.workingCrop,
  });

  final (String, _CameraTrack, double)? tracked;
  final Rect ratio;
  final Rect rect;
  final bool relaxedAssociation;
  final int minFacePixels;
  final double faceAreaRatio;
  final bool adaptiveFarDistance;
  final double frameQuality;
  final double spoofScore;
  final img.Image workingCrop;
}

class _FallbackComputedRecognition {
  _FallbackComputedRecognition({
    required this.pending,
    required this.vector,
    required this.partialBundle,
  });

  final _FallbackPendingRecognition pending;
  final List<double> vector;
  final _PartialEmbeddingBundle partialBundle;
}

class _ConcurrencyRunResult<R> {
  const _ConcurrencyRunResult({
    required this.results,
    required this.workerCount,
    required this.activeWorkers,
    required this.processedPerWorker,
    required this.elapsedMs,
  });

  final List<R> results;
  final int workerCount;
  final int activeWorkers;
  final List<int> processedPerWorker;
  final int elapsedMs;
}

class _SpoofAssessment {
  const _SpoofAssessment({
    required this.score,
    required this.reason,
    required this.isSpoof,
  });

  final double score;
  final String reason;
  final bool isSpoof;
}

class _SpoofState {
  _SpoofState({required this.lastSeenAtMs});

  int lastSeenAtMs;
  final List<double> eyeHistory = <double>[];
  final List<double> mouthHistory = <double>[];
  final List<double> motionHistory = <double>[];
  final List<double> sizeHistory = <double>[];
  double? previousEye;
  double? previousMouth;
  Offset? previousCenter;
  bool blinkSeen = false;
  int frameCount = 0;
}

class _AdaptiveDistanceState {
  int smallFaceStreak = 0;
  int activeUntilMs = 0;
  int lastLogAtMs = 0;
  bool lastActive = false;
}

class FaceRecognitionService {
  FaceRecognitionService._();

  static final FaceRecognitionService instance = FaceRecognitionService._();

  final OnnxRuntime _onnxRuntime = OnnxRuntime();
  final LogService _log = LogService();
  final Uuid _uuid = const Uuid();
  static const MethodChannel _windowsCameraExtChannel = MethodChannel(
    'flutter_cam/camera_windows_ext',
  );
  static const int _realtimeWsPort = 8788;
  static const String _realtimeWsPath = '/recognition/realtime';
  static const int _maxRealtimeCacheEvents = 3000;
  static const int _maxPendingDbEvents = 6000;
  static const Duration _dbFlushInterval = Duration(minutes: 5);
  bool get _perfProbeEnabled => _runtimeConfig.enablePerfLogs;
  bool get _detailedScoreVectorLogging => _runtimeConfig.enableTraceLogs;

  final Map<String, _Processor> _processorsByCameraId = {};
  final Map<String, bool> _streamUnavailableByCameraId = {};
  final Set<String> _processorStartingCameraIds = <String>{};
  final Map<String, List<FaceOverlayBox>> _overlaysByCameraId = {};
  final Map<String, int> _lastEventAt = {};
  final Map<String, Map<String, _CameraTrack>> _overlayTracksByCameraId = {};
  final Map<String, int> _fallbackFaceSkipCountByCameraId = {};
  final Map<String, int> _fallbackFaceSkipLogAtByCameraId = {};
  final Map<String, RecognitionZone> _zoneByCameraId = {};
  final Map<String, _SpoofState> _spoofStates = {};
  final Map<String, _AdaptiveDistanceState> _adaptiveDistanceStates = {};
  final Map<String, _TrackStatsAccumulator> _trackStatsByCameraId = {};
  final Map<String, _WorkerRuntimeAccumulator> _workerStatsByCameraId = {};
  final Map<String, int> _missingTemplateGuardLogAtByCameraId = {};
  final List<RecognitionEvent> _realtimeEventCache = <RecognitionEvent>[];
  final List<RecognitionEvent> _pendingDbEvents = <RecognitionEvent>[];
  final Set<WebSocket> _realtimeWsClients = <WebSocket>{};
  final List<face_template.FaceTemplate> _templates = [];

  List<double>? _globalMeanDirection;
  int _templateVectorDimension = 0;
  final Map<String, _CameraThresholdProfile> _cameraThresholdProfiles = {};
  final Map<String, _CalibrationWindow> _calibrationWindows = {};

  final StreamController<RecognitionFramePacket> _frameQueue =
      StreamController<RecognitionFramePacket>.broadcast();
  final StreamController<FaceRecognitionNotification> _notiQueue =
      StreamController<FaceRecognitionNotification>.broadcast();

  List<CameraDescription> _availableCameras = [];
  bool _initialized = false;
  bool _arcFaceAttempted = false;
  OrtSession? _arcFaceSession;
  String _arcFaceInputName = 'data';
  String _arcFaceOutputName = 'fc1';
  bool? _arcFaceInputIsNhwc;
  bool _scrfdAttempted = false;
  OrtSession? _scrfdSession;
  String _scrfdInputName = 'input.1';
  FaceDetectorProcessor? _faceDetectorProcessor;
  FaceMeshProcessor? _faceMeshProcessor;
  FaceMeshInferencePipeline? _faceMeshPipeline;
  final tfl.FaceDetector _fallbackFaceDetector = tfl.FaceDetector();
  bool _fallbackDetectorInitialized = false;

  Timer? _templateMonitorTimer;
  StreamSubscription<RecognitionRuntimeConfig>? _runtimeConfigSub;
  bool _templateRefreshBusy = false;
  int _lastPeopleCacheVersion = -1;
  int _onnxFallbackCount = 0;
  bool _knownRecognitionBlockedByMissingTemplateCache = false;
  int _missingTemplatePeopleCount = 0;
  String _missingTemplatePeoplePreview = '';
  RecognitionRuntimeConfig _runtimeConfig = const RecognitionRuntimeConfig();
  HttpServer? _realtimeWsServer;
  Timer? _dbFlushTimer;
  bool _dbFlushInProgress = false;

  double get _knownMatchThreshold => _runtimeConfig.knownMatchThreshold;
  double get _knownCalibratedThreshold =>
      _runtimeConfig.knownCalibratedThreshold;
  double get _knownMatchMargin => _runtimeConfig.knownMatchMargin;
  double get _minTemplateSharpness => _runtimeConfig.minTemplateSharpness;
  Duration get _cameraCalibrationDuration =>
      Duration(milliseconds: _runtimeConfig.cameraCalibrationDurationMs);
  int get _calibrationLogThrottleMs => _runtimeConfig.calibrationLogThrottleMs;
  int get _fallbackSkipLogIntervalMs =>
      _runtimeConfig.fallbackSkipLogIntervalMs;
  int get _fallbackCaptureIntervalMs =>
      _runtimeConfig.fallbackCaptureIntervalMs;
  int get _fallbackMaxInputEdge => _runtimeConfig.fallbackMaxInputEdge;
  int get _processFrameIntervalMs => _runtimeConfig.processFrameIntervalMs;
  int get _singleFlightKeepLatestFrames =>
      _runtimeConfig.singleFlightKeepLatestFrames.clamp(1, 24).toInt();
  int get _faceMeshMaxWorkers =>
      _runtimeConfig.faceMeshMaxWorkers.clamp(1, 8).toInt();
  int get _detectorInputWidth => _runtimeConfig.detectorInputWidth;
  int get _detectorInputHeight => _runtimeConfig.detectorInputHeight;
  int get _trackKeepAliveMs => _runtimeConfig.trackKeepAliveMs;
  double get _trackMatchMinScore => _runtimeConfig.trackMatchMinScore;
  double get _bboxSmoothingAlpha => _runtimeConfig.bboxSmoothingAlpha;
  int get _annotatedFrameMinIntervalMs =>
      _runtimeConfig.annotatedFrameMinIntervalMs;
  static const int _overlayRendererVersion = 3;
  static const int _bboxOverlayOffsetXPx = 1;
  static const int _adaptiveFarDistanceActivationStreak = 3;
  static const int _adaptiveFarDistanceActiveMs = 8000;
  static const double _adaptiveFarDistanceFaceAreaRatio = 0.010;
  static const int _adaptiveFarDistanceFacePixels = 24;
  static const double _adaptiveFarDistanceFrameQuality = 0.20;
  static const int _realtimePartialModeQualitySize = 0;
  static const int _realtimePartialModeAllFrames = 1;
  static const int _realtimePartialModeDisabled = 2;
  int get _eventPublishIntervalMs =>
      _runtimeConfig.eventPublishIntervalMs.clamp(1000, 20000).toInt();
  int get _trackReuseKnownMs =>
      _runtimeConfig.trackReuseKnownMs.clamp(200, 5000).toInt();
  int get _trackReuseStrangerMs =>
      _runtimeConfig.trackReuseStrangerMs.clamp(120, 3000).toInt();
  double get _trackPoseRefreshDeltaDeg =>
      _runtimeConfig.trackPoseRefreshDeltaDeg.clamp(3.0, 45.0).toDouble();
  double get _trackReuseMinIoU =>
      (_trackMatchMinScore + 0.10).clamp(0.46, 0.84).toDouble();
  double get _trackReuseMaxCenterDistance => 0.20;
  double get _trackAssociationMinScore =>
      (_trackMatchMinScore - 0.12).clamp(0.22, 0.78).toDouble();
  double get _minRealtimeFrameQuality => _runtimeConfig.minRealtimeFrameQuality;
  double get _minRealtimeFaceAreaRatio =>
      _runtimeConfig.minRealtimeFaceAreaRatio;
  int get _minRealtimeFacePixels => _runtimeConfig.minRealtimeFacePixels;
  double get _realtimePartialMinFrameQuality =>
      _runtimeConfig.realtimePartialMinFrameQuality;
  double get _realtimePartialMinFaceAreaRatio =>
      _runtimeConfig.realtimePartialMinFaceAreaRatio;
  int get _realtimePartialMinFacePixels =>
      _runtimeConfig.realtimePartialMinFacePixels;
  int get _realtimePartialMode =>
      _runtimeConfig.realtimePartialMode.clamp(0, 2).toInt();
  Set<String> get _realtimePartialEnabledRegions {
    const fallback = <String>{
      'forehead',
      'leftEye',
      'rightEye',
      'nose',
      'leftCheek',
      'rightCheek',
      'mouth',
      'chin',
    };
    final raw = _runtimeConfig.realtimePartialEnabledRegions;
    final parsed = raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    final valid = parsed.intersection(fallback);
    return valid.isEmpty ? fallback : valid;
  }

  int get _realtimePartialFrameCycle =>
      _runtimeConfig.realtimePartialFrameCycle;
  double get _minEnrollmentFaceAreaRatio =>
      _runtimeConfig.minEnrollmentFaceAreaRatio;
  double get _maxEnrollmentFaceAreaRatio =>
      _runtimeConfig.maxEnrollmentFaceAreaRatio;
  double get _minEnrollmentFaceAspectRatio =>
      _runtimeConfig.minEnrollmentFaceAspectRatio;
  double get _maxEnrollmentFaceAspectRatio =>
      _runtimeConfig.maxEnrollmentFaceAspectRatio;
  int get _minEnrollmentFacePixels => _runtimeConfig.minEnrollmentFacePixels;
  bool get _enableRealtimeAutoSharpen =>
      _runtimeConfig.enableRealtimeAutoSharpen;
  static const List<String> _scrfdModelAssets = <String>[
    'assets/models/scrfd_2.5g_bnkps.onnx',
  ];
  static const List<String> _recognizerModelAssets = <String>[
    'assets/models/adaface.onnx',
    'assets/models/arcface.onnx',
  ];
  int get _scrfdInputSize => _runtimeConfig.scrfdInputSize;
  double get _scrfdScoreThreshold => _runtimeConfig.scrfdScoreThreshold;
  double get _scrfdNmsThreshold => _runtimeConfig.scrfdNmsThreshold;
  int get _hnswM => _runtimeConfig.hnswM;
  int get _hnswEfConstruction => _runtimeConfig.hnswEfConstruction;
  int get _hnswEfSearch => _runtimeConfig.hnswEfSearch;
  double get _eyeRegionMinQuality => _runtimeConfig.eyeRegionMinQuality;
  double get _noseRegionMinQuality => _runtimeConfig.noseRegionMinQuality;
  double get _mouthRegionMinQuality => _runtimeConfig.mouthRegionMinQuality;
  bool get _debugRealtimeOverlay => _runtimeConfig.debugRealtimeOverlay;
  bool get _traceLogsEnabled => _runtimeConfig.enableTraceLogs;
  bool get _realtimeCropFacesFromCameraImage =>
      _runtimeConfig.realtimeCropFacesFromCameraImage;
  double get _autoTuneMaxSharpenAmount =>
      _runtimeConfig.autoTuneMaxSharpenAmount;

  Stream<RecognitionFramePacket> get frameQueue => _frameQueue.stream;
  Stream<FaceRecognitionNotification> get notificationQueue =>
      _notiQueue.stream;

  List<RecognitionEvent> get realtimeEventCacheSnapshot =>
      List<RecognitionEvent>.unmodifiable(_realtimeEventCache);

  List<FaceOverlayBox> overlaysFor(String cameraId) =>
      _overlaysByCameraId[cameraId] ?? const [];

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _runtimeConfig =
          await RecognitionSettingsRepository.getOrCreateDefaultConfig();
      _runtimeConfigSub?.cancel();
      _runtimeConfigSub = RecognitionSettingsRepository.changes.listen((cfg) {
        final old = _runtimeConfig;
        _runtimeConfig = cfg;

        if (old.fallbackCaptureIntervalMs != cfg.fallbackCaptureIntervalMs) {
          _restartFallbackCaptureTimers();
        }

        final thresholdInputsChanged =
            old.knownMatchThreshold != cfg.knownMatchThreshold ||
            old.knownCalibratedThreshold != cfg.knownCalibratedThreshold ||
            old.knownMatchMargin != cfg.knownMatchMargin ||
            old.cameraCalibrationDurationMs !=
                cfg.cameraCalibrationDurationMs ||
            old.calibrationLogThrottleMs != cfg.calibrationLogThrottleMs;
        if (thresholdInputsChanged) {
          _cameraThresholdProfiles.clear();
        }

        final hnswChanged =
            old.hnswM != cfg.hnswM ||
            old.hnswEfConstruction != cfg.hnswEfConstruction ||
            old.hnswEfSearch != cfg.hnswEfSearch;
        if (hnswChanged && _templates.isNotEmpty) {
          HnswVectorIndex().build(
            _templates,
            m: _hnswM,
            efConstruction: _hnswEfConstruction,
            efSearchBase: _hnswEfSearch,
          );
          _log.info(
            'Recognition search index rebuilt m=${cfg.hnswM} efC=${cfg.hnswEfConstruction} efS=${cfg.hnswEfSearch}',
          );
        }
        _log.info('Recognition runtime config hot-updated');
      });
      _log.info('Recognition runtime config loaded from persisted settings');

      _availableCameras = await availableCameras();
      if (_supportsNativeFacePipeline) {
        await _ensureMediaPipeProcessors();
      } else {
        await _fallbackFaceDetector.initialize(
          model: tfl.FaceDetectionModel.full,
        );
        _fallbackDetectorInitialized = true;
        await _ensureScrfdSession();
      }
      await _ensureArcFaceSession();
      await _loadTemplates();
      _lastPeopleCacheVersion =
          await FaceAttendanceRepository.getFacePeopleCacheVersion();
      _startTemplateMonitor();
      await _startRealtimeWebSocketHub();
      _startDbFlushScheduler();
      _log.info(
        'FaceRecognitionService initialized: mode=$runtimeModeLabel cameras=${_availableCameras.length} arcFace=${_arcFaceSession != null}',
      );
    } catch (_) {
      // Keep app startup stable when detector initialization fails.
      _log.error('FaceRecognitionService initialization failed');
    }
  }

  bool get _supportsNativeFacePipeline {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
  }

  String get runtimeModeLabel {
    if (_supportsNativeFacePipeline) {
      return 'MediaPipe Face Mesh + ArcFace ONNX';
    }
    if (_scrfdSession != null) {
      return 'SCRFD 2.5G + AdaFace/ArcFace ONNX';
    }
    if (kIsWeb) {
      return 'Web fallback detector mode';
    }
    return 'Desktop fallback detector mode';
  }

  ImageFormatGroup _preferredImageFormat() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return ImageFormatGroup.bgra8888;
      case TargetPlatform.android:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return ImageFormatGroup.yuv420;
    }
  }

  Future<void> refreshTemplates() async {
    await _loadTemplates();
    _lastPeopleCacheVersion =
        await FaceAttendanceRepository.getFacePeopleCacheVersion();
  }

  void invalidateZoneCache(String? cameraId) {
    if (cameraId == null || cameraId.trim().isEmpty) {
      _zoneByCameraId.clear();
      return;
    }
    _zoneByCameraId.remove(cameraId);
  }

  void _restartFallbackCaptureTimers() {
    final entries = _processorsByCameraId.entries.toList(growable: false);
    for (final entry in entries) {
      final processor = entry.value;
      if (processor.stillCaptureTimer == null) continue;
      _startStillCaptureFallback(entry.key, processor);
    }
  }

  Future<void> rebuildVectorsForPerson(String personId) async {
    final person = await FaceAttendanceRepository.getPersonById(personId);
    if (person == null) {
      return;
    }

    final entries = await _buildVectorCacheEntriesForPerson(person);
    await FaceAttendanceRepository.replaceVectorCacheForPerson(
      personId,
      entries,
    );
    await refreshTemplates();
  }

  Future<void> rebuildVectorsForAllPeople() async {
    final people = await FaceAttendanceRepository.getPeople();
    for (final person in people) {
      final entries = await _buildVectorCacheEntriesForPerson(person);
      await FaceAttendanceRepository.replaceVectorCacheForPerson(
        person.id,
        entries,
      );
    }
    await refreshTemplates();
  }

  Future<EnrollmentFaceCropResult> preprocessEnrollmentImage(
    Uint8List imageBytes, {
    String poseLabel = '',
  }) async {
    if (imageBytes.isEmpty) {
      return EnrollmentFaceCropResult(
        ok: false,
        message: 'Anh trong, vui long chon lai.',
      );
    }

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      return EnrollmentFaceCropResult(
        ok: false,
        message: 'Khong doc duoc anh, vui long thu anh khac.',
      );
    }

    try {
      final detections = await _detectFacesForStaticRecognition(
        decoded,
        contextKey: 'enrollment-image',
      );

      if (detections.isEmpty) {
        return EnrollmentFaceCropResult(
          ok: false,
          message: _poseError(poseLabel, 'Khong phat hien khuon mat.'),
        );
      }
      if (detections.length > 1) {
        return EnrollmentFaceCropResult(
          ok: false,
          message: _poseError(
            poseLabel,
            'Phat hien nhieu khuon mat, chi de 1 nguoi trong khung hinh.',
          ),
        );
      }

      final detectedFace = detections.first;
      final rect = detectedFace.rect;
      final faceAreaRatio =
          (rect.width * rect.height) / (decoded.width * decoded.height);
      final faceAspectRatio = rect.width / rect.height;
      final minEdge = math.min(rect.width, rect.height);

      if (faceAreaRatio < _minEnrollmentFaceAreaRatio) {
        return EnrollmentFaceCropResult(
          ok: false,
          message: _poseError(
            poseLabel,
            'Khuon mat qua nho, vui long tien lai gan camera hon.',
          ),
          faceAreaRatio: faceAreaRatio,
          faceAspectRatio: faceAspectRatio,
        );
      }

      if (faceAreaRatio > _maxEnrollmentFaceAreaRatio) {
        return EnrollmentFaceCropResult(
          ok: false,
          message: _poseError(
            poseLabel,
            'Khuon mat qua gan camera, vui long lui xa hon mot chut.',
          ),
          faceAreaRatio: faceAreaRatio,
          faceAspectRatio: faceAspectRatio,
        );
      }

      if (faceAspectRatio < _minEnrollmentFaceAspectRatio ||
          faceAspectRatio > _maxEnrollmentFaceAspectRatio) {
        return EnrollmentFaceCropResult(
          ok: false,
          message: _poseError(
            poseLabel,
            'Goc mat chua hop le, vui long chup lai dung huong yeu cau.',
          ),
          faceAreaRatio: faceAreaRatio,
          faceAspectRatio: faceAspectRatio,
        );
      }

      if (minEdge < _minEnrollmentFacePixels) {
        return EnrollmentFaceCropResult(
          ok: false,
          message: _poseError(
            poseLabel,
            'Do phan giai khuon mat qua thap, vui long chup ro hon.',
          ),
          faceAreaRatio: faceAreaRatio,
          faceAspectRatio: faceAspectRatio,
        );
      }

      final crop = _selectRecognitionCrop(
        source: decoded,
        rect: rect,
        detectedFace: detectedFace,
      );
      if (crop == null) {
        return EnrollmentFaceCropResult(
          ok: false,
          message: _poseError(poseLabel, 'Khong cat duoc khuon mat tu anh.'),
          faceAreaRatio: faceAreaRatio,
          faceAspectRatio: faceAspectRatio,
        );
      }

      final sharpness = _imageSharpness(crop);
      if (sharpness < _minTemplateSharpness) {
        return EnrollmentFaceCropResult(
          ok: false,
          message: _poseError(
            poseLabel,
            'Anh mo, vui long giu may on dinh va chup lai.',
          ),
          faceAreaRatio: faceAreaRatio,
          faceAspectRatio: faceAspectRatio,
          sharpness: sharpness,
        );
      }

      final output = Uint8List.fromList(img.encodeJpg(crop, quality: 94));
      return EnrollmentFaceCropResult(
        ok: true,
        message: 'OK',
        imageBytes: output,
        faceAreaRatio: faceAreaRatio,
        faceAspectRatio: faceAspectRatio,
        sharpness: sharpness,
      );
    } catch (e) {
      return EnrollmentFaceCropResult(
        ok: false,
        message: _poseError(poseLabel, 'Detect khuon mat that bai: $e'),
      );
    }
  }

  Future<UploadedImageRecognitionResult> analyzeUploadedImage({
    required Uint8List imageBytes,
    required List<FacePerson> selectedPeople,
    double matchThreshold = 0.55,
    bool compareAgainstWholeGallery = false,
  }) async {
    if (selectedPeople.isEmpty) {
      return UploadedImageRecognitionResult(
        pass: false,
        message: 'Vui long chon it nhat 1 doi tuong can nhan dien.',
        annotatedImageBytes: imageBytes,
        matches: const <UploadedImageRecognitionFaceMatch>[],
        faceDebugInfos: const <UploadedImageRecognitionFaceDebugInfo>[],
        recognizedPersonIds: <String>{},
        missingPersonIds: const <String>[],
        matchThreshold: matchThreshold,
      );
    }

    if (imageBytes.isEmpty) {
      return UploadedImageRecognitionResult(
        pass: false,
        message: 'Anh trong, vui long chon lai.',
        annotatedImageBytes: imageBytes,
        matches: const <UploadedImageRecognitionFaceMatch>[],
        faceDebugInfos: const <UploadedImageRecognitionFaceDebugInfo>[],
        recognizedPersonIds: <String>{},
        missingPersonIds: selectedPeople
            .map((e) => e.id)
            .toList(growable: false),
        matchThreshold: matchThreshold,
      );
    }

    await initialize();
    await refreshTemplates();
    await _ensureFallbackDetectorReady();

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      return UploadedImageRecognitionResult(
        pass: false,
        message: 'Khong doc duoc anh upload.',
        annotatedImageBytes: imageBytes,
        matches: const <UploadedImageRecognitionFaceMatch>[],
        faceDebugInfos: const <UploadedImageRecognitionFaceDebugInfo>[],
        recognizedPersonIds: <String>{},
        missingPersonIds: selectedPeople
            .map((e) => e.id)
            .toList(growable: false),
        matchThreshold: matchThreshold,
      );
    }

    final referencePeople = compareAgainstWholeGallery
        ? await FaceAttendanceRepository.getPeople()
        : selectedPeople;
    final referenceTemplates = await _loadReferenceTemplatesForPeople(
      referencePeople,
    );
    if (referenceTemplates.isEmpty) {
      return UploadedImageRecognitionResult(
        pass: false,
        message: compareAgainstWholeGallery
            ? 'Khong co vector cache hop le trong gallery. Hay rebuild vector cache truoc khi test.'
            : 'Khong co vector cache hop le cho doi tuong da chon. Hay rebuild vector cache truoc khi test.',
        annotatedImageBytes: imageBytes,
        matches: const <UploadedImageRecognitionFaceMatch>[],
        faceDebugInfos: const <UploadedImageRecognitionFaceDebugInfo>[],
        recognizedPersonIds: <String>{},
        missingPersonIds: selectedPeople
            .map((e) => e.id)
            .toList(growable: false),
        matchThreshold: matchThreshold,
      );
    }

    final selectedIds = selectedPeople.map((person) => person.id).toSet();

    final detections = await _detectFacesForFallback(decoded, 'uploaded-image');
    final faces = detections.isNotEmpty
        ? detections
        : <_DetectedFace>[
            _DetectedFace(rect: _centerFallbackRect(decoded), score: 0.2),
          ];

    faces.sort((a, b) {
      final areaA = a.rect.width * a.rect.height * a.score;
      final areaB = b.rect.width * b.rect.height * b.score;
      return areaB.compareTo(areaA);
    });

    final matches = <UploadedImageRecognitionFaceMatch>[];
    final faceDebugInfos = <UploadedImageRecognitionFaceDebugInfo>[];
    final recognizedPersonIds = <String>{};

    for (var faceIndex = 0; faceIndex < faces.length; faceIndex++) {
      final detectedFace = faces[faceIndex];
      final rect = detectedFace.rect;
      if (rect.width <= 1 || rect.height <= 1) {
        continue;
      }

      final originalCrop = _selectRecognitionCrop(
        source: decoded,
        rect: rect,
        detectedFace: detectedFace,
      );
      if (originalCrop == null) {
        continue;
      }

      final cleanedCrop = _prepareFaceForEmbedding(originalCrop);
      final vector = await _embeddingFromImage(
        cleanedCrop,
        alreadyPrepared: true,
        robust: false,
      );
      if (vector.isEmpty) {
        continue;
      }

      final frameQuality = _regionQuality(
        cleanedCrop,
        minSharpness: _minTemplateSharpness * 0.40,
      );
      final partialBundle = await _buildPartialEmbeddingsFromFace(
        cleanedCrop,
        targetDimension: _templateVectorDimension,
        frameQuality: frameQuality,
        forRealtime: false,
        faceAlreadyPrepared: true,
      );
      final topCandidates = _topUploadedImageCandidates(
        vector,
        referenceTemplates,
        partialBundle: partialBundle,
      );
      final top1 = topCandidates.isNotEmpty ? topCandidates.first : null;
      final isRecognized = top1 != null && top1.score >= matchThreshold;
      final recognizedPersonId = isRecognized ? top1.personId : null;
      if (recognizedPersonId != null) {
        recognizedPersonIds.add(recognizedPersonId);
      }

      matches.add(
        UploadedImageRecognitionFaceMatch(
          rect: rect,
          name: isRecognized ? top1.personName : 'Unknown',
          personId: recognizedPersonId,
          score: top1?.score ?? 0.0,
        ),
      );

      final originalBytes = Uint8List.fromList(img.encodePng(originalCrop));
      final cleanedBytes = Uint8List.fromList(img.encodePng(cleanedCrop));
      final vectorNorm = math.sqrt(
        vector.fold<double>(0.0, (sum, value) => sum + value * value),
      );
      faceDebugInfos.add(
        UploadedImageRecognitionFaceDebugInfo(
          faceIndex: faceIndex,
          rect: rect,
          originalFaceBytes: originalBytes,
          cleanedFaceBytes: cleanedBytes,
          vector: vector,
          vectorNorm: vectorNorm,
          detectorScore: detectedFace.score,
          areaRatio:
              (rect.width * rect.height) / (decoded.width * decoded.height),
          aspectRatio: rect.width / rect.height,
          minFacePixels: math.min(rect.width, rect.height).round(),
          originalLuma: _averageLuma(originalCrop),
          cleanedLuma: _averageLuma(cleanedCrop),
          originalSharpness: _imageSharpness(originalCrop),
          cleanedSharpness: _imageSharpness(cleanedCrop),
          matchThreshold: matchThreshold,
          topCandidates: topCandidates,
        ),
      );
    }

    final missingPersonIds = selectedIds
        .where((id) => !recognizedPersonIds.contains(id))
        .toList(growable: false);
    final annotatedImageBytes = _drawUploadedImageAnnotations(decoded, matches);
    final pass = missingPersonIds.isEmpty;
    return UploadedImageRecognitionResult(
      pass: pass,
      message: pass
          ? 'PASS - Da nhan dien du cac doi tuong trong danh sach.'
          : 'FAILED - Con thieu ${missingPersonIds.length} doi tuong trong danh sach.',
      annotatedImageBytes: annotatedImageBytes,
      matches: matches,
      faceDebugInfos: faceDebugInfos,
      recognizedPersonIds: recognizedPersonIds,
      missingPersonIds: missingPersonIds,
      matchThreshold: matchThreshold,
    );
  }

  Future<void> _ensureFallbackDetectorReady() async {
    if (_fallbackDetectorInitialized) return;
    await _fallbackFaceDetector.initialize(model: tfl.FaceDetectionModel.full);
    _fallbackDetectorInitialized = true;
  }

  Future<img.Image?> _resizeWithOpenCvDart(
    img.Image frame,
    int targetWidth,
    int targetHeight,
  ) async {
    // Encode sang Uint8List để dùng OpenCV
    final frameBytes = Uint8List.fromList(img.encodeJpg(frame));

    final mat = await opencv.imdecode(frameBytes, opencv.IMREAD_COLOR);

    final resizedMat = await opencv.resize(
      mat,
      (targetWidth, targetHeight),
      interpolation: opencv.INTER_LINEAR,
    );

    final result = await opencv.imencode('.jpg', resizedMat);

    // Decode lại sang img.Image để trả về
    return img.decodeImage(result.$2);
  }

  Rect _centerFallbackRect(img.Image source) {
    final side = (math.min(source.width, source.height) * 0.62).round();
    final clampedSide = math.max(1, side);
    final left = ((source.width - clampedSide) / 2).round();
    final top = ((source.height - clampedSide) / 2).round();
    return Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      clampedSide.toDouble(),
      clampedSide.toDouble(),
    );
  }

  List<UploadedImageRecognitionCandidateScore> _topUploadedImageCandidates(
    List<double> query,
    List<face_template.FaceTemplate> templates, {
    _PartialEmbeddingBundle? partialBundle,
    int maxItems = 3,
  }) {
    final bucketsByPerson = <String, PersonScoreBucket>{};
    for (final template in templates) {
      final bucket = bucketsByPerson.putIfAbsent(
        template.person.id,
        () => PersonScoreBucket()..person = template.person,
      );
      bucket.addTemplate(template);
    }
    for (final bucket in bucketsByPerson.values) {
      bucket.finalize();
    }

    final ranked = _scoreCandidateBuckets(
      query,
      buckets: bucketsByPerson.values,
      partialBundle: partialBundle,
      frameQuality: 1.0,
    )..sort((a, b) => b.blendedScore.compareTo(a.blendedScore));
    final mapped = ranked
        .map(
          (candidate) => UploadedImageRecognitionCandidateScore(
            personId: candidate.bucket.person.id,
            personName: candidate.bucket.person.name,
            score: candidate.blendedScore,
          ),
        )
        .toList(growable: false);
    if (mapped.length <= maxItems) {
      return mapped;
    }
    return mapped.take(maxItems).toList(growable: false);
  }

  List<_CandidateScore> _scoreCandidateBuckets(
    List<double> vector, {
    required Iterable<PersonScoreBucket> buckets,
    _PartialEmbeddingBundle? partialBundle,
    double frameQuality = 1.0,
  }) {
    final candidates = <_CandidateScore>[];
    final probePartials = partialBundle ?? const _PartialEmbeddingBundle();

    for (final bucket in buckets) {
      if (bucket.templates.isEmpty) continue;

      face_template.FaceTemplate bestTemplate = bucket.templates.first;
      var templateScore = -1.0;
      final templateScores = <double>[];
      for (final template in bucket.templates) {
        final score =
            _debiasedCosine(vector, template.vector) *
            (0.80 + template.quality * 0.20);
        templateScores.add(score);
        if (score > templateScore) {
          templateScore = score;
          bestTemplate = template;
        }
      }

      templateScores.sort((a, b) => b.compareTo(a));
      final topCount = math.min(3, templateScores.length);
      var multiPoseScore = templateScore;
      if (topCount > 0) {
        var sum = 0.0;
        for (var i = 0; i < topCount; i++) {
          sum += templateScores[i];
        }
        multiPoseScore = sum / topCount;
        if (templateScores.length >= 5) {
          final fifth = templateScores[4];
          multiPoseScore = (multiPoseScore * 0.87) + (fifth * 0.13);
        }
      }

      final centroidVector = bucket.centroid;
      final centroidScore = centroidVector == null || centroidVector.isEmpty
          ? 0.0
          : _debiasedCosine(vector, centroidVector);
      var partialWeightedSum = 0.0;
      var partialWeightTotal = 0.0;

      void addPartial(
        List<double>? probeVector,
        List<double>? templateVector,
        double weight,
      ) {
        if (probeVector == null || templateVector == null || weight <= 0) {
          return;
        }
        final sim = _debiasedCosine(probeVector, templateVector);
        partialWeightedSum += sim * weight;
        partialWeightTotal += weight;
      }

      addPartial(
        probePartials.eyeVector,
        bestTemplate.eyeVector,
        probePartials.eyeWeight,
      );
      addPartial(
        probePartials.leftEyeVector,
        bestTemplate.leftEyeVector,
        probePartials.leftEyeWeight,
      );
      addPartial(
        probePartials.rightEyeVector,
        bestTemplate.rightEyeVector,
        probePartials.rightEyeWeight,
      );
      addPartial(
        probePartials.noseVector,
        bestTemplate.noseVector,
        probePartials.noseWeight,
      );
      addPartial(
        probePartials.mouthVector,
        bestTemplate.mouthVector,
        probePartials.mouthWeight,
      );
      addPartial(
        probePartials.foreheadVector,
        bestTemplate.foreheadVector,
        probePartials.foreheadWeight,
      );
      addPartial(
        probePartials.leftCheekVector,
        bestTemplate.leftCheekVector,
        probePartials.leftCheekWeight,
      );
      addPartial(
        probePartials.rightCheekVector,
        bestTemplate.rightCheekVector,
        probePartials.rightCheekWeight,
      );
      addPartial(
        probePartials.chinVector,
        bestTemplate.chinVector,
        probePartials.chinWeight,
      );

      final partialCoverage = probePartials.totalWeight <= 0
          ? 0.0
          : (partialWeightTotal / probePartials.totalWeight)
                .clamp(0.0, 1.0)
                .toDouble();
      final partialScore = partialWeightTotal > 0
          ? (partialWeightedSum / partialWeightTotal)
          : templateScore;

      final structuralScore =
          (templateScore * 0.55 + multiPoseScore * 0.30 + centroidScore * 0.15)
              .clamp(-1.0, 1.0)
              .toDouble();
      final partialMix = (0.32 * partialCoverage).clamp(0.0, 0.32).toDouble();
      final score =
          (structuralScore * (1.0 - partialMix) + partialScore * partialMix)
              .clamp(-1.0, 1.0)
              .toDouble();
      final calibrated = bucket.calibrate(score);
      candidates.add(
        _CandidateScore(
          bucket: bucket,
          template: bestTemplate,
          templateScore: templateScore,
          multiPoseScore: multiPoseScore,
          partialScore: partialScore,
          partialCoverage: partialCoverage,
          centroidScore: centroidScore,
          blendedScore: score,
          calibratedScore: calibrated,
          decisionScore: _candidateDecisionScore(
            _CandidateScore(
              bucket: bucket,
              template: bestTemplate,
              templateScore: templateScore,
              multiPoseScore: multiPoseScore,
              partialScore: partialScore,
              partialCoverage: partialCoverage,
              centroidScore: centroidScore,
              blendedScore: score,
              calibratedScore: calibrated,
              decisionScore: 0.0,
            ),
            frameQuality: frameQuality,
          ),
        ),
      );
    }

    return candidates;
  }

  Future<List<face_template.FaceTemplate>> _loadReferenceTemplatesForPeople(
    List<FacePerson> selectedPeople,
  ) async {
    final templates = <face_template.FaceTemplate>[];
    for (final person in selectedPeople) {
      final cacheEntries =
          await FaceAttendanceRepository.getVectorCacheEntriesForPerson(
            person.id,
          );
      for (final entry in cacheEntries) {
        final template = _templateFromVectorCacheEntry(person, entry);
        if (template != null) {
          templates.add(template);
        }
      }
    }
    return templates;
  }

  face_template.FaceTemplate? _templateFromVectorCacheEntry(
    FacePerson person,
    FaceVectorCacheEntry entry,
  ) {
    final vector = FaceAttendanceRepository.decodeVector(entry.vectorBlob);
    if (vector.isEmpty) return null;

    final baseDimension = vector.length;
    List<double>? normalize(Uint8List? bytes) {
      final decoded = FaceAttendanceRepository.decodeVector(bytes);
      if (decoded.isEmpty) return null;
      final aligned = _alignVectorDimension(decoded, baseDimension);
      return aligned.isEmpty ? null : _normalizeVector(aligned);
    }

    return face_template.FaceTemplate(
      person: person,
      vector: _normalizeVector(vector),
      quality: entry.quality.clamp(0.20, 1.0).toDouble(),
      eyeVector: normalize(entry.eyeVectorBlob),
      leftEyeVector: normalize(entry.leftEyeVectorBlob),
      rightEyeVector: normalize(entry.rightEyeVectorBlob),
      noseVector: normalize(entry.noseVectorBlob),
      mouthVector: normalize(entry.mouthVectorBlob),
      foreheadVector: normalize(entry.foreheadVectorBlob),
      leftCheekVector: normalize(entry.leftCheekVectorBlob),
      rightCheekVector: normalize(entry.rightCheekVectorBlob),
      chinVector: normalize(entry.chinVectorBlob),
    );
  }

  Uint8List _drawUploadedImageAnnotations(
    img.Image source,
    List<UploadedImageRecognitionFaceMatch> matches,
  ) {
    try {
      final annotated = img.Image.from(source);
      for (final match in matches) {
        final color = match.isKnown
            ? img.ColorRgba8(72, 219, 101, 255)
            : img.ColorRgba8(255, 165, 0, 255);
        final left = match.rect.left.floor().clamp(0, annotated.width - 1);
        final top = match.rect.top.floor().clamp(0, annotated.height - 1);
        final right = match.rect.right.ceil().clamp(left, annotated.width - 1);
        final bottom = match.rect.bottom.ceil().clamp(
          top,
          annotated.height - 1,
        );
        _drawRectStrokeManual(
          annotated,
          left: left,
          top: top,
          right: right,
          bottom: bottom,
          color: color,
          thickness: 3,
        );
      }
      return Uint8List.fromList(img.encodePng(annotated));
    } catch (_) {
      return Uint8List.fromList(img.encodePng(source));
    }
  }

  String _poseError(String poseLabel, String message) {
    final pose = poseLabel.trim();
    if (pose.isEmpty) return message;
    return '[$pose] $message';
  }

  void _startTemplateMonitor() {
    _templateMonitorTimer?.cancel();
    _templateMonitorTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_syncTemplatesIfChanged());
    });
  }

  Future<void> _syncTemplatesIfChanged() async {
    if (_templateRefreshBusy) return;
    _templateRefreshBusy = true;
    try {
      final version =
          await FaceAttendanceRepository.getFacePeopleCacheVersion();
      if (version == _lastPeopleCacheVersion) return;
      await _loadTemplates();
      _lastPeopleCacheVersion = version;
      _log.info(
        'Face template cache refreshed version=$version templates=${_templates.length} persons=${PersonScoreBucket().templatesByPersonId.length}',
      );
    } catch (e) {
      _log.error('Face template cache sync failed error=$e');
    } finally {
      _templateRefreshBusy = false;
    }
  }

  Future<void> _ensureMediaPipeProcessors() async {
    if (_faceDetectorProcessor != null &&
        _faceMeshProcessor != null &&
        _faceMeshPipeline != null) {
      return;
    }

    _faceDetectorProcessor ??= await FaceDetectorProcessor.create(
      model: FaceDetectionModel.fullRange,
      delegate: FaceMeshDelegate.xnnpack,
      maxResults: 4,
      roiScaleY: 1.7,
      roiShiftY: -0.2,
    );
    _faceMeshProcessor ??= await FaceMeshProcessor.createForMultiFace(
      delegate: FaceMeshDelegate.xnnpack,
      enableIris: true,
    );
    _faceMeshPipeline ??= FaceMeshInferencePipeline(
      detector: _faceDetectorProcessor!,
      mesh: _faceMeshProcessor!,
    );
  }

  Future<void> _ensureArcFaceSession() async {
    if (_arcFaceAttempted) return;
    _arcFaceAttempted = true;

    for (final asset in _recognizerModelAssets) {
      try {
        _arcFaceSession = await _onnxRuntime.createSessionFromAsset(asset);
        final session = _arcFaceSession;
        if (session != null) {
          if (session.inputNames.isNotEmpty) {
            _arcFaceInputName = session.inputNames.first;
          }
          if (session.outputNames.isNotEmpty) {
            _arcFaceOutputName = session.outputNames.first;
          }
          _log.info('Recognizer model loaded asset=$asset');
          return;
        }
      } catch (_) {
        _arcFaceSession = null;
        continue;
      }
    }
    _log.error('No recognizer ONNX model loaded; fallback vector mode active');
  }

  Future<void> _ensureScrfdSession() async {
    if (_scrfdAttempted) return;
    _scrfdAttempted = true;

    for (final asset in _scrfdModelAssets) {
      try {
        final session = await _onnxRuntime.createSessionFromAsset(asset);
        _scrfdSession = session;
        if (session.inputNames.isNotEmpty) {
          _scrfdInputName = session.inputNames.first;
        }
        _log.info('SCRFD detector loaded asset=$asset');
        return;
      } catch (_) {
        _scrfdSession = null;
        continue;
      }
    }

    _log.info('SCRFD detector unavailable, using tfl fallback detector');
  }

  CameraController? previewControllerFor(String cameraId) =>
      _processorsByCameraId[cameraId]?.controller;

  bool isRunning(String cameraId) =>
      _processorsByCameraId.containsKey(cameraId);

  Future<void> ensureProcessorForCamera(
    String cameraId, {
    int preferredDeviceIndex = 0,
  }) async {
    if (_processorsByCameraId.containsKey(cameraId) ||
        _processorStartingCameraIds.contains(cameraId)) {
      return;
    }
    _processorStartingCameraIds.add(cameraId);

    try {
      if (_availableCameras.isEmpty) {
        _availableCameras = await availableCameras();
        if (_availableCameras.isEmpty) {
          return;
        }
      }

      final safeIndex = preferredDeviceIndex
          .clamp(0, _availableCameras.length - 1)
          .toInt();
      final desc = _availableCameras[safeIndex];
      _log.info(
        'Starting recognition processor camera=$cameraId device=${desc.name} mode=$runtimeModeLabel',
      );
      final controller = CameraController(
        desc,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: _preferredImageFormat(),
      );
      try {
        await controller.initialize();
      } catch (e) {
        _log.error(
          'CameraController initialize failed camera=$cameraId error=$e',
        );
        rethrow;
      }

      final processor = _Processor(controller: controller);
      _processorsByCameraId[cameraId] = processor;

      try {
        if (!controller.supportsImageStreaming()) {
          _streamUnavailableByCameraId[cameraId] = true;
          _log.info(
            'CameraController does not support image streaming camera=$cameraId; using in-memory preview-frame fallback',
          );
          _startStillCaptureFallback(cameraId, processor);
          return;
        }

        _streamUnavailableByCameraId.remove(cameraId);
        _startCameraCalibrationWindow(cameraId);

        await controller.startImageStream((image) {
          _enqueueStreamFrame(cameraId, processor, image);
        });
      } catch (_) {
        _streamUnavailableByCameraId[cameraId] = true;
        _log.info(
          'Failed to start image stream camera=$cameraId; switching to in-memory preview-frame fallback',
        );
        _startStillCaptureFallback(cameraId, processor);
      }
    } finally {
      _processorStartingCameraIds.remove(cameraId);
    }
  }

  Future<void> stopProcessor(String cameraId) async {
    final processor = _processorsByCameraId.remove(cameraId);
    if (processor == null) {
      return;
    }

    if (processor.controller.value.isStreamingImages) {
      await processor.controller.stopImageStream();
    }
    processor.stillCaptureTimer?.cancel();
    processor.stillCaptureTimer = null;
    processor.pendingDrainTimer?.cancel();
    processor.pendingDrainTimer = null;
    processor.pendingFrames.clear();
    await processor.controller.dispose();
    _streamUnavailableByCameraId.remove(cameraId);
    _overlaysByCameraId.remove(cameraId);
    _overlayTracksByCameraId.remove(cameraId);
    _fallbackFaceSkipCountByCameraId.remove(cameraId);
    _fallbackFaceSkipLogAtByCameraId.remove(cameraId);
    _zoneByCameraId.remove(cameraId);
    _spoofStates.removeWhere((key, _) => key.startsWith('$cameraId|'));
    _adaptiveDistanceStates.remove(cameraId);
    _trackStatsByCameraId.remove(cameraId);
    _workerStatsByCameraId.remove(cameraId);
    final window = _calibrationWindows.remove(cameraId);
    window?.timer?.cancel();
    _emitFrame(cameraId, const []);
  }

  void _enqueueStreamFrame(
    String cameraId,
    _Processor processor,
    CameraImage image,
  ) {
    if (!processor.controller.value.isInitialized) return;

    _markInputFrame(processor, DateTime.now().millisecondsSinceEpoch);

    processor.pendingFrames.add(image);
    final maxPending = _singleFlightKeepLatestFrames;
    if (processor.pendingFrames.length > maxPending) {
      final overflow = processor.pendingFrames.length - maxPending;
      processor.pendingFrames.removeRange(0, overflow);
    }
    unawaited(_drainPendingFrames(cameraId, processor));
  }

  Future<void> _drainPendingFrames(
    String cameraId,
    _Processor processor,
  ) async {
    if (processor.draining) return;
    processor.draining = true;
    try {
      while (true) {
        if (!processor.controller.value.isInitialized || processor.busy) {
          return;
        }
        if (processor.pendingFrames.isEmpty) {
          return;
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final waitMs =
            _processFrameIntervalMs - (nowMs - processor.lastProcessAtMs);
        if (waitMs > 0) {
          processor.pendingDrainTimer?.cancel();
          processor.pendingDrainTimer = Timer(
            Duration(milliseconds: waitMs),
            () {
              processor.pendingDrainTimer = null;
              unawaited(_drainPendingFrames(cameraId, processor));
            },
          );
          return;
        }

        final nextFrame = processor.pendingFrames.removeAt(0);
        await _processFrame(cameraId, processor, nextFrame);
      }
    } finally {
      processor.draining = false;
    }
  }

  void _startStillCaptureFallback(String cameraId, _Processor processor) {
    processor.stillCaptureTimer?.cancel();
    final intervalMs = _fallbackCaptureIntervalMs.clamp(50, 5000);
    processor.stillCaptureTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) {
        _markInputFrame(processor, DateTime.now().millisecondsSinceEpoch);
        unawaited(_captureStillFrame(cameraId, processor));
      },
    );
  }

  Future<void> _captureStillFrame(String cameraId, _Processor processor) async {
    if (processor.busy || !processor.controller.value.isInitialized) return;

    processor.busy = true;
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _markRecognitionFrame(processor, nowMs);
      processor.frameCount++;
      final decoded = await _capturePreviewFrameFromWindows(processor);
      if (decoded == null) return;
      final optimizedFrame = _optimizeFallbackFrame(decoded);

      final zone = await _resolveZone(cameraId);
      await _processFallbackImage(
        cameraId,
        zone,
        optimizedFrame,
        frameIndex: processor.frameCount,
      );
    } catch (e, st) {
      final stLine = st.toString().split('\n').first;
      _log.error(
        'Still-image fallback failed camera=$cameraId errorType=${e.runtimeType} error=$e stack=$stLine',
      );
    } finally {
      processor.busy = false;
    }
  }

  img.Image? _optimizeFallbackFrame(img.Image frame) {
    final maxInputEdge = _fallbackMaxInputEdge.clamp(160, 4096);
    final longestEdge = math.max(frame.width, frame.height);
    if (longestEdge <= maxInputEdge) {
      return frame;
    }

    final scale = maxInputEdge / longestEdge;
    final targetWidth = (frame.width * scale).round().clamp(1, frame.width);
    final targetHeight = (frame.height * scale).round().clamp(1, frame.height);
    
    // Resize using image package for better compatibility
    return img.copyResize(frame, width: targetWidth, height: targetHeight);
  }

  Future<RecognitionZone> _resolveZone(String cameraId) async {
    final cachedZone = _zoneByCameraId[cameraId];
    if (cachedZone != null) {
      return cachedZone;
    }

    try {
      final zone = await FaceAttendanceRepository.getZoneByCameraId(cameraId);
      _zoneByCameraId[cameraId] = zone;
      return zone;
    } catch (e) {
      _log.error('Zone load failed camera=$cameraId error=$e');
      final fallback =
          _zoneByCameraId[cameraId] ??
          RecognitionZone.defaults(cameraId: cameraId);
      _zoneByCameraId[cameraId] = fallback;
      return fallback;
    }
  }

  Future<img.Image?> _capturePreviewFrameFromWindows(
    _Processor processor,
  ) async {
    if (!Platform.isWindows) {
      return null;
    }

    final controller = processor.controller;
    final int cameraId = controller.cameraId;
    final Object? response = await _windowsCameraExtChannel
        .invokeMethod<Object?>('getLatestFrameBgra', <String, Object?>{
          'cameraId': cameraId,
        });
    if (response is! Map<Object?, Object?>) {
      return null;
    }

    final Object? bytesRaw = response['bytes'];
    final Object? widthRaw = response['width'];
    final Object? heightRaw = response['height'];
    if (bytesRaw == null || widthRaw == null || heightRaw == null) {
      return null;
    }

    final int width = (widthRaw as num).toInt();
    final int height = (heightRaw as num).toInt();
    if (width <= 0 || height <= 0) {
      return null;
    }

    final Uint8List bytes = bytesRaw is Uint8List
        ? bytesRaw
        : Uint8List.fromList((bytesRaw as List<Object?>).cast<int>());
    if (bytes.length < width * height * 4) {
      return null;
    }

    final output = img.Image(width: width, height: height);
    var index = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final b = bytes[index];
        final g = bytes[index + 1];
        final r = bytes[index + 2];
        final a = bytes[index + 3];
        output.setPixelRgba(x, y, r, g, b, a);
        index += 4;
      }
    }
    return output;
  }

  Future<void> stopAllProcessors() async {
    final ids = _processorsByCameraId.keys.toList(growable: false);
    for (final id in ids) {
      await stopProcessor(id);
    }
  }

  Future<void> _loadTemplates() async {
    final people = await FaceAttendanceRepository.getPeople();
    final peopleById = {for (final person in people) person.id: person};
    final cacheEntries = await FaceAttendanceRepository.getVectorCacheEntries();
    final result = <face_template.FaceTemplate>[];
    final byPerson = <String, PersonScoreBucket>{};
    var inferredDim = 0;

    for (final person in people) {
      byPerson.putIfAbsent(person.id, () => PersonScoreBucket()..person = person);
    }

    for (final entry in cacheEntries) {
      final person = peopleById[entry.personId];
      if (person == null) continue;

      final vector = FaceAttendanceRepository.decodeVector(entry.vectorBlob);
      if (vector.isEmpty) continue;
      if (inferredDim == 0) {
        inferredDim = vector.length;
      }

      final alignedVector = _alignVectorDimension(vector, inferredDim);
      if (alignedVector.isEmpty) continue;
      final normalizedVector = _normalizeVector(alignedVector);
      if (normalizedVector.isEmpty) continue;

      final eyeVector = _alignVectorDimension(
        FaceAttendanceRepository.decodeVector(entry.eyeVectorBlob),
        inferredDim,
      );
      final leftEyeVector = _alignVectorDimension(
        FaceAttendanceRepository.decodeVector(entry.leftEyeVectorBlob),
        inferredDim,
      );
      final rightEyeVector = _alignVectorDimension(
        FaceAttendanceRepository.decodeVector(entry.rightEyeVectorBlob),
        inferredDim,
      );
      final noseVector = _alignVectorDimension(
        FaceAttendanceRepository.decodeVector(entry.noseVectorBlob),
        inferredDim,
      );
      final mouthVector = _alignVectorDimension(
        FaceAttendanceRepository.decodeVector(entry.mouthVectorBlob),
        inferredDim,
      );
      final foreheadVector = _alignVectorDimension(
        FaceAttendanceRepository.decodeVector(entry.foreheadVectorBlob),
        inferredDim,
      );
      final leftCheekVector = _alignVectorDimension(
        FaceAttendanceRepository.decodeVector(entry.leftCheekVectorBlob),
        inferredDim,
      );
      final rightCheekVector = _alignVectorDimension(
        FaceAttendanceRepository.decodeVector(entry.rightCheekVectorBlob),
        inferredDim,
      );
      final chinVector = _alignVectorDimension(
        FaceAttendanceRepository.decodeVector(entry.chinVectorBlob),
        inferredDim,
      );
      final normalizedEyeVector = eyeVector.isEmpty
          ? null
          : _normalizeVector(eyeVector);
      final normalizedLeftEyeVector = leftEyeVector.isEmpty
          ? null
          : _normalizeVector(leftEyeVector);
      final normalizedRightEyeVector = rightEyeVector.isEmpty
          ? null
          : _normalizeVector(rightEyeVector);
      final normalizedNoseVector = noseVector.isEmpty
          ? null
          : _normalizeVector(noseVector);
      final normalizedMouthVector = mouthVector.isEmpty
          ? null
          : _normalizeVector(mouthVector);
      final normalizedForeheadVector = foreheadVector.isEmpty
          ? null
          : _normalizeVector(foreheadVector);
      final normalizedLeftCheekVector = leftCheekVector.isEmpty
          ? null
          : _normalizeVector(leftCheekVector);
      final normalizedRightCheekVector = rightCheekVector.isEmpty
          ? null
          : _normalizeVector(rightCheekVector);
      final normalizedChinVector = chinVector.isEmpty
          ? null
          : _normalizeVector(chinVector);

      final template = face_template.FaceTemplate(
        person: person,
        vector: normalizedVector,
        quality: entry.quality.clamp(0.20, 1.0).toDouble(),
        eyeVector: normalizedEyeVector,
        leftEyeVector: normalizedLeftEyeVector,
        rightEyeVector: normalizedRightEyeVector,
        noseVector: normalizedNoseVector,
        mouthVector: normalizedMouthVector,
        foreheadVector: normalizedForeheadVector,
        leftCheekVector: normalizedLeftCheekVector,
        rightCheekVector: normalizedRightCheekVector,
        chinVector: normalizedChinVector,
      );
      result.add(template);
      byPerson[person.id]!.addTemplate(template);
    }

    final missingPeople = <String>[];
    for (final person in people) {
      final bucket = byPerson[person.id]!;
      if (bucket.templates.isEmpty) {
        missingPeople.add(person.name);
        _log.debug('Vector cache missing person=${person.name}');
      }
    }

    _missingTemplatePeopleCount = missingPeople.length;
    _missingTemplatePeoplePreview = missingPeople.take(5).join(', ');
    final shouldBlockKnown = people.isNotEmpty && missingPeople.isNotEmpty;
    if (shouldBlockKnown != _knownRecognitionBlockedByMissingTemplateCache) {
      if (shouldBlockKnown) {
        _log.error(
          'Known recognition degraded: missing vector cache for '
          '${missingPeople.length}/${people.length} people '
          'sample=[$_missingTemplatePeoplePreview]',
        );
      } else {
        _log.info(
          'Known recognition normal: all registered people have vector cache',
        );
      }
    }
    _knownRecognitionBlockedByMissingTemplateCache = shouldBlockKnown;

    _templates
      ..clear()
      ..addAll(result);
    _templateVectorDimension = inferredDim;
    _globalMeanDirection = _computeGlobalMeanDirection(result);
    PersonScoreBucket().templatesByPersonId
      ..clear()
      ..addAll(byPerson);
    HnswVectorIndex().build(
      result,
      m: _hnswM,
      efConstruction: _hnswEfConstruction,
      efSearchBase: _hnswEfSearch,
    );

    for (final bucket in PersonScoreBucket().templatesByPersonId.values) {
      bucket.finalize();
    }

    if (PersonScoreBucket().templatesByPersonId.length >= 2) {
      final centroids = PersonScoreBucket().templatesByPersonId.values
          .where(
            (bucket) => bucket.centroid != null && bucket.centroid!.isNotEmpty,
          )
          .toList(growable: false);
      if (centroids.length >= 2) {
        var minInter = 1.0;
        var maxInter = -1.0;
        var sumInter = 0.0;
        var pairs = 0;
        for (var i = 0; i < centroids.length; i++) {
          for (var j = i + 1; j < centroids.length; j++) {
            final sim = _debiasedCosine(
              centroids[i].centroid!,
              centroids[j].centroid!,
            );
            if (sim < minInter) minInter = sim;
            if (sim > maxInter) maxInter = sim;
            sumInter += sim;
            pairs++;
          }
        }
        if (pairs > 0) {
          _log.info(
            'Template separability centroids count=${centroids.length} '
            'inter(min=${minInter.toStringAsFixed(3)} '
            'avg=${(sumInter / pairs).toStringAsFixed(3)} '
            'max=${maxInter.toStringAsFixed(3)})',
          );
        }
      }
    }

    final buckets = PersonScoreBucket().templatesByPersonId.values.toList(growable: false);
    for (final bucket in buckets) {
      final c = bucket.centroid;
      if (c == null || c.isEmpty) {
        bucket.interClassMean = 0.78;
        bucket.interClassStd = 0.10;
        continue;
      }

      final sims = <double>[];
      for (final other in buckets) {
        if (other.person.id == bucket.person.id) continue;
        final oc = other.centroid;
        if (oc == null || oc.isEmpty) continue;
        sims.add(_debiasedCosine(c, oc));
      }

      if (sims.isEmpty) {
        bucket.interClassMean = 0.78;
        bucket.interClassStd = 0.10;
        continue;
      }

      final mean = sims.reduce((a, b) => a + b) / sims.length;
      var variance = 0.0;
      for (final s in sims) {
        final d = s - mean;
        variance += d * d;
      }
      variance /= sims.length;

      bucket.interClassMean = mean;
      bucket.interClassStd = math.sqrt(variance).clamp(0.015, 0.25);
    }
  }

  Future<List<FaceVectorCacheEntry>> _buildVectorCacheEntriesForPerson(
    FacePerson person,
  ) async {
    final cacheEntries = <FaceVectorCacheEntry>[];
    final encodedImages =
        <
          ({
            String sourceId,
            String sourceType,
            String preferredEncoded,
            String fallbackEncoded,
          })
        >[];

    final primaryCrop = person.imageCropBase64.trim();
    final primaryRaw = person.imageBase64.trim();
    if (primaryCrop.isNotEmpty || primaryRaw.isNotEmpty) {
      encodedImages.add((
        sourceId: person.id,
        sourceType: 'primary',
        preferredEncoded: primaryCrop.isNotEmpty ? primaryCrop : primaryRaw,
        fallbackEncoded: primaryRaw,
      ));
    }

    final extraImages = await FaceAttendanceRepository.getPersonImages(
      person.id,
    );
    for (final image in extraImages) {
      final cropped = image.imageCropBase64.trim();
      final raw = image.imageBase64.trim();
      if (cropped.isEmpty && raw.isEmpty) continue;
      encodedImages.add((
        sourceId: image.id,
        sourceType: 'extra',
        preferredEncoded: cropped.isNotEmpty ? cropped : raw,
        fallbackEncoded: raw,
      ));
    }

    for (final item in encodedImages) {
      var entry = await _buildVectorCacheEntryFromEncodedImage(
        personId: person.id,
        sourceId: item.sourceId,
        sourceType: item.sourceType,
        encodedImage: item.preferredEncoded,
      );

      // Legacy or bad cropped blobs can be unusable while original image is fine.
      // Retry once with raw source bytes before giving up this slot.
      final rawFallback = item.fallbackEncoded.trim();
      final usedPreferred = item.preferredEncoded.trim();
      if (entry == null &&
          rawFallback.isNotEmpty &&
          rawFallback != usedPreferred) {
        if (_detailedScoreVectorLogging) {
          _log.debug(
            'VectorBuild retry personId=${person.id} sourceId=${item.sourceId} sourceType=${item.sourceType} reason=fallback_to_raw',
          );
        }
        entry = await _buildVectorCacheEntryFromEncodedImage(
          personId: person.id,
          sourceId: item.sourceId,
          sourceType: item.sourceType,
          encodedImage: rawFallback,
        );
      }

      if (entry != null) {
        cacheEntries.add(entry);
      }
    }

    return cacheEntries;
  }

  Future<FaceVectorCacheEntry?> _buildVectorCacheEntryFromEncodedImage({
    required String personId,
    required String sourceId,
    required String sourceType,
    required String encodedImage,
  }) async {
    if (encodedImage.trim().isEmpty) return null;
    try {
      final bytes = base64Decode(encodedImage);
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final detections = await _detectFacesForStaticRecognition(
        decoded,
        contextKey: 'vector-cache-$personId-$sourceType',
      );
      if (detections.isEmpty) {
        if (_detailedScoreVectorLogging) {
          _log.debug(
            'VectorBuild skipped personId=$personId sourceId=$sourceId sourceType=$sourceType '
            'reason=no_face_detected',
          );
        }
        return null;
      }
      if (detections.length > 1) {
        if (_detailedScoreVectorLogging) {
          _log.debug(
            'VectorBuild skipped personId=$personId sourceId=$sourceId sourceType=$sourceType '
            'reason=multiple_faces count=${detections.length}',
          );
        }
        return null;
      }

      final detectedFace = detections.first;
      final faceCrop = _selectRecognitionCrop(
        source: decoded,
        rect: detectedFace.rect,
        detectedFace: detectedFace,
      );
      if (faceCrop == null) {
        if (_detailedScoreVectorLogging) {
          _log.debug(
            'VectorBuild skipped personId=$personId sourceId=$sourceId sourceType=$sourceType '
            'reason=crop_failed',
          );
        }
        return null;
      }

      final prepared = _prepareFaceForEmbedding(faceCrop);
      final sharpness = _imageSharpness(prepared);
      final templateSharpnessFloor = (_minTemplateSharpness * 0.70).clamp(
        16.0,
        _minTemplateSharpness,
      );
      if (sharpness < templateSharpnessFloor) {
        if (_detailedScoreVectorLogging) {
          _log.debug(
            'VectorBuild skipped personId=$personId sourceId=$sourceId sourceType=$sourceType '
            'reason=sharpness sharpness=${sharpness.toStringAsFixed(2)} '
            'required=${templateSharpnessFloor.toStringAsFixed(2)}',
          );
        }
        return null;
      }

      final vector = await _embeddingFromImage(
        prepared,
        alreadyPrepared: true,
        robust: true,
      );
      if (vector.isEmpty) {
        if (_detailedScoreVectorLogging) {
          _log.debug(
            'VectorBuild skipped personId=$personId sourceId=$sourceId sourceType=$sourceType '
            'reason=empty_vector',
          );
        }
        return null;
      }

      final faceMap = await _buildPartialEmbeddingsFromFace(
        prepared,
        targetDimension: vector.length,
        faceAlreadyPrepared: true,
      );
      final quality = (sharpness / _minTemplateSharpness)
          .clamp(0.20, 1.0)
          .toDouble();
      if (_detailedScoreVectorLogging) {
        _log.debug(
          'VectorBuild personId=$personId sourceId=$sourceId sourceType=$sourceType '
          'sharpness=${sharpness.toStringAsFixed(2)} quality=${quality.toStringAsFixed(3)} '
          'vector=${_vectorStats(vector)} preview=${_vectorPreview(vector)} '
          'eye=${faceMap.eyeVector == null ? 'none' : _vectorStats(faceMap.eyeVector!)} '
          'leftEye=${faceMap.leftEyeVector == null ? 'none' : _vectorStats(faceMap.leftEyeVector!)} '
          'rightEye=${faceMap.rightEyeVector == null ? 'none' : _vectorStats(faceMap.rightEyeVector!)} '
          'nose=${faceMap.noseVector == null ? 'none' : _vectorStats(faceMap.noseVector!)} '
          'mouth=${faceMap.mouthVector == null ? 'none' : _vectorStats(faceMap.mouthVector!)} '
          'forehead=${faceMap.foreheadVector == null ? 'none' : _vectorStats(faceMap.foreheadVector!)} '
          'leftCheek=${faceMap.leftCheekVector == null ? 'none' : _vectorStats(faceMap.leftCheekVector!)} '
          'rightCheek=${faceMap.rightCheekVector == null ? 'none' : _vectorStats(faceMap.rightCheekVector!)} '
          'chin=${faceMap.chinVector == null ? 'none' : _vectorStats(faceMap.chinVector!)}',
        );
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      return FaceVectorCacheEntry(
        sourceId: sourceId,
        personId: personId,
        sourceType: sourceType,
        vectorBlob: FaceAttendanceRepository.encodeVector(vector),
        eyeVectorBlob: faceMap.eyeVector == null
            ? null
            : FaceAttendanceRepository.encodeVector(faceMap.eyeVector!),
        noseVectorBlob: faceMap.noseVector == null
            ? null
            : FaceAttendanceRepository.encodeVector(faceMap.noseVector!),
        mouthVectorBlob: faceMap.mouthVector == null
            ? null
            : FaceAttendanceRepository.encodeVector(faceMap.mouthVector!),
        foreheadVectorBlob: faceMap.foreheadVector == null
            ? null
            : FaceAttendanceRepository.encodeVector(faceMap.foreheadVector!),
        leftEyeVectorBlob: faceMap.leftEyeVector == null
            ? null
            : FaceAttendanceRepository.encodeVector(faceMap.leftEyeVector!),
        rightEyeVectorBlob: faceMap.rightEyeVector == null
            ? null
            : FaceAttendanceRepository.encodeVector(faceMap.rightEyeVector!),
        leftCheekVectorBlob: faceMap.leftCheekVector == null
            ? null
            : FaceAttendanceRepository.encodeVector(faceMap.leftCheekVector!),
        rightCheekVectorBlob: faceMap.rightCheekVector == null
            ? null
            : FaceAttendanceRepository.encodeVector(faceMap.rightCheekVector!),
        chinVectorBlob: faceMap.chinVector == null
            ? null
            : FaceAttendanceRepository.encodeVector(faceMap.chinVector!),
        quality: quality,
        createdAt: now,
        updatedAt: now,
      );
    } catch (e, st) {
      if (_detailedScoreVectorLogging) {
        _log.debug(
          'VectorBuild error personId=$personId sourceId=$sourceId sourceType=$sourceType '
          'errorType=${e.runtimeType} error=$e stack=${st.toString().split('\n').first}',
        );
      }
      return null;
    }
  }

  Future<void> _processFrame(
    String cameraId,
    _Processor processor,
    CameraImage image,
  ) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    _markRecognitionFrame(processor, nowMs);
    processor.lastProcessAtMs = nowMs;
    processor.frameCount++;

    processor.busy = true;
    try {
      final zone = await _resolveZone(cameraId);
      if (!zone.enabled) {
        _overlaysByCameraId[cameraId] = const [];
        _overlayTracksByCameraId.remove(cameraId);
        _emitFrame(cameraId, const []);
        return;
      }

      if (_supportsNativeFacePipeline) {
        final rgb = _cameraImageToRgb(image);
        if (rgb == null) {
          return;
        }

        final resizedForDetector = await _resizeWithOpenCvDart(
          rgb,
          _detectorInputWidth,
          _detectorInputHeight,
        );
        final frameInput = _buildMediaPipeFrameFromRgb(
          resizedForDetector!,
          rotationDegrees: _rotationDegreesFor(cameraId, image),
        );
        if (frameInput == null) {
          return;
        }

        final inference = await _runMediaPipeInference(frameInput);
        final faces = inference?.meshResults ?? const <FaceMeshResult>[];
        final previousTracks =
            _overlayTracksByCameraId[cameraId] ??
            const <String, _CameraTrack>{};
        final trackStats = _statsForCamera(cameraId, nowMs);

        final overlays = <FaceOverlayBox>[];
        final nextTracks = <String, _CameraTrack>{};
        final pendingRecognitions = <_NativePendingRecognition>[];
        for (final f in faces) {
          final detectorRect = f.boundingRect(
            targetSize: Size(
              _detectorInputWidth.toDouble(),
              _detectorInputHeight.toDouble(),
            ),
          );
          final ratio = Rect.fromLTWH(
            (detectorRect.left / _detectorInputWidth).clamp(0.0, 1.0),
            (detectorRect.top / _detectorInputHeight).clamp(0.0, 1.0),
            (detectorRect.width / _detectorInputWidth).clamp(0.0, 1.0),
            (detectorRect.height / _detectorInputHeight).clamp(0.0, 1.0),
          );

          if (!_isInsideZone(ratio, zone)) {
            continue;
          }

          final pose = _estimateFacePoseDegrees(f);

          final tracked = _resolveTrackedTrack(previousTracks, ratio, nowMs);
          if (tracked == null && _hasLiveTracks(previousTracks, nowMs)) {
            trackStats.onRefresh(_TrackReuseRejectReason.association);
          }
          final rejectReason = tracked == null
              ? _TrackReuseRejectReason.association
              : _trackReuseRejectReason(
                  track: tracked.$2,
                  currentRatio: ratio,
                  currentYawDeg: pose.$1,
                  currentPitchDeg: pose.$2,
                  nowMs: nowMs,
                  relaxedAssociation: tracked.$3 < _trackAssociationMinScore,
                );
          final relaxedAssociation =
              tracked != null && tracked.$3 < _trackAssociationMinScore;
          if (tracked != null && rejectReason == null) {
            trackStats.onReuse();
            final reusedEvent = _refreshTrackedEvent(
              cameraId,
              tracked.$2.event,
              nowMs,
            );
            final smoothedRatio = _smoothTrackedRatio(
              previousTracks[tracked.$1]?.currentRect,
              ratio,
            );
            nextTracks[tracked.$1] = _CameraTrack(
              key: tracked.$1,
              currentRect: smoothedRatio,
              targetRect: smoothedRatio,
              event: reusedEvent,
              lastSeenAt: nowMs,
              lastRecognitionAt: tracked.$2.lastRecognitionAt,
              lastTrackingConfidence: tracked.$3,
              lastYawDeg: pose.$1,
              lastPitchDeg: pose.$2,
              reuseCount: tracked.$2.reuseCount + 1,
              cachedEmbedding: tracked.$2.cachedEmbedding,
              cachedEmbeddingAtMs: tracked.$2.cachedEmbeddingAtMs,
            );
            overlays.add(
              FaceOverlayBox(
                trackKey: tracked.$1,
                rectRatio: smoothedRatio,
                event: reusedEvent,
                debugLabel: _debugRealtimeOverlay
                    ? 'cache:${tracked.$2.reuseCount + 1}'
                    : null,
              ),
            );
            _publishRecognitionEvent(
              cameraId,
              smoothedRatio,
              reusedEvent,
              nowMs,
            );
            continue;
          }
          if (tracked != null && rejectReason != null) {
            trackStats.onRefresh(rejectReason);
          }

          final rect = _rectFromRatio(ratio, rgb.width, rgb.height);
          if (rect.width <= 1 || rect.height <= 1) {
            continue;
          }

          final faceAreaRatio =
              (rect.width * rect.height) / (rgb.width * rgb.height);
          final minFacePixels = math.min(rect.width, rect.height).round();
          final adaptiveFarDistance = _updateAdaptiveFarDistanceMode(
            cameraId,
            faceAreaRatio,
            minFacePixels,
            nowMs,
          );
          final crop = _realtimeCropFacesFromCameraImage
              ? (_cameraImageFaceToRgb(image, rect) ??
                    _selectRecognitionCrop(source: rgb, rect: rect, mesh: f))
              : _selectRecognitionCrop(source: rgb, rect: rect, mesh: f);
          if (crop == null) continue;

          var workingCrop = crop;
          var luminance = _robustFaceLuminance(workingCrop);
          if (luminance < 0.34) {
            workingCrop = _boostRealtimeFaceExposure(workingCrop, luminance);
            luminance = _robustFaceLuminance(workingCrop);
          }
          workingCrop = _applyRealtimeInputProcessing(workingCrop);
          luminance = _robustFaceLuminance(workingCrop);
          final preSharpnessQuality = (_imageSharpness(workingCrop) / 140.0)
              .clamp(0.0, 1.0)
              .toDouble();
          final preLumaStdDev = _lumaStdDev(workingCrop, luminance);
          final autoSharpenAmount = _computeRealtimeAutoSharpenAmount(
            sharpnessQuality: preSharpnessQuality,
            lumaStdDev: preLumaStdDev,
          );
          workingCrop = _applyAutoTuneRealtimeInputProcessing(
            workingCrop,
            autoSharpenAmount,
          );
          luminance = _robustFaceLuminance(workingCrop);
          final sharpnessQuality = (_imageSharpness(workingCrop) / 140.0)
              .clamp(0.0, 1.0)
              .toDouble();
          final regionQuality = _regionQuality(
            workingCrop,
            minSharpness:
                _minTemplateSharpness * (adaptiveFarDistance ? 0.35 : 0.45),
          );
          final frameQuality = math
              .min(sharpnessQuality, regionQuality)
              .clamp(0.0, 1.0)
              .toDouble();
          final spoofAssessment = _assessSpoof(
            cameraId,
            '${(ratio.center.dx * 100).round()}_${(ratio.center.dy * 100).round()}',
            rectRatio: ratio,
            mesh: f,
            crop: workingCrop,
            frameQuality: frameQuality,
            nowMs: nowMs,
          );
          if (spoofAssessment.isSpoof) {
            final spoofEvent = RecognitionEvent(
              id: _uuid.v4(),
              personName: 'Anh gia mao',
              cameraId: cameraId,
              confidence: (1.0 - spoofAssessment.score).clamp(0.30, 0.99),
              isStranger: true,
              createdAt: nowMs,
            );
            final spoofKey = _matchTrackKey(
              cameraId,
              ratio,
              spoofEvent,
              nextTracks,
            );
            final smoothedSpoofRatio = _smoothTrackedRatio(
              previousTracks[spoofKey]?.currentRect,
              ratio,
            );
            final spoofDebugLabel = _debugRealtimeOverlay
                ? 'spoof:${spoofAssessment.score.toStringAsFixed(2)} ${spoofAssessment.reason}'
                : null;
            nextTracks[spoofKey] = _CameraTrack(
              key: spoofKey,
              currentRect: smoothedSpoofRatio,
              targetRect: smoothedSpoofRatio,
              event: spoofEvent,
              lastSeenAt: nowMs,
              lastRecognitionAt: nowMs,
              lastTrackingConfidence: _associationTrackingConfidence(
                previousTracks[spoofKey]?.currentRect,
                ratio,
              ),
              lastYawDeg: pose.$1,
              lastPitchDeg: pose.$2,
              cachedEmbedding: null,
              cachedEmbeddingAtMs: 0,
            );
            overlays.add(
              FaceOverlayBox(
                trackKey: spoofKey,
                rectRatio: smoothedSpoofRatio,
                event: spoofEvent,
                debugLabel: spoofDebugLabel,
              ),
            );
            _publishRecognitionEvent(
              cameraId,
              smoothedSpoofRatio,
              spoofEvent,
              nowMs,
              eventBuilder: () =>
                  _buildEventWithSnapshot(spoofEvent, rgb: rgb, rect: rect),
            );
            continue;
          }
          pendingRecognitions.add(
            _NativePendingRecognition(
              tracked: tracked,
              ratio: ratio,
              rect: rect,
              pose: pose,
              relaxedAssociation: relaxedAssociation,
              minFacePixels: minFacePixels,
              faceAreaRatio: faceAreaRatio,
              adaptiveFarDistance: adaptiveFarDistance,
              frameQuality: frameQuality,
              spoofScore: spoofAssessment.score,
              workingCrop: workingCrop,
            ),
          );
        }

        if (pendingRecognitions.isNotEmpty) {
          final concurrencyRun =
              await _runWithMaxConcurrency<
                _NativePendingRecognition,
                _NativeComputedRecognition?
              >(
                pendingRecognitions,
                _faceMeshMaxWorkers,
                (pending) => _computeNativeRecognitionCandidate(
                  pending,
                  nowMs: nowMs,
                  frameIndex: processor.frameCount,
                ),
              );
          _updateWorkerStats(
            cameraId,
            configuredWorkers: _faceMeshMaxWorkers,
            run: concurrencyRun,
          );

          for (final computed in concurrencyRun.results) {
            if (computed == null) {
              continue;
            }

            final pending = computed.pending;
            final tracked = pending.tracked;
            final vector = computed.vector;
            final partialBundle = computed.partialBundle;
            final faceLogKey =
                tracked?.$1 ?? _faceLogKeyFromRatio(pending.ratio);
            final assignedKnownIds = nextTracks.values
                .map((track) => track.event.personId)
                .whereType<String>()
                .toSet();
            final match = _findBestMatch(
              vector,
              partialBundle: partialBundle,
              excludedPersonIds: assignedKnownIds,
              frameQuality: pending.frameQuality,
              cameraId: cameraId,
              faceLogKey: faceLogKey,
            );
            final effectiveKnown = match != null;
            _logRealtimeDecisionTrace(
              cameraId: cameraId,
              faceLogKey: faceLogKey,
              match: match,
              isKnown: effectiveKnown,
              frameQuality: pending.frameQuality,
            );
            final acceptedMatch = effectiveKnown ? match : null;
            final debugLabel = _debugRealtimeOverlay
                ? _buildRealtimeDebugLabel(
                    match: match,
                    frameQuality: pending.frameQuality,
                    spoofScore: pending.spoofScore,
                  )
                : null;
            final confidence =
                (acceptedMatch != null
                        ? acceptedMatch.score.clamp(0.0, 0.99)
                        : _strangerConfidence(
                            match: match,
                            frameQuality: pending.frameQuality,
                          ))
                    .toDouble();
            final event = _buildRecognitionEvent(
              cameraId,
              acceptedMatch,
              nowMs,
              unknownConfidence: confidence,
            );

            final key = _matchTrackKey(
              cameraId,
              pending.ratio,
              event,
              nextTracks,
            );
            final smoothedRatio = _smoothTrackedRatio(
              previousTracks[key]?.currentRect,
              pending.ratio,
            );
            final persistEmbedding = !event.isStranger;
            nextTracks[key] = _CameraTrack(
              key: key,
              currentRect: smoothedRatio,
              targetRect: smoothedRatio,
              event: event,
              lastSeenAt: nowMs,
              lastRecognitionAt: nowMs,
              lastTrackingConfidence: _associationTrackingConfidence(
                previousTracks[key]?.currentRect,
                pending.ratio,
              ),
              lastYawDeg: pending.pose.$1,
              lastPitchDeg: pending.pose.$2,
              cachedEmbedding: persistEmbedding
                  ? List<double>.from(vector, growable: false)
                  : null,
              cachedEmbeddingAtMs: persistEmbedding ? nowMs : 0,
            );
            overlays.add(
              FaceOverlayBox(
                trackKey: key,
                rectRatio: smoothedRatio,
                event: event,
                debugLabel: debugLabel,
              ),
            );
            _publishRecognitionEvent(
              cameraId,
              smoothedRatio,
              event,
              nowMs,
              eventBuilder: () =>
                  _buildEventWithSnapshot(event, rgb: rgb, rect: pending.rect),
            );
          }
        }

        _overlayTracksByCameraId[cameraId] = nextTracks;
        _overlaysByCameraId[cameraId] = overlays;
        final annotatedOverlayPng = _maybeBuildOverlayPng(
          processor,
          rgb,
          overlays,
          zone,
          nowMs,
        );
        _emitFrameWithImage(
          cameraId,
          overlays,
          trackStats: trackStats.snapshot(),
          workerStats: _workerStatsForCamera(cameraId),
          annotatedOverlayPng: annotatedOverlayPng,
        );
        if (_traceLogsEnabled && processor.frameCount % 60 == 0) {
          _log.debug(
            'Processed frame camera=$cameraId overlays=${overlays.length} mode=$runtimeModeLabel',
          );
        }
      } else {
        final rgb = _cameraImageToRgb(image);
        if (rgb == null) return;
        await _processFallbackImage(
          cameraId,
          zone,
          rgb,
          frameIndex: processor.frameCount,
        );
      }
    } catch (_) {
      // Keep frame pipeline alive when one frame fails.
      if (processor.frameCount % 60 == 0) {
        _log.error(
          'Frame processing failed camera=$cameraId mode=$runtimeModeLabel',
        );
      }
    } finally {
      processor.busy = false;
    }
  }

  Future<void> _processFallbackImage(
    String cameraId,
    RecognitionZone zone,
    img.Image? rgb, {
    int frameIndex = 0,
  }) async {
    if (rgb == null) return;
    try {
      final detections = await _detectFacesForFallback(rgb, cameraId);
      final filteredDetections = _filterFallbackDetectionsForRealtime(
        detections,
        frameWidth: rgb.width,
        frameHeight: rgb.height,
      );
      final overlays = <FaceOverlayBox>[];
      final nextTracks = <String, _CameraTrack>{};
      final previousTracks =
          _overlayTracksByCameraId[cameraId] ?? const <String, _CameraTrack>{};
      final frameNowMs = DateTime.now().millisecondsSinceEpoch;
      final trackStats = _statsForCamera(cameraId, frameNowMs);
      final pendingRecognitions = <_FallbackPendingRecognition>[];
      for (final detected in filteredDetections) {
        try {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final rect = detected.rect;
          if (rect.width <= 1 || rect.height <= 1) {
            continue;
          }
          final faceAreaRatio =
              (rect.width * rect.height) / (rgb.width * rgb.height);
          final minFacePixels = math.min(rect.width, rect.height).round();
          final adaptiveFarDistance = _updateAdaptiveFarDistanceMode(
            cameraId,
            faceAreaRatio,
            minFacePixels,
            nowMs,
          );
          final ratio = Rect.fromLTWH(
            (rect.left / rgb.width).clamp(0.0, 1.0),
            (rect.top / rgb.height).clamp(0.0, 1.0),
            (rect.width / rgb.width).clamp(0.0, 1.0),
            (rect.height / rgb.height).clamp(0.0, 1.0),
          );

          if (!_isInsideZone(ratio, zone)) continue;

          final tracked = _resolveTrackedTrack(previousTracks, ratio, nowMs);
          if (tracked == null && _hasLiveTracks(previousTracks, nowMs)) {
            trackStats.onRefresh(_TrackReuseRejectReason.association);
          }
          final rejectReason = tracked == null
              ? _TrackReuseRejectReason.association
              : _trackReuseRejectReason(
                  track: tracked.$2,
                  currentRatio: ratio,
                  nowMs: nowMs,
                  relaxedAssociation: tracked.$3 < _trackAssociationMinScore,
                );
          final relaxedAssociation =
              tracked != null && tracked.$3 < _trackAssociationMinScore;
          if (tracked != null && rejectReason == null) {
            trackStats.onReuse();
            final reusedEvent = _refreshTrackedEvent(
              cameraId,
              tracked.$2.event,
              nowMs,
            );
            final smoothedRatio = _smoothTrackedRatio(
              previousTracks[tracked.$1]?.currentRect,
              ratio,
            );
            nextTracks[tracked.$1] = _CameraTrack(
              key: tracked.$1,
              currentRect: smoothedRatio,
              targetRect: smoothedRatio,
              event: reusedEvent,
              lastSeenAt: nowMs,
              lastRecognitionAt: tracked.$2.lastRecognitionAt,
              lastTrackingConfidence: tracked.$3,
              lastYawDeg: tracked.$2.lastYawDeg,
              lastPitchDeg: tracked.$2.lastPitchDeg,
              reuseCount: tracked.$2.reuseCount + 1,
              cachedEmbedding: tracked.$2.cachedEmbedding,
              cachedEmbeddingAtMs: tracked.$2.cachedEmbeddingAtMs,
            );
            overlays.add(
              FaceOverlayBox(
                trackKey: tracked.$1,
                rectRatio: smoothedRatio,
                event: reusedEvent,
                debugLabel: _debugRealtimeOverlay
                    ? 'cache:${tracked.$2.reuseCount + 1}'
                    : null,
              ),
            );

            _publishRecognitionEvent(
              cameraId,
              smoothedRatio,
              reusedEvent,
              nowMs,
            );
            continue;
          }
          if (tracked != null && rejectReason != null) {
            trackStats.onRefresh(rejectReason);
          }

          final crop = _selectRecognitionCrop(
            source: rgb,
            rect: rect,
            detectedFace: detected,
          );
          if (crop == null) continue;

          var workingCrop = crop;
          var luminance = _robustFaceLuminance(workingCrop);
          if (luminance < 0.34) {
            workingCrop = _boostRealtimeFaceExposure(workingCrop, luminance);
            luminance = _robustFaceLuminance(workingCrop);
          }
          workingCrop = _applyRealtimeInputProcessing(workingCrop);
          luminance = _robustFaceLuminance(workingCrop);
          final preSharpnessQuality = (_imageSharpness(workingCrop) / 140.0)
              .clamp(0.0, 1.0)
              .toDouble();
          final preLumaStdDev = _lumaStdDev(workingCrop, luminance);
          final autoSharpenAmount = _computeRealtimeAutoSharpenAmount(
            sharpnessQuality: preSharpnessQuality,
            lumaStdDev: preLumaStdDev,
          );
          workingCrop = _applyAutoTuneRealtimeInputProcessing(
            workingCrop,
            autoSharpenAmount,
          );
          luminance = _robustFaceLuminance(workingCrop);
          final sharpnessQuality = (_imageSharpness(workingCrop) / 140.0)
              .clamp(0.0, 1.0)
              .toDouble();
          final regionQuality = _regionQuality(
            workingCrop,
            minSharpness:
                _minTemplateSharpness * (adaptiveFarDistance ? 0.35 : 0.45),
          );
          final frameQuality = math
              .min(sharpnessQuality, regionQuality)
              .clamp(0.0, 1.0)
              .toDouble();
          final spoofAssessment = _assessSpoof(
            cameraId,
            '${(ratio.center.dx * 100).round()}_${(ratio.center.dy * 100).round()}',
            rectRatio: ratio,
            mesh: null,
            crop: workingCrop,
            frameQuality: frameQuality,
            nowMs: nowMs,
          );
          if (spoofAssessment.isSpoof) {
            final spoofEvent = RecognitionEvent(
              id: _uuid.v4(),
              personName: 'Anh gia mao',
              cameraId: cameraId,
              confidence: (1.0 - spoofAssessment.score).clamp(0.30, 0.99),
              isStranger: true,
              createdAt: nowMs,
            );
            final spoofKey = _matchTrackKey(
              cameraId,
              ratio,
              spoofEvent,
              nextTracks,
            );
            final smoothedSpoofRatio = _smoothTrackedRatio(
              previousTracks[spoofKey]?.currentRect,
              ratio,
            );
            final spoofDebugLabel = _debugRealtimeOverlay
                ? 'spoof:${spoofAssessment.score.toStringAsFixed(2)} ${spoofAssessment.reason}'
                : null;
            nextTracks[spoofKey] = _CameraTrack(
              key: spoofKey,
              currentRect: smoothedSpoofRatio,
              targetRect: smoothedSpoofRatio,
              event: spoofEvent,
              lastSeenAt: nowMs,
              lastRecognitionAt: nowMs,
              lastTrackingConfidence: _associationTrackingConfidence(
                previousTracks[spoofKey]?.currentRect,
                ratio,
              ),
              cachedEmbedding: null,
              cachedEmbeddingAtMs: 0,
            );
            overlays.add(
              FaceOverlayBox(
                trackKey: spoofKey,
                rectRatio: smoothedSpoofRatio,
                event: spoofEvent,
                debugLabel: spoofDebugLabel,
              ),
            );
            _publishRecognitionEvent(
              cameraId,
              smoothedSpoofRatio,
              spoofEvent,
              nowMs,
              eventBuilder: () =>
                  _buildEventWithSnapshot(spoofEvent, rgb: rgb, rect: rect),
            );
            continue;
          }
          pendingRecognitions.add(
            _FallbackPendingRecognition(
              tracked: tracked,
              ratio: ratio,
              rect: rect,
              relaxedAssociation: relaxedAssociation,
              minFacePixels: minFacePixels,
              faceAreaRatio: faceAreaRatio,
              adaptiveFarDistance: adaptiveFarDistance,
              frameQuality: frameQuality,
              spoofScore: spoofAssessment.score,
              workingCrop: workingCrop,
            ),
          );
        } catch (e, st) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final count = (_fallbackFaceSkipCountByCameraId[cameraId] ?? 0) + 1;
          _fallbackFaceSkipCountByCameraId[cameraId] = count;
          final lastAt = _fallbackFaceSkipLogAtByCameraId[cameraId] ?? 0;
          if (now - lastAt >= _fallbackSkipLogIntervalMs) {
            _fallbackFaceSkipLogAtByCameraId[cameraId] = now;
            final stLine = st.toString().split('\n').first;
            _log.debug(
              'Fallback face skipped camera=$cameraId skipped=$count errorType=${e.runtimeType} error=$e stack=$stLine',
            );
            _fallbackFaceSkipCountByCameraId[cameraId] = 0;
          }
          continue;
        }
      }

      if (pendingRecognitions.isNotEmpty) {
        final concurrencyRun =
            await _runWithMaxConcurrency<
              _FallbackPendingRecognition,
              _FallbackComputedRecognition?
            >(
              pendingRecognitions,
              _faceMeshMaxWorkers,
              (pending) => _computeFallbackRecognitionCandidate(
                pending,
                nowMs: frameNowMs,
                frameIndex: frameIndex,
              ),
            );
        _updateWorkerStats(
          cameraId,
          configuredWorkers: _faceMeshMaxWorkers,
          run: concurrencyRun,
        );

        if (pendingRecognitions.length > 1 &&
            _faceMeshMaxWorkers > 1 &&
            frameIndex % 60 == 0) {
          final workerStats = _workerStatsForCamera(cameraId);
          final perWorkerText =
              workerStats?.perWorkerFps
                  .map((fps) => fps.toStringAsFixed(fps >= 10 ? 0 : 1))
                  .join(', ') ??
              '';
          _log.info(
            'Worker pool active mode=fallback camera=$cameraId faces=${pendingRecognitions.length} '
            'workers=${concurrencyRun.activeWorkers}/${concurrencyRun.workerCount} '
            'workerFps=[$perWorkerText]',
          );
        }

        for (final computed in concurrencyRun.results) {
          if (computed == null) {
            continue;
          }

          final pending = computed.pending;
          final tracked = pending.tracked;
          final faceLogKey = tracked?.$1 ?? _faceLogKeyFromRatio(pending.ratio);
          final assignedKnownIds = nextTracks.values
              .map((track) => track.event.personId)
              .whereType<String>()
              .toSet();
          final match = _findBestMatch(
            computed.vector,
            partialBundle: computed.partialBundle,
            excludedPersonIds: assignedKnownIds,
            frameQuality: pending.frameQuality,
            cameraId: cameraId,
            faceLogKey: faceLogKey,
          );
          final effectiveKnown = match != null;
          _logRealtimeDecisionTrace(
            cameraId: cameraId,
            faceLogKey: faceLogKey,
            match: match,
            isKnown: effectiveKnown,
            frameQuality: pending.frameQuality,
          );
          final acceptedMatch = effectiveKnown ? match : null;
          final debugLabel = _debugRealtimeOverlay
              ? _buildRealtimeDebugLabel(
                  match: match,
                  frameQuality: pending.frameQuality,
                  spoofScore: pending.spoofScore,
                )
              : null;
          final confidence =
              (acceptedMatch != null
                      ? acceptedMatch.score.clamp(0.0, 0.99)
                      : _strangerConfidence(
                          match: match,
                          frameQuality: pending.frameQuality,
                        ))
                  .toDouble();
          final event = _buildRecognitionEvent(
            cameraId,
            acceptedMatch,
            frameNowMs,
            unknownConfidence: confidence,
          );

          final key = _matchTrackKey(
            cameraId,
            pending.ratio,
            event,
            nextTracks,
          );
          final smoothedRatio = _smoothTrackedRatio(
            previousTracks[key]?.currentRect,
            pending.ratio,
          );
          nextTracks[key] = _CameraTrack(
            key: key,
            currentRect: smoothedRatio,
            targetRect: smoothedRatio,
            event: event,
            lastSeenAt: frameNowMs,
            lastRecognitionAt: frameNowMs,
            lastTrackingConfidence: _associationTrackingConfidence(
              previousTracks[key]?.currentRect,
              pending.ratio,
            ),
            cachedEmbedding: null,
            cachedEmbeddingAtMs: 0,
          );
          overlays.add(
            FaceOverlayBox(
              trackKey: key,
              rectRatio: smoothedRatio,
              event: event,
              debugLabel: debugLabel,
            ),
          );

          _publishRecognitionEvent(
            cameraId,
            smoothedRatio,
            event,
            frameNowMs,
            eventBuilder: () =>
                _buildEventWithSnapshot(event, rgb: rgb, rect: pending.rect),
          );
        }
      }

      _overlayTracksByCameraId[cameraId] = nextTracks;
      _overlaysByCameraId[cameraId] = overlays;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final annotatedOverlayPng = _maybeBuildOverlayPng(
        _processorsByCameraId[cameraId],
        rgb,
        overlays,
        zone,
        nowMs,
      );
      _emitFrameWithImage(
        cameraId,
        overlays,
        trackStats: trackStats.snapshot(),
        workerStats: _workerStatsForCamera(cameraId),
        annotatedOverlayPng: annotatedOverlayPng,
      );
    } catch (e, st) {
      final stLine = st.toString().split('\n').first;
      _log.error(
        'Fallback processing failed camera=$cameraId errorType=${e.runtimeType} error=$e stack=$stLine',
      );
    }
  }

  List<_DetectedFace> _filterFallbackDetectionsForRealtime(
    List<_DetectedFace> detections, {
    required int frameWidth,
    required int frameHeight,
  }) {
    if (detections.length <= 1) {
      return detections;
    }

    final sorted = [...detections]
      ..sort(
        (a, b) => (b.rect.width * b.rect.height).compareTo(
          a.rect.width * a.rect.height,
        ),
      );

    final maxArea = sorted.first.rect.width * sorted.first.rect.height;
    if (maxArea <= 0) {
      return sorted.take(1).toList(growable: false);
    }

    final frameArea = (frameWidth * frameHeight).toDouble();
    final absoluteMinArea = frameArea * 0.006;
    final relativeMinArea = maxArea * 0.45;
    final minKeepArea = math.max(absoluteMinArea, relativeMinArea);

    final filtered = <_DetectedFace>[];
    for (final face in sorted) {
      final area = face.rect.width * face.rect.height;
      final weakSmallNoise = area < (maxArea * 0.30) && face.score < 0.70;
      if (area >= minKeepArea && !weakSmallNoise) {
        filtered.add(face);
      }
    }

    if (filtered.isEmpty) {
      filtered.add(sorted.first);
    }

    if (_detailedScoreVectorLogging && filtered.length != detections.length) {
      _log.debug(
        'Fallback detection filtered total=${detections.length} kept=${filtered.length} '
        'maxArea=${maxArea.toStringAsFixed(1)} minKeep=${minKeepArea.toStringAsFixed(1)}',
      );
    }

    return filtered;
  }

  Future<List<_DetectedFace>> _detectFacesForFallback(
    img.Image rgb,
    String cameraId,
  ) async {
    if (_scrfdSession != null) {
      try {
        final scrfd = await _detectWithScrfd(rgb);
        if (scrfd.isNotEmpty) {
          return scrfd;
        }
      } catch (e, st) {
        final stLine = st.toString().split('\n').first;
        _log.error(
          'SCRFD detect failed camera=$cameraId errorType=${e.runtimeType} error=$e stack=$stLine',
        );
      }
    }

    final encoded = Uint8List.fromList(img.encodeJpg(rgb, quality: 90));
    List<tfl.Face> faces = const <tfl.Face>[];
    try {
      faces = await _fallbackFaceDetector.detectFaces(
        encoded,
        mode: tfl.FaceDetectionMode.standard,
      );
    } catch (e, st) {
      final stLine = st.toString().split('\n').first;
      _log.error(
        'Fallback detectFaces failed camera=$cameraId errorType=${e.runtimeType} error=$e stack=$stLine',
      );
    }

    final results = <_DetectedFace>[];
    for (final f in faces) {
      final rect = _extractFallbackFaceRect(f, rgb.width, rgb.height);
      if (rect == null) continue;
      results.add(_DetectedFace(rect: rect));
    }
    return results;
  }

  Future<List<_DetectedFace>> _detectFacesForStaticRecognition(
    img.Image source, {
    required String contextKey,
  }) async {
    await _ensureFallbackDetectorReady();
    final detections = await _detectFacesForFallback(source, contextKey);
    if (detections.isEmpty) {
      return const <_DetectedFace>[];
    }

    final sorted = [...detections]
      ..sort((a, b) {
        final areaA = a.rect.width * a.rect.height * a.score;
        final areaB = b.rect.width * b.rect.height * b.score;
        return areaB.compareTo(areaA);
      });
    return sorted;
  }

  Future<List<_DetectedFace>> _detectWithScrfd(img.Image source) async {
    final session = _scrfdSession;
    if (session == null) return const <_DetectedFace>[];

    final resized = await _resizeWithOpenCvDart(source, _scrfdInputSize, _scrfdInputSize);
    final rgb = resized!.getBytes(order: img.ChannelOrder.rgb);

    final input = List<double>.filled(
      1 * 3 * _scrfdInputSize * _scrfdInputSize,
      0.0,
    );
    for (var y = 0; y < _scrfdInputSize; y++) {
      for (var x = 0; x < _scrfdInputSize; x++) {
        final pixelIndex = (y * _scrfdInputSize + x) * 3;
        final spatialIndex = y * _scrfdInputSize + x;
        input[spatialIndex] = (rgb[pixelIndex] - 127.5) / 128.0;
        input[_scrfdInputSize * _scrfdInputSize + spatialIndex] =
            (rgb[pixelIndex + 1] - 127.5) / 128.0;
        input[2 * _scrfdInputSize * _scrfdInputSize + spatialIndex] =
            (rgb[pixelIndex + 2] - 127.5) / 128.0;
      }
    }

    final ortInput = {
      _scrfdInputName: await OrtValue.fromList(input, [
        1,
        3,
        _scrfdInputSize,
        _scrfdInputSize,
      ]),
    };
    final outputs = await session.run(ortInput);
    final tensorsByDim = <int, List<List<double>>>{
      1: <List<double>>[],
      4: <List<double>>[],
      10: <List<double>>[],
    };

    for (final entry in outputs.entries) {
      final values = await entry.value.asList();
      final flat = <double>[];
      _flattenNumericValues(values, flat);
      if (flat.isEmpty) continue;

      final name = entry.key.toLowerCase();
      var dim = 0;
      if (name.contains('kps') || name.contains('landmark')) {
        dim = 10;
      } else if (name.contains('bbox') || name.contains('box')) {
        dim = 4;
      } else if (name.contains('score') ||
          name.contains('cls') ||
          name.contains('conf')) {
        dim = 1;
      }

      if (dim == 0) {
        if (flat.length % 10 == 0) {
          dim = 10;
        } else if (flat.length % 4 == 0) {
          dim = 4;
        } else {
          dim = 1;
        }
      }

      final rows = _chunk(flat, dim);
      tensorsByDim[dim]!.addAll(rows);
    }

    final boxes = tensorsByDim[4]!;
    final scores = tensorsByDim[1]!;
    final keypoints = tensorsByDim[10]!;
    final n = math.min(scores.length, math.min(boxes.length, keypoints.length));
    if (n == 0) return const <_DetectedFace>[];

    final stride = _estimateScrfdStride(n);
    final gridW = (_scrfdInputSize / stride).round();
    final gridH = (_scrfdInputSize / stride).round();
    final anchorCount = math.max(1, (n / (gridW * gridH)).round());

    final rawDetections = <_DetectedFace>[];
    for (var i = 0; i < n; i++) {
      final score = scores[i].isEmpty ? 0.0 : scores[i].first;
      if (score < _scrfdScoreThreshold) continue;

      final loc = i ~/ anchorCount;
      final gy = loc ~/ gridW;
      final gx = loc % gridW;
      final cx = (gx + 0.5) * stride;
      final cy = (gy + 0.5) * stride;

      final b = boxes[i];
      if (b.length < 4) continue;
      final x1 = (cx - b[0] * stride).clamp(
        0.0,
        _scrfdInputSize.toDouble() - 1,
      );
      final y1 = (cy - b[1] * stride).clamp(
        0.0,
        _scrfdInputSize.toDouble() - 1,
      );
      final x2 = (cx + b[2] * stride).clamp(
        0.0,
        _scrfdInputSize.toDouble() - 1,
      );
      final y2 = (cy + b[3] * stride).clamp(
        0.0,
        _scrfdInputSize.toDouble() - 1,
      );
      if (x2 <= x1 || y2 <= y1) continue;

      final scaleX = source.width / _scrfdInputSize;
      final scaleY = source.height / _scrfdInputSize;
      final rect = Rect.fromLTRB(
        x1 * scaleX,
        y1 * scaleY,
        x2 * scaleX,
        y2 * scaleY,
      );

      img.Image? aligned;
      final kp = keypoints[i];
      if (kp.length >= 10) {
        final pts = <Offset>[];
        for (var k = 0; k < 5; k++) {
          pts.add(Offset(kp[k * 2] * scaleX, kp[k * 2 + 1] * scaleY));
        }
        aligned = _alignedCropFromFivePoints(source, pts);
      }

      rawDetections.add(
        _DetectedFace(rect: rect, alignedCrop: aligned, score: score),
      );
    }

    return _nmsDetectedFaces(rawDetections, _scrfdNmsThreshold);
  }

  List<List<double>> _chunk(List<double> values, int dim) {
    if (dim <= 0 || values.isEmpty || values.length < dim) {
      return const <List<double>>[];
    }
    final out = <List<double>>[];
    for (var i = 0; i + dim <= values.length; i += dim) {
      out.add(values.sublist(i, i + dim));
    }
    return out;
  }

  double _estimateScrfdStride(int rows) {
    const candidates = <double>[8, 16, 32, 64];
    var bestStride = 8.0;
    var bestError = double.infinity;
    for (final stride in candidates) {
      final grid = (_scrfdInputSize / stride).round();
      final cellCount = grid * grid;
      final anchors = rows / cellCount;
      final error = (anchors - anchors.roundToDouble()).abs();
      if (error < bestError) {
        bestError = error;
        bestStride = stride;
      }
    }
    return bestStride;
  }

  List<_DetectedFace> _nmsDetectedFaces(
    List<_DetectedFace> input,
    double iouThreshold,
  ) {
    if (input.length < 2) return input;
    final boxes = [...input]..sort((a, b) => b.score.compareTo(a.score));
    final kept = <_DetectedFace>[];
    for (final candidate in boxes) {
      var suppressed = false;
      for (final selected in kept) {
        if (_rectIoU(candidate.rect, selected.rect) >= iouThreshold) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) {
        kept.add(candidate);
      }
    }
    return kept;
  }

  img.Image? _alignedCropFromFivePoints(img.Image source, List<Offset> points) {
    if (points.length < 2) return null;
    final leftEye = points[0];
    final rightEye = points[1];
    final eyeDx = rightEye.dx - leftEye.dx;
    final eyeDy = rightEye.dy - leftEye.dy;
    final eyeDistance = math.sqrt(eyeDx * eyeDx + eyeDy * eyeDy);
    if (eyeDistance < _minRealtimeFacePixels) return null;

    final angleDeg = math.atan2(eyeDy, eyeDx) * 180.0 / math.pi;
    final rotated = img.copyRotate(
      source,
      angle: -angleDeg,
      interpolation: img.Interpolation.linear,
    );

    final srcCenter = Offset(source.width / 2, source.height / 2);
    final dstCenter = Offset(rotated.width / 2, rotated.height / 2);
    final leftEyeRotated = _rotatePoint(
      leftEye,
      srcCenter,
      -angleDeg,
      dstCenter,
    );
    final rightEyeRotated = _rotatePoint(
      rightEye,
      srcCenter,
      -angleDeg,
      dstCenter,
    );

    final cx = (leftEyeRotated.dx + rightEyeRotated.dx) / 2;
    final cy =
        (leftEyeRotated.dy + rightEyeRotated.dy) / 2 + eyeDistance * 0.38;
    final side = (eyeDistance * 2.25).clamp(
      _minRealtimeFacePixels.toDouble(),
      math.min(rotated.width, rotated.height).toDouble(),
    );
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: side,
      height: side,
    );
    return _cropFaceTight(rotated, rect, paddingRatio: -0.10);
  }

  Future<FaceMeshMultiInferenceResult?> _runMediaPipeInference(
    _CameraFrameInput input,
  ) async {
    await _ensureMediaPipeProcessors();
    final pipeline = _faceMeshPipeline;
    if (pipeline == null) return null;

    if (input.image is FaceMeshNv21Image) {
      return pipeline.processNv21MultiFace(
        input.image as FaceMeshNv21Image,
        maxMeshFaces: 4,
        rotationDegrees: input.rotationDegrees,
      );
    }

    if (input.image is FaceMeshImage) {
      return pipeline.processMultiFace(
        input.image as FaceMeshImage,
        maxMeshFaces: 4,
        rotationDegrees: input.rotationDegrees,
      );
    }

    return null;
  }

  _CameraFrameInput? _buildMediaPipeFrameFromRgb(
    img.Image source, {
    required int rotationDegrees,
  }) {
    final rgba = source.getBytes(order: img.ChannelOrder.rgba);
    final frame = FaceMeshImage(
      pixels: Uint8List.fromList(rgba),
      width: source.width,
      height: source.height,
      pixelFormat: FaceMeshPixelFormat.rgba,
      bytesPerRow: source.width * 4,
    );
    return _CameraFrameInput(image: frame, rotationDegrees: rotationDegrees);
  }

  int _rotationDegreesFor(String cameraId, CameraImage image) {
    final processor = _processorsByCameraId[cameraId];
    if (processor == null) return 0;
    final cameraOrientation =
        processor.controller.description.sensorOrientation;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return cameraOrientation;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return cameraOrientation;
    }
    return 0;
  }

  String _matchTrackKey(
    String cameraId,
    Rect ratio,
    RecognitionEvent event,
    Map<String, _CameraTrack> nextTracks,
  ) {
    final previousTracks =
        _overlayTracksByCameraId[cameraId] ?? const <String, _CameraTrack>{};
    if (!event.isStranger &&
        event.personId != null &&
        event.personId!.isNotEmpty) {
      final knownKeys = previousTracks.keys
          .where(
            (key) =>
                key.startsWith('known_${cameraId}_${event.personId}_') &&
                !nextTracks.containsKey(key),
          )
          .toList(growable: false);

      String? bestKnownKey;
      var bestKnownScore = 0.0;
      for (final key in knownKeys) {
        final candidate = previousTracks[key];
        if (candidate == null) continue;
        final iou = _rectIoU(candidate.currentRect, ratio);
        final distance = _rectCenterDistance(candidate.currentRect, ratio);
        final score = iou * 0.7 + (1 - distance.clamp(0.0, 1.0)) * 0.3;
        if (score > bestKnownScore && score >= 0.35) {
          bestKnownScore = score;
          bestKnownKey = key;
        }
      }

      if (bestKnownKey != null) {
        return bestKnownKey;
      }

      return 'known_${cameraId}_${event.personId}_${(ratio.center.dx * 100).round()}_${(ratio.center.dy * 100).round()}';
    }

    var bestKey =
        'stranger_${cameraId}_${(ratio.center.dx * 100).round()}_${(ratio.center.dy * 100).round()}';
    var bestScore = 0.0;
    for (final entry in previousTracks.entries) {
      if (!entry.key.startsWith('stranger_${cameraId}_')) {
        continue;
      }
      if (nextTracks.containsKey(entry.key)) {
        continue;
      }
      final candidate = entry.value;
      final score =
          _rectIoU(candidate.currentRect, ratio) +
          (1 -
              _rectCenterDistance(
                candidate.currentRect,
                ratio,
              ).clamp(0.0, 1.0));
      if (score > bestScore && score >= 0.95) {
        bestScore = score;
        bestKey = entry.key;
      }
    }
    return bestKey;
  }

  (String, _CameraTrack, double)? _resolveTrackedTrack(
    Map<String, _CameraTrack> previousTracks,
    Rect ratio,
    int nowMs,
  ) {
    String? bestKey;
    _CameraTrack? bestTrack;
    var bestScore = 0.0;
    final active = <(String, _CameraTrack)>[];
    for (final entry in previousTracks.entries) {
      final track = entry.value;
      if (nowMs - track.lastSeenAt > _trackKeepAliveMs) continue;
      active.add((entry.key, track));
      final iou = _rectIoU(track.currentRect, ratio);
      final centerScore =
          1 - _rectCenterDistance(track.currentRect, ratio).clamp(0.0, 1.0);
      final score = iou * 0.62 + centerScore * 0.38;
      if (score > bestScore) {
        bestScore = score;
        bestKey = entry.key;
        bestTrack = track;
      }
    }

    if (bestKey != null &&
        bestTrack != null &&
        bestScore >= _trackAssociationMinScore) {
      return (bestKey, bestTrack, bestScore);
    }

    // ByteTrack-like permissive fallback: if only one active track remains,
    // accept weak association when center displacement is still reasonable.
    if (active.length == 1) {
      final only = active.first;
      final iou = _rectIoU(only.$2.currentRect, ratio);
      final centerDistance = _rectCenterDistance(only.$2.currentRect, ratio);
      final looseScore =
          (iou * 0.52 + (1 - centerDistance.clamp(0.0, 1.0)) * 0.48)
              .clamp(0.0, 1.0)
              .toDouble();
      if (centerDistance <= 0.30 && iou >= 0.05) {
        return (only.$1, only.$2, looseScore);
      }
    }

    if (bestKey == null || bestTrack == null) {
      return null;
    }
    return null;
  }

  bool _hasLiveTracks(Map<String, _CameraTrack> previousTracks, int nowMs) {
    for (final track in previousTracks.values) {
      if (nowMs - track.lastSeenAt <= _trackKeepAliveMs) {
        return true;
      }
    }
    return false;
  }

  _TrackStatsAccumulator _statsForCamera(String cameraId, int nowMs) {
    final current = _trackStatsByCameraId.putIfAbsent(
      cameraId,
      () => _TrackStatsAccumulator(windowStartedAtMs: nowMs),
    );
    if (nowMs - current.windowStartedAtMs >
        _TrackStatsAccumulator.windowDurationMs) {
      current.reset(nowMs);
    }
    return current;
  }

  _TrackReuseRejectReason? _trackReuseRejectReason({
    required _CameraTrack track,
    required Rect currentRatio,
    double? currentYawDeg,
    double? currentPitchDeg,
    required int nowMs,
    bool relaxedAssociation = false,
  }) {
    final elapsedMs = nowMs - track.lastRecognitionAt;
    final maxReuseMs = track.event.isStranger
        ? _trackReuseStrangerMs
        : _trackReuseKnownMs;
    if (elapsedMs > maxReuseMs) {
      return _TrackReuseRejectReason.ttl;
    }

    final previousYaw = track.lastYawDeg;
    if (previousYaw != null && currentYawDeg != null) {
      if ((currentYawDeg - previousYaw).abs() > _trackPoseRefreshDeltaDeg) {
        return _TrackReuseRejectReason.pose;
      }
    }

    final previousPitch = track.lastPitchDeg;
    if (previousPitch != null && currentPitchDeg != null) {
      if ((currentPitchDeg - previousPitch).abs() > _trackPoseRefreshDeltaDeg) {
        return _TrackReuseRejectReason.pose;
      }
    }

    final previous = track.currentRect;
    final minIoU = relaxedAssociation
        ? (_trackReuseMinIoU - 0.14).clamp(0.05, 0.84)
        : _trackReuseMinIoU;
    final maxCenterDistance = relaxedAssociation
        ? (_trackReuseMaxCenterDistance + 0.18).clamp(0.20, 0.55)
        : _trackReuseMaxCenterDistance;
    final iou = _rectIoU(previous, currentRatio);
    if (iou < minIoU) {
      return _TrackReuseRejectReason.geometry;
    }

    final centerDistance = _rectCenterDistance(previous, currentRatio);
    if (centerDistance > maxCenterDistance) {
      return _TrackReuseRejectReason.geometry;
    }

    final previousArea = (previous.width * previous.height).clamp(1e-6, 1.0);
    final currentArea = (currentRatio.width * currentRatio.height).clamp(
      1e-6,
      1.0,
    );
    final areaScale = currentArea / previousArea;
    final minAreaScale = relaxedAssociation ? 0.40 : 0.60;
    final maxAreaScale = relaxedAssociation ? 2.30 : 1.70;
    if (areaScale < minAreaScale || areaScale > maxAreaScale) {
      return _TrackReuseRejectReason.geometry;
    }

    if (!track.event.isStranger &&
        track.event.confidence < 0.62 &&
        elapsedMs > math.max(120, _processFrameIntervalMs * 2) &&
        !relaxedAssociation) {
      return _TrackReuseRejectReason.ttl;
    }

    return null;
  }

  bool _shouldReuseTrackedRecognition({
    required _CameraTrack track,
    required Rect currentRatio,
    double? currentYawDeg,
    double? currentPitchDeg,
    required int nowMs,
  }) {
    return _trackReuseRejectReason(
          track: track,
          currentRatio: currentRatio,
          currentYawDeg: currentYawDeg,
          currentPitchDeg: currentPitchDeg,
          nowMs: nowMs,
        ) ==
        null;
  }

  Future<_ConcurrencyRunResult<R>> _runWithMaxConcurrency<T, R>(
    List<T> items,
    int maxWorkers,
    Future<R> Function(T item) op,
  ) async {
    if (items.isEmpty) {
      return _ConcurrencyRunResult<R>(
        results: <R>[],
        workerCount: 0,
        activeWorkers: 0,
        processedPerWorker: <int>[],
        elapsedMs: 0,
      );
    }

    final workerCount = math.min(maxWorkers.clamp(1, 64), items.length);
    final results = List<R?>.filled(items.length, null);
    final processedPerWorker = List<int>.filled(workerCount, 0);
    var cursor = 0;
    var activeWorkers = 0;
    final startedAt = DateTime.now().millisecondsSinceEpoch;

    Future<void> runWorker(int workerIndex) async {
      while (true) {
        if (cursor >= items.length) {
          return;
        }
        final index = cursor;
        cursor++;
        if (processedPerWorker[workerIndex] == 0) {
          activeWorkers++;
        }
        results[index] = await op(items[index]);
        processedPerWorker[workerIndex]++;
      }
    }

    await Future.wait(List.generate(workerCount, runWorker));
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - startedAt;
    return _ConcurrencyRunResult<R>(
      results: results.cast<R>(),
      workerCount: workerCount,
      activeWorkers: activeWorkers,
      processedPerWorker: processedPerWorker,
      elapsedMs: elapsedMs,
    );
  }

  void _updateWorkerStats(
    String cameraId, {
    required int configuredWorkers,
    required _ConcurrencyRunResult<dynamic> run,
  }) {
    final accumulator = _workerStatsByCameraId.putIfAbsent(
      cameraId,
      () => _WorkerRuntimeAccumulator(maxWorkers: configuredWorkers),
    );
    if (accumulator.maxWorkers != configuredWorkers) {
      accumulator.resetForMaxWorkers(configuredWorkers);
    }
    accumulator.updateBatch(
      configured: configuredWorkers,
      active: run.activeWorkers,
      elapsedMs: run.elapsedMs,
      processedPerWorker: run.processedPerWorker,
    );
  }

  CameraWorkerRuntimeStats? _workerStatsForCamera(String cameraId) {
    final accumulator = _workerStatsByCameraId[cameraId];
    if (accumulator == null) {
      return null;
    }
    return accumulator.snapshot();
  }

  Future<_NativeComputedRecognition?> _computeNativeRecognitionCandidate(
    _NativePendingRecognition pending, {
    required int nowMs,
    required int frameIndex,
  }) async {
    final tracked = pending.tracked;
    final cachedVector = _cachedEmbeddingForTracked(
      tracked?.$2,
      nowMs: nowMs,
      trackingConfidence: tracked?.$3,
      relaxedAssociation: pending.relaxedAssociation,
    );
    final vector =
        cachedVector ??
        _alignVectorDimension(
          await _embeddingFromImage(pending.workingCrop, robust: false),
          _templateVectorDimension,
        );
    if (vector.isEmpty) {
      return null;
    }

    final shouldComputePartials =
        cachedVector == null &&
        _shouldComputeRealtimePartials(
          minFacePixels: pending.minFacePixels,
          faceAreaRatio: pending.faceAreaRatio,
          frameQuality: pending.frameQuality,
          adaptiveFarDistance: pending.adaptiveFarDistance,
          frameIndex: frameIndex,
        );
    final partialBundle = shouldComputePartials
        ? await _buildPartialEmbeddingsFromFace(
            pending.workingCrop,
            targetDimension: _templateVectorDimension,
            frameQuality: pending.frameQuality,
            forRealtime: true,
            faceAlreadyPrepared: true,
          )
        : const _PartialEmbeddingBundle();

    return _NativeComputedRecognition(
      pending: pending,
      vector: vector,
      partialBundle: partialBundle,
    );
  }

  Future<_FallbackComputedRecognition?> _computeFallbackRecognitionCandidate(
    _FallbackPendingRecognition pending, {
    required int nowMs,
    required int frameIndex,
  }) async {
    final tracked = pending.tracked;
    final cachedVector = _cachedEmbeddingForTracked(
      tracked?.$2,
      nowMs: nowMs,
      trackingConfidence: tracked?.$3,
      relaxedAssociation: pending.relaxedAssociation,
    );
    final vector =
        cachedVector ??
        _alignVectorDimension(
          await _embeddingFromImage(pending.workingCrop, robust: false),
          _templateVectorDimension,
        );
    if (vector.isEmpty) {
      return null;
    }

    final shouldComputePartials =
        cachedVector == null &&
        _shouldComputeRealtimePartials(
          minFacePixels: pending.minFacePixels,
          faceAreaRatio: pending.faceAreaRatio,
          frameQuality: pending.frameQuality,
          adaptiveFarDistance: pending.adaptiveFarDistance,
          frameIndex: frameIndex,
        );
    final partialBundle = shouldComputePartials
        ? await _buildPartialEmbeddingsFromFace(
            pending.workingCrop,
            targetDimension: _templateVectorDimension,
            frameQuality: pending.frameQuality,
            forRealtime: true,
            faceAlreadyPrepared: true,
          )
        : const _PartialEmbeddingBundle();

    return _FallbackComputedRecognition(
      pending: pending,
      vector: vector,
      partialBundle: partialBundle,
    );
  }

  List<double>? _cachedEmbeddingForTracked(
    _CameraTrack? track, {
    required int nowMs,
    double? trackingConfidence,
    bool relaxedAssociation = false,
  }) {
    if (track == null) {
      return null;
    }
    if (track.lastYawDeg == null || track.lastPitchDeg == null) {
      return null;
    }
    if (track.event.isStranger) {
      return null;
    }
    final cached = track.cachedEmbedding;
    if (cached == null || cached.isEmpty) {
      return null;
    }
    if (_templateVectorDimension > 0 &&
        cached.length != _templateVectorDimension) {
      return null;
    }
    if (!relaxedAssociation &&
        trackingConfidence != null &&
        trackingConfidence < _trackAssociationMinScore) {
      return null;
    }
    final cachedAt = track.cachedEmbeddingAtMs > 0
        ? track.cachedEmbeddingAtMs
        : track.lastRecognitionAt;
    final ageMs = nowMs - cachedAt;
    final cacheTtlMs = track.event.isStranger
        ? (_trackReuseStrangerMs * 2).clamp(250, 6000).toInt()
        : (_trackReuseKnownMs * 2).clamp(300, 8000).toInt();
    if (ageMs <= 0 || ageMs > cacheTtlMs) {
      return null;
    }
    return cached;
  }

  double _associationTrackingConfidence(Rect? previous, Rect current) {
    if (previous == null) {
      return 1.0;
    }
    final iou = _rectIoU(previous, current);
    final center = 1 - _rectCenterDistance(previous, current).clamp(0.0, 1.0);
    return (iou * 0.75 + center * 0.25).clamp(0.0, 1.0).toDouble();
  }

  (double?, double?) _estimateFacePoseDegrees(FaceMeshResult mesh) {
    final leftEyeOuter = _landmarkPixel(mesh, 33);
    final rightEyeOuter = _landmarkPixel(mesh, 263);
    final noseTip = _landmarkPixel(mesh, 1);
    final upperLip = _landmarkPixel(mesh, 13);
    final chin = _landmarkPixel(mesh, 152);
    if (leftEyeOuter == null ||
        rightEyeOuter == null ||
        noseTip == null ||
        upperLip == null ||
        chin == null) {
      return (null, null);
    }

    final eyeMid = Offset(
      (leftEyeOuter.dx + rightEyeOuter.dx) / 2,
      (leftEyeOuter.dy + rightEyeOuter.dy) / 2,
    );
    final eyeDistance = _distance(leftEyeOuter, rightEyeOuter);
    final faceHeight = _distance(eyeMid, chin);
    if (eyeDistance < 1.0 || faceHeight < 1.0) {
      return (null, null);
    }

    final yawNorm = ((noseTip.dx - eyeMid.dx) / (eyeDistance * 0.55)).clamp(
      -1.0,
      1.0,
    );
    final yawDeg = (math.asin(yawNorm) * 180.0 / math.pi).clamp(-50.0, 50.0);

    final mouthRefY = (upperLip.dy + chin.dy) / 2;
    final pitchNorm = ((noseTip.dy - mouthRefY) / (faceHeight * 0.55)).clamp(
      -1.0,
      1.0,
    );
    final pitchDeg = (math.asin(pitchNorm) * 180.0 / math.pi).clamp(
      -50.0,
      50.0,
    );
    return (yawDeg.toDouble(), pitchDeg.toDouble());
  }

  RecognitionEvent _refreshTrackedEvent(
    String cameraId,
    RecognitionEvent baseEvent,
    int nowMs,
  ) {
    return RecognitionEvent(
      id: _uuid.v4(),
      personId: baseEvent.personId,
      personName: baseEvent.personName,
      cameraId: cameraId,
      confidence: baseEvent.confidence,
      isStranger: baseEvent.isStranger,
      createdAt: nowMs,
      snapshotBase64: '',
    );
  }

  Rect _rectFromRatio(Rect ratio, int imageWidth, int imageHeight) {
    final left = (ratio.left * imageWidth).clamp(0.0, imageWidth - 1.0);
    final top = (ratio.top * imageHeight).clamp(0.0, imageHeight - 1.0);
    final width = (ratio.width * imageWidth).clamp(1.0, imageWidth - left);
    final height = (ratio.height * imageHeight).clamp(1.0, imageHeight - top);
    return Rect.fromLTWH(left, top, width, height);
  }

  Rect _smoothTrackedRatio(Rect? previous, Rect current) {
    if (previous == null) return current;
    final a = _bboxSmoothingAlpha.clamp(0.0, 1.0);
    final left = previous.left * (1 - a) + current.left * a;
    final top = previous.top * (1 - a) + current.top * a;
    final width = previous.width * (1 - a) + current.width * a;
    final height = previous.height * (1 - a) + current.height * a;

    final clampedLeft = left.clamp(0.0, 1.0);
    final clampedTop = top.clamp(0.0, 1.0);
    final maxWidth = 1.0 - clampedLeft;
    final maxHeight = 1.0 - clampedTop;
    final clampedWidth = width.clamp(0.0, maxWidth);
    final clampedHeight = height.clamp(0.0, maxHeight);
    return Rect.fromLTWH(clampedLeft, clampedTop, clampedWidth, clampedHeight);
  }

  RecognitionEvent _buildRecognitionEvent(
    String cameraId,
    _MatchResult? match,
    int createdAtMs, {
    String snapshotBase64 = '',
    double? unknownConfidence,
  }) {
    final isKnown = match != null;
    if (isKnown) {
      return RecognitionEvent(
        id: _uuid.v4(),
        personId: match.template.person.id,
        personName: match.template.person.name,
        cameraId: cameraId,
        confidence: match.score.clamp(0, 0.99),
        isStranger: false,
        createdAt: createdAtMs,
        snapshotBase64: snapshotBase64,
      );
    }
    return RecognitionEvent(
      id: _uuid.v4(),
      personName: 'Nguoi la',
      cameraId: cameraId,
      confidence: (unknownConfidence ?? _strangerConfidence(match: match))
          .clamp(0.30, 0.76),
      isStranger: true,
      createdAt: createdAtMs,
      snapshotBase64: snapshotBase64,
    );
  }

  double _strangerConfidence({
    required _MatchResult? match,
    double? frameQuality,
  }) {
    final quality = (frameQuality ?? 0.35).clamp(0.0, 1.0);
    if (match == null) {
      return (0.32 + quality * 0.38).clamp(0.30, 0.76).toDouble();
    }

    final scoreGap = (1.0 - match.score).clamp(0.0, 1.0);
    final lowQualityBoost = (1.0 - quality) * 0.18;
    return (scoreGap * 0.82 + lowQualityBoost).clamp(0.30, 0.76).toDouble();
  }

  String _buildRealtimeDebugLabel({
    required _MatchResult? match,
    required double frameQuality,
    double? spoofScore,
  }) {
    final threshold = _knownMatchThreshold.toStringAsFixed(2);
    if (match == null) {
      final spoofText = spoofScore == null
          ? ''
          : ' s:${spoofScore.toStringAsFixed(2)}';
      return 'top1:- th:$threshold q:${frameQuality.toStringAsFixed(2)}$spoofText';
    }

    final top1 = match.score.toStringAsFixed(3);
    final margin = match.margin.toStringAsFixed(3);
    final spoofText = spoofScore == null
        ? ''
        : ' s:${spoofScore.toStringAsFixed(2)}';
    return 'top1:$top1 th:$threshold m:$margin q:${frameQuality.toStringAsFixed(2)}$spoofText';
  }

  RecognitionEvent _buildEventWithSnapshot(
    RecognitionEvent baseEvent, {
    required img.Image rgb,
    required Rect rect,
  }) {
    return RecognitionEvent(
      id: baseEvent.id,
      personId: baseEvent.personId,
      personName: baseEvent.personName,
      cameraId: baseEvent.cameraId,
      confidence: baseEvent.confidence,
      isStranger: baseEvent.isStranger,
      createdAt: baseEvent.createdAt,
      snapshotBase64: _encodeSnapshotWithBboxBase64(
        rgb,
        rect,
        isStranger: baseEvent.isStranger,
        personName: baseEvent.personName,
        confidence: baseEvent.confidence,
        createdAt: baseEvent.createdAt,
        cameraId: baseEvent.cameraId ?? '',
      ),
    );
  }

  _SpoofAssessment _assessSpoof(
    String cameraId,
    String faceLogKey, {
    required Rect rectRatio,
    FaceMeshResult? mesh,
    img.Image? crop,
    required double frameQuality,
    required int nowMs,
  }) {
    final key = '$cameraId|$faceLogKey';
    final state = _spoofStates.putIfAbsent(
      key,
      () => _SpoofState(lastSeenAtMs: nowMs),
    );

    if (nowMs - state.lastSeenAtMs > 2200) {
      state.eyeHistory.clear();
      state.mouthHistory.clear();
      state.motionHistory.clear();
      state.sizeHistory.clear();
      state.previousEye = null;
      state.previousMouth = null;
      state.previousCenter = null;
      state.blinkSeen = false;
      state.frameCount = 0;
    }

    state.lastSeenAtMs = nowMs;
    state.frameCount++;

    final faceCenter = rectRatio.center;
    final faceSize = (rectRatio.width + rectRatio.height) / 2;
    if (state.previousCenter != null) {
      final dx = faceCenter.dx - state.previousCenter!.dx;
      final dy = faceCenter.dy - state.previousCenter!.dy;
      final motion = math.sqrt(dx * dx + dy * dy);
      state.motionHistory.add(motion);
      if (state.motionHistory.length > 8) {
        state.motionHistory.removeAt(0);
      }
    }
    state.previousCenter = faceCenter;
    state.sizeHistory.add(faceSize);
    if (state.sizeHistory.length > 8) {
      state.sizeHistory.removeAt(0);
    }

    double? eyeOpenness;
    double? mouthOpenness;
    if (mesh != null) {
      eyeOpenness = _eyeOpenness(mesh);
      mouthOpenness = _mouthOpenness(mesh);

      state.eyeHistory.add(eyeOpenness);
      state.mouthHistory.add(mouthOpenness);
      if (state.eyeHistory.length > 10) {
        state.eyeHistory.removeAt(0);
      }
      if (state.mouthHistory.length > 10) {
        state.mouthHistory.removeAt(0);
      }

      final prevEye = state.previousEye;
      if (prevEye != null && prevEye > 0.24 && eyeOpenness < 0.15) {
        state.blinkSeen = true;
      }
      state.previousEye = eyeOpenness;
      state.previousMouth = mouthOpenness;
    }

    final eyeStd = _stdDev(state.eyeHistory);
    final mouthStd = _stdDev(state.mouthHistory);
    final motionAvg = _mean(state.motionHistory);
    final sizeStd = _stdDev(state.sizeHistory);
    final textureScore =
        (frameQuality * 0.55 + (_lumaContrastScore(crop) * 0.45)).clamp(
          0.0,
          1.0,
        );

    final blinkScore = state.blinkSeen ? 0.42 : 0.0;
    final eyeVarScore = ((eyeStd - 0.010) / 0.045).clamp(0.0, 0.20);
    final mouthVarScore = ((mouthStd - 0.008) / 0.040).clamp(0.0, 0.12);
    final motionScore = ((motionAvg - 0.0015) / 0.018).clamp(0.0, 0.14);
    final sizeMotionScore = ((sizeStd - 0.002) / 0.020).clamp(0.0, 0.08);

    final liveScore =
        (blinkScore +
                eyeVarScore +
                mouthVarScore +
                motionScore +
                sizeMotionScore +
                textureScore * 0.18)
            .clamp(0.0, 1.0)
            .toDouble();

    var isSpoof = false;
    var reason = 'pending';
    if (state.frameCount >= 8 &&
        liveScore < 0.16 &&
        textureScore < 0.42 &&
        frameQuality < 0.70) {
      isSpoof = true;
      reason = 'no_blink_no_motion';
    } else if (state.frameCount >= 12 &&
        liveScore < 0.22 &&
        textureScore < 0.48 &&
        frameQuality < 0.62) {
      isSpoof = true;
      reason = 'low_liveness';
    } else if (state.frameCount >= 20 &&
        !state.blinkSeen &&
        liveScore < 0.26 &&
        textureScore < 0.52 &&
        frameQuality < 0.58) {
      isSpoof = true;
      reason = 'no_blink';
    }

    if (isSpoof && _traceLogsEnabled) {
      _log.debug(
        'Spoof detected camera=$cameraId face=$faceLogKey score=${liveScore.toStringAsFixed(3)} eyeStd=${eyeStd.toStringAsFixed(3)} mouthStd=${mouthStd.toStringAsFixed(3)} motion=${motionAvg.toStringAsFixed(3)} reason=$reason',
      );
    }

    return _SpoofAssessment(score: liveScore, reason: reason, isSpoof: isSpoof);
  }

  double _eyeOpenness(FaceMeshResult mesh) {
    final left = _landmarkPixel(mesh, 33);
    final leftUpper = _landmarkPixel(mesh, 159);
    final leftLower = _landmarkPixel(mesh, 145);
    final leftInner = _landmarkPixel(mesh, 133);

    final right = _landmarkPixel(mesh, 263);
    final rightUpper = _landmarkPixel(mesh, 386);
    final rightLower = _landmarkPixel(mesh, 374);
    final rightOuter = _landmarkPixel(mesh, 362);

    double eyeRatio(Offset outer, Offset inner, Offset upper, Offset lower) {
      final width = _distance(outer, inner);
      final height = _distance(upper, lower);
      if (width <= 0) return 0.0;
      return (height / width).clamp(0.0, 1.0);
    }

    final leftRatio =
        (left != null &&
            leftInner != null &&
            leftUpper != null &&
            leftLower != null)
        ? eyeRatio(left, leftInner, leftUpper, leftLower)
        : 0.0;
    final rightRatio =
        (right != null &&
            rightOuter != null &&
            rightUpper != null &&
            rightLower != null)
        ? eyeRatio(rightOuter, right, rightUpper, rightLower)
        : 0.0;
    return ((leftRatio + rightRatio) / 2).clamp(0.0, 1.0).toDouble();
  }

  double _mouthOpenness(FaceMeshResult mesh) {
    final upper = _landmarkPixel(mesh, 13);
    final lower = _landmarkPixel(mesh, 14);
    final left = _landmarkPixel(mesh, 78);
    final right = _landmarkPixel(mesh, 308);
    if (upper == null || lower == null || left == null || right == null) {
      return 0.0;
    }
    final width = _distance(left, right);
    final height = _distance(upper, lower);
    if (width <= 0) return 0.0;
    return (height / width).clamp(0.0, 1.0).toDouble();
  }

  double _distance(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _stdDev(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = _mean(values);
    var variance = 0.0;
    for (final value in values) {
      final delta = value - mean;
      variance += delta * delta;
    }
    variance /= values.length;
    return math.sqrt(variance);
  }

  double _lumaContrastScore(img.Image? image) {
    if (image == null || image.width < 4 || image.height < 4) return 0.0;
    final gray = img.grayscale(image);
    final samples = <double>[];
    final stepX = math.max(1, gray.width ~/ 8);
    final stepY = math.max(1, gray.height ~/ 8);
    for (var y = 0; y < gray.height; y += stepY) {
      for (var x = 0; x < gray.width; x += stepX) {
        samples.add(gray.getPixel(x, y).r.toDouble() / 255.0);
      }
    }
    if (samples.length < 2) return 0.0;
    return _stdDev(samples).clamp(0.0, 1.0).toDouble();
  }

  String _encodeSnapshotWithBboxBase64(
    img.Image frame,
    Rect faceRect, {
    required bool isStranger,
    required String personName,
    required double confidence,
    required int createdAt,
    required String cameraId,
  }) {
    // Chuyển frame từ image sang Mat của OpenCV
    final mat = opencv.Mat.fromList(frame.height, frame.width, opencv.MatType.CV_8UC3, frame.getBytes());

    // Tính toán tọa độ bbox
    final left = faceRect.left.floor().clamp(0, frame.width - 1);
    final top = faceRect.top.floor().clamp(0, frame.height - 1);
    final right = faceRect.right.ceil().clamp(left, frame.width - 1);
    final bottom = faceRect.bottom.ceil().clamp(top, frame.height - 1);

    // Màu bbox
    final color = isStranger
        ? opencv.Scalar(255, 165, 0, 245) // cam
        : opencv.Scalar(120, 235, 0, 245); // xanh lá

    // Tạo Rect đúng kiểu cho OpenCV
    final cvRect = opencv.Rect(left, top, right - left, bottom - top);
    // Vẽ rectangle bằng OpenCV
    opencv.rectangle(
      mat,
      cvRect,
      color,
      thickness: 3,
    );

    // Chuẩn bị text
    final label = '$personName ${(confidence * 100).toStringAsFixed(0)}%';
    final timeText = _formatLogTimestamp(createdAt);
    final cameraText = 'Cam: $cameraId';

    final textX = left.clamp(0, frame.width - 1);
    final textY1 = (top - 42).clamp(0, frame.height - 1);
    final textY2 = (textY1 + 14).clamp(0, frame.height - 1);
    final textY3 = (textY2 + 14).clamp(0, frame.height - 1);

    // Vẽ text bằng OpenCV
    opencv.putText(mat, label, opencv.Point(textX, textY1), opencv.FONT_HERSHEY_SIMPLEX, 0.5, color, thickness: 1,);
    opencv.putText(mat, timeText, opencv.Point(textX, textY2), opencv.FONT_HERSHEY_SIMPLEX, 0.5, opencv.Scalar(255,255,255,245), thickness: 1,);
    opencv.putText(mat, cameraText, opencv.Point(textX, textY3), opencv.FONT_HERSHEY_SIMPLEX, 0.5, opencv.Scalar(255,255,255,245), thickness: 1,);

    // Resize nếu cần
    final maxSide = math.max(frame.width, frame.height);
    opencv.Mat normalized = mat;
    if (maxSide > 640) {
      final newWidth  = frame.width >= frame.height ? 640 : (frame.width * 640 ~/ frame.height);
      final newHeight = frame.height > frame.width ? 640 : (frame.height * 640 ~/ frame.width);
      normalized = opencv.resize(
        mat,
        (newWidth, newHeight), // tuple (int, int)
        interpolation: opencv.INTER_LINEAR,
      );
    }

    // Encode sang JPG
    final params = opencv.VecI32.fromList([opencv.IMWRITE_JPEG_QUALITY, 80]);
    final result = opencv.imencode(
      '.jpg',
      normalized,
      params: params,
    );

    // result là (bool, Uint8List)
    final success = result.$1;      // hoặc result.item1
    final jpgBytes = result.$2;     // hoặc result.item2

    if (!success) {
      throw Exception('imencode failed');
    }
    return base64Encode(jpgBytes);
  }

  // String _encodeSnapshotWithBboxBase64(
  //   img.Image frame,
  //   Rect faceRect, {
  //   required bool isStranger,
  //   required String personName,
  //   required double confidence,
  //   required int createdAt,
  //   required String cameraId,
  // }) {
  //   final annotated = img.Image.from(frame);
  //   final left = faceRect.left.floor().clamp(0, annotated.width - 1);
  //   final top = faceRect.top.floor().clamp(0, annotated.height - 1);
  //   final right = faceRect.right.ceil().clamp(left, annotated.width - 1);
  //   final bottom = faceRect.bottom.ceil().clamp(top, annotated.height - 1);
  //   final color = isStranger
  //       ? img.ColorRgba8(255, 165, 0, 245)
  //       : img.ColorRgba8(120, 235, 0, 245);
  //   img.drawRect(
  //     annotated,
  //     x1: left,
  //     y1: top,
  //     x2: right,
  //     y2: bottom,
  //     color: color,
  //     thickness: 3,
  //   );

  //   final label = '$personName ${(confidence * 100).toStringAsFixed(0)}%';
  //   final timeText = _formatLogTimestamp(createdAt);
  //   final cameraText = 'Cam: $cameraId';

  //   final textX = left.clamp(0, annotated.width - 1);
  //   final textY1 = (top - 42).clamp(0, annotated.height - 1);
  //   final textY2 = (textY1 + 14).clamp(0, annotated.height - 1);
  //   final textY3 = (textY2 + 14).clamp(0, annotated.height - 1);

  //   img.drawString(
  //     annotated,
  //     label,
  //     font: img.arial14,
  //     x: textX,
  //     y: textY1,
  //     color: color,
  //   );
  //   img.drawString(
  //     annotated,
  //     timeText,
  //     font: img.arial14,
  //     x: textX,
  //     y: textY2,
  //     color: img.ColorRgba8(255, 255, 255, 245),
  //   );
  //   img.drawString(
  //     annotated,
  //     cameraText,
  //     font: img.arial14,
  //     x: textX,
  //     y: textY3,
  //     color: img.ColorRgba8(255, 255, 255, 245),
  //   );

  //   final maxSide = math.max(annotated.width, annotated.height);
  //   final normalized = maxSide > 640
  //       ? img.copyResize(
  //           annotated,
  //           width: annotated.width >= annotated.height ? 640 : null,
  //           height: annotated.height > annotated.width ? 640 : null,
  //           interpolation: img.Interpolation.linear,
  //         )
  //       : annotated;
  //   final jpg = img.encodeJpg(normalized, quality: 80);
  //   return base64Encode(jpg);
  // }

  String _formatLogTimestamp(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min:$ss';
  }

  bool _publishRecognitionEvent(
    String cameraId,
    Rect ratio,
    RecognitionEvent event,
    int nowMs, {
    RecognitionEvent Function()? eventBuilder,
  }) {
    final eventKey = _eventThrottleKey(
      cameraId: cameraId,
      ratio: ratio,
      event: event,
    );
    if (_shouldThrottleEvent(eventKey, nowMs)) {
      return false;
    }
    final eventToPublish = eventBuilder?.call() ?? event;
    _ingestRealtimeEvent(eventToPublish, cameraId: cameraId, nowMs: nowMs);
    return true;
  }

  bool _shouldThrottleEvent(String eventKey, int nowMs) {
    final lastAt = _lastEventAt[eventKey] ?? 0;
    if (nowMs - lastAt < _eventPublishIntervalMs) {
      return true;
    }
    _lastEventAt[eventKey] = nowMs;
    return false;
  }

  String _eventThrottleKey({
    required String cameraId,
    Rect? ratio,
    required RecognitionEvent event,
  }) {
    if (!event.isStranger) {
      final id = (event.personId ?? '').trim();
      if (id.isNotEmpty) {
        return 'known|$cameraId|$id';
      }
      return 'known_name|$cameraId|${event.personName.toLowerCase()}';
    }

    final normalizedName = event.personName.toLowerCase().trim();
    if (ratio == null) {
      return 'stranger|$cameraId|$normalizedName';
    }
    final cx = (ratio.center.dx * 8).round();
    final cy = (ratio.center.dy * 8).round();
    return 'stranger|$cameraId|$normalizedName|$cx|$cy';
  }

  String _faceLogKeyFromRatio(Rect ratio) {
    // Use coarse quantization so the same moving face keeps a stable vote key.
    final cx = (ratio.center.dx * 40).round();
    final cy = (ratio.center.dy * 40).round();
    final size = (math.min(ratio.width, ratio.height) * 40).round();
    return '${cx}_${cy}_$size';
  }

  void _queueEventForDatabase(RecognitionEvent event) {
    _pendingDbEvents.add(event);
    if (_pendingDbEvents.length > _maxPendingDbEvents) {
      _pendingDbEvents.removeRange(
        0,
        _pendingDbEvents.length - _maxPendingDbEvents,
      );
    }
  }

  Future<void> _startRealtimeWebSocketHub() async {
    if (_realtimeWsServer != null) return;
    try {
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _realtimeWsPort,
        shared: true,
      );
      _realtimeWsServer = server;
      server.listen(_handleRealtimeWsHttpRequest);
      _log.info(
        'Realtime WS hub started at ws://0.0.0.0:$_realtimeWsPort$_realtimeWsPath',
      );
    } catch (e) {
      _log.error('Cannot start realtime WS hub: $e');
    }
  }

  void _handleRealtimeWsHttpRequest(HttpRequest request) {
    final path = request.uri.path;
    if (path != _realtimeWsPath ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = 404;
      request.response.close();
      return;
    }
    unawaited(_acceptRealtimeWsClient(request));
  }

  Future<void> _acceptRealtimeWsClient(HttpRequest request) async {
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _realtimeWsClients.add(socket);
      socket.listen(
        (message) => _handleRealtimeWsMessage(socket, message),
        onDone: () {
          _realtimeWsClients.remove(socket);
        },
        onError: (_) {
          _realtimeWsClients.remove(socket);
        },
        cancelOnError: true,
      );
    } catch (e) {
      _log.error('Realtime WS client upgrade failed: $e');
    }
  }

  void _handleRealtimeWsMessage(WebSocket socket, Object? message) {
    final raw = message?.toString().trim() ?? '';
    if (raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = decoded.cast<String, dynamic>();
      final type = map['type']?.toString() ?? 'recognition_event';
      if (type != 'recognition_event') return;

      final payloadRaw = map['payload'];
      if (payloadRaw is! Map) return;
      final payload = payloadRaw.cast<String, dynamic>();
      final incoming = RecognitionEvent(
        id: (payload['id']?.toString().trim().isNotEmpty ?? false)
            ? payload['id'].toString()
            : _uuid.v4(),
        personId: payload['person_id']?.toString(),
        personName: payload['person_name']?.toString() ?? 'Unknown',
        cameraId: payload['camera_id']?.toString(),
        confidence: (payload['confidence'] as num?)?.toDouble() ?? 0.0,
        isStranger:
            payload['is_stranger'] == true || payload['is_stranger'] == 1,
        createdAt:
            (payload['created_at'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        snapshotBase64: payload['snapshot_base64']?.toString() ?? '',
      );

      final throttleKey = _eventThrottleKey(
        cameraId: incoming.cameraId ?? 'external',
        event: incoming,
      );
      if (_shouldThrottleEvent(throttleKey, incoming.createdAt)) {
        return;
      }

      _ingestRealtimeEvent(
        incoming,
        cameraId: incoming.cameraId ?? 'external',
        nowMs: incoming.createdAt,
      );
      _broadcastRealtimeEvent(incoming, skip: socket);
    } catch (e) {
      _log.error('Realtime WS message parse failed: $e');
    }
  }

  void _ingestRealtimeEvent(
    RecognitionEvent event, {
    required String cameraId,
    required int nowMs,
  }) {
    _queueEventForDatabase(event);

    _realtimeEventCache.add(event);
    if (_realtimeEventCache.length > _maxRealtimeCacheEvents) {
      _realtimeEventCache.removeRange(
        0,
        _realtimeEventCache.length - _maxRealtimeCacheEvents,
      );
    }

    if (!_notiQueue.isClosed) {
      _notiQueue.add(
        FaceRecognitionNotification(cameraId: cameraId, event: event),
      );
    }

    // Persist quickly so DB-backed log list updates almost immediately.
    unawaited(_flushPendingEventsToDb());

    _broadcastRealtimeEvent(event);
  }

  void _broadcastRealtimeEvent(RecognitionEvent event, {WebSocket? skip}) {
    if (_realtimeWsClients.isEmpty) return;
    final sw = Stopwatch()..start();
    final payload = jsonEncode({
      'type': 'recognition_event',
      'payload': event.toMap(),
    });

    final dead = <WebSocket>[];
    for (final client in _realtimeWsClients) {
      if (skip != null && identical(client, skip)) continue;
      try {
        client.add(payload);
      } catch (_) {
        dead.add(client);
      }
    }
    for (final client in dead) {
      _realtimeWsClients.remove(client);
      unawaited(client.close());
    }
    sw.stop();
    if (_perfProbeEnabled && sw.elapsedMilliseconds >= 8) {
      _log.debug(
        'Perf[ws] broadcastMs=${sw.elapsedMilliseconds} clients=${_realtimeWsClients.length} payloadBytes=${payload.length}',
      );
    }
  }

  void _startDbFlushScheduler() {
    _dbFlushTimer?.cancel();
    _dbFlushTimer = Timer.periodic(_dbFlushInterval, (_) {
      unawaited(_flushPendingEventsToDb());
    });
  }

  Future<void> _flushPendingEventsToDb() async {
    if (_dbFlushInProgress || _pendingDbEvents.isEmpty) return;
    _dbFlushInProgress = true;
    final events = List<RecognitionEvent>.from(_pendingDbEvents);
    final sw = Stopwatch()..start();

    try {
      for (final event in events) {
        await FaceAttendanceRepository.addEvent(event);
      }
      if (_pendingDbEvents.length >= events.length) {
        _pendingDbEvents.removeRange(0, events.length);
      } else {
        _pendingDbEvents.clear();
      }
      sw.stop();
      if (_perfProbeEnabled) {
        final perEventMs = events.isEmpty
            ? 0.0
            : sw.elapsedMicroseconds / events.length / 1000.0;
        _log.info(
          'Perf[db] flushEvents=${events.length} flushMs=${sw.elapsedMilliseconds} avgPerEventMs=${perEventMs.toStringAsFixed(2)} pendingAfter=${_pendingDbEvents.length}',
        );
      }
    } catch (e) {
      _log.error('Flush pending recognition events failed error=$e');
    } finally {
      _dbFlushInProgress = false;
    }
  }

  double _rectIoU(Rect a, Rect b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    if (right <= left || bottom <= top) return 0.0;
    final intersection = (right - left) * (bottom - top);
    final union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0.0 : intersection / union;
  }

  double _rectCenterDistance(Rect a, Rect b) {
    final dx = a.center.dx - b.center.dx;
    final dy = a.center.dy - b.center.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  Future<List<double>> _embeddingFromImage(
    img.Image source, {
    bool alreadyPrepared = false,
    bool robust = false,
  }) async {
    final aligned = alreadyPrepared ? source : _prepareFaceForEmbedding(source);
    final session = _arcFaceSession;
    if (session == null) {
      return _vectorFromImage(aligned);
    }

    Future<List<double>> runArcFace(img.Image preparedInput) async {
      final resized = await _resizeWithOpenCvDart(preparedInput, 112, 112);
      final rgb = resized!.getBytes(order: img.ChannelOrder.rgb);
      final nchwInput = List<double>.filled(1 * 3 * 112 * 112, 0);
      final nhwcInput = List<double>.filled(1 * 112 * 112 * 3, 0);
      for (var y = 0; y < 112; y++) {
        for (var x = 0; x < 112; x++) {
          final pixelIndex = (y * 112 + x) * 3;
          final spatialIndex = y * 112 + x;
          final r = (rgb[pixelIndex] - 127.5) / 128.0;
          final g = (rgb[pixelIndex + 1] - 127.5) / 128.0;
          final b = (rgb[pixelIndex + 2] - 127.5) / 128.0;
          nchwInput[spatialIndex] = r;
          nchwInput[112 * 112 + spatialIndex] =
              (rgb[pixelIndex + 1] - 127.5) / 128.0;
          nchwInput[2 * 112 * 112 + spatialIndex] =
              (rgb[pixelIndex + 2] - 127.5) / 128.0;

          final nhwcIndex = spatialIndex * 3;
          nhwcInput[nhwcIndex] = r;
          nhwcInput[nhwcIndex + 1] = g;
          nhwcInput[nhwcIndex + 2] = b;
        }
      }

      Future<Map<String, OrtValue?>> runWithLayout(bool nhwc) async {
        final input = nhwc ? nhwcInput : nchwInput;
        final shape = nhwc ? const [1, 112, 112, 3] : const [1, 3, 112, 112];
        final inputs = {
          _arcFaceInputName: await OrtValue.fromList(input, shape),
        };
        return session.run(inputs);
      }

      Map<String, OrtValue?> outputs;
      final preferredLayout = _arcFaceInputIsNhwc;
      if (preferredLayout != null) {
        outputs = await runWithLayout(preferredLayout);
      } else {
        try {
          outputs = await runWithLayout(false);
          _arcFaceInputIsNhwc = false;
        } catch (e) {
          final message = e.toString().toLowerCase();
          final likelyShapeMismatch =
              message.contains('invalid dimensions') ||
              message.contains('got: 3 expected: 112') ||
              message.contains('input_1');
          if (!likelyShapeMismatch) {
            rethrow;
          }
          outputs = await runWithLayout(true);
          _arcFaceInputIsNhwc = true;
          _log.info('ArcFace input layout auto-detected: NHWC');
        }
      }

      final output =
          outputs[_arcFaceOutputName] ??
          (outputs.isNotEmpty ? outputs.values.first : null);
      final values = output == null ? const <dynamic>[] : await output.asList();
      final flattened = <double>[];
      _flattenNumericValues(values, flattened);
      if (flattened.isEmpty) {
        return const <double>[];
      }

      final vector = flattened.length > 512
          ? flattened.sublist(flattened.length - 512)
          : flattened;
      return _normalizeVector(vector);
    }

    try {
      final primaryVector = await runArcFace(aligned);
      if (primaryVector.isEmpty) {
        if (_onnxFallbackCount < 5) {
          _onnxFallbackCount++;
          _log.error('ArcFace output flatten failed, fallback vector used');
        }
        return _vectorFromImage(aligned);
      }

      if (!robust || !_shouldUseRobustEmbedding(aligned)) {
        return primaryVector;
      }

      final flipped = img.flipHorizontal(aligned);
      final secondaryVector = await runArcFace(flipped);
      if (secondaryVector.isEmpty) {
        return primaryVector;
      }

      return _fuseVectorsNormalized(primaryVector, secondaryVector);
    } catch (e) {
      if (_onnxFallbackCount < 5) {
        _onnxFallbackCount++;
        _log.error('ArcFace inference failed, fallback vector used error=$e');
      }
      return _vectorFromImage(aligned);
    }
  }

  bool _shouldUseRobustEmbedding(img.Image preparedFace) {
    final side = math.min(preparedFace.width, preparedFace.height).toDouble();
    final luma = _averageLuma(preparedFace);
    final sharpness = _imageSharpness(preparedFace);
    return side < 92 ||
        side > 216 ||
        luma < 0.34 ||
        luma > 0.76 ||
        sharpness < 24.0;
  }

  List<double> _normalizeVector(List<double> vector) {
    if (vector.isEmpty) return vector;
    final normalized = List<double>.from(vector);
    final norm = math.sqrt(normalized.fold<double>(0, (sum, v) => sum + v * v));
    if (norm <= 0) return normalized;
    for (var i = 0; i < normalized.length; i++) {
      normalized[i] = normalized[i] / norm;
    }
    return normalized;
  }

  List<double>? _computeGlobalMeanDirection(List<face_template.FaceTemplate> templates) {
    if (templates.isEmpty) return null;
    final dimension = templates.first.vector.length;
    if (dimension <= 0) return null;

    final sum = List<double>.filled(dimension, 0.0);
    var count = 0;
    for (final template in templates) {
      if (template.vector.length != dimension) continue;
      for (var i = 0; i < dimension; i++) {
        sum[i] += template.vector[i];
      }
      count++;
    }
    if (count <= 0) return null;

    for (var i = 0; i < dimension; i++) {
      sum[i] /= count;
    }
    final normalized = _normalizeVector(sum);
    return normalized.isEmpty ? null : normalized;
  }

  double _debiasedCosine(List<double> a, List<double> b) {
    final raw = HnswVectorIndex().dotProduct(a, b);
    final mean = _globalMeanDirection;
    if (mean == null || mean.isEmpty) {
      return raw.clamp(-1.0, 1.0).toDouble();
    }

    final centered = _centeredCosine(a, b, mean);
    if (centered == null) {
      return raw.clamp(-1.0, 1.0).toDouble();
    }

    // Blend raw and centered cosine to reduce common-direction bias without
    // collapsing scores when the centered projection is unstable.
    final blendWeight = ((raw - 0.55) / 0.35).clamp(0.10, 0.40).toDouble();
    var blended = raw * (1.0 - blendWeight) + centered * blendWeight;

    final minAllowed = (raw - 0.10).clamp(-1.0, 1.0);
    final maxAllowed = (raw + 0.06).clamp(-1.0, 1.0);
    if (blended < minAllowed) blended = minAllowed;
    if (blended > maxAllowed) blended = maxAllowed;
    return blended.clamp(-1.0, 1.0).toDouble();
  }

  double? _centeredCosine(List<double> a, List<double> b, List<double> mean) {
    final len = math.min(math.min(a.length, b.length), mean.length);
    if (len <= 0) return null;

    var projA = 0.0;
    var projB = 0.0;
    for (var i = 0; i < len; i++) {
      projA += a[i] * mean[i];
      projB += b[i] * mean[i];
    }

    var dot = 0.0;
    var normA2 = 0.0;
    var normB2 = 0.0;
    for (var i = 0; i < len; i++) {
      final ca = a[i] - mean[i] * projA;
      final cb = b[i] - mean[i] * projB;
      dot += ca * cb;
      normA2 += ca * ca;
      normB2 += cb * cb;
    }

    final denom = math.sqrt(normA2) * math.sqrt(normB2);
    if (denom <= 1e-8 || !denom.isFinite) {
      return null;
    }
    final centered = dot / denom;
    if (!centered.isFinite) return null;
    return centered.clamp(-1.0, 1.0).toDouble();
  }

  String _vectorStats(List<double> vector) {
    if (vector.isEmpty) return 'empty';
    var minV = vector.first;
    var maxV = vector.first;
    var sum = 0.0;
    var norm2 = 0.0;
    for (final value in vector) {
      if (value < minV) minV = value;
      if (value > maxV) maxV = value;
      sum += value;
      norm2 += value * value;
    }
    final mean = sum / vector.length;
    final norm = math.sqrt(norm2);
    return 'len=${vector.length} norm=${norm.toStringAsFixed(4)} '
        'min=${minV.toStringAsFixed(4)} max=${maxV.toStringAsFixed(4)} '
        'mean=${mean.toStringAsFixed(4)}';
  }

  String _vectorPreview(List<double> vector, {int maxItems = 10}) {
    if (vector.isEmpty) return '[]';
    final end = math.min(maxItems, vector.length);
    final head = vector
        .take(end)
        .map((value) => value.toStringAsFixed(4))
        .join(',');
    return '[$head${vector.length > end ? ',...' : ''}]';
  }

  List<double> _fuseVectorsNormalized(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    if (n <= 0) return const <double>[];
    final fused = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      fused[i] = (a[i] + b[i]) * 0.5;
    }
    return _normalizeVector(fused);
  }

  img.Image _prepareFaceForEmbedding(img.Image source) {
    final square = _centerCropSquare(source);
    final monochrome = img.grayscale(square);
    final sharpness = _imageSharpness(monochrome);
    final sharpenAmount = sharpness < 18.0
        ? 0.60
        : sharpness < 28.0
        ? 0.30
        : 0.0;
    final processed = sharpenAmount > 0.0
        ? _sharpenFaceCrop(monochrome, sharpenAmount)
        : monochrome;
    return _materializeRgba8Image(processed);
  }

  img.Image _materializeRgba8Image(img.Image source) {
    final rgba = source.getBytes(order: img.ChannelOrder.rgba);
    final output = img.Image(width: source.width, height: source.height);
    var index = 0;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        output.setPixelRgba(
          x,
          y,
          rgba[index],
          rgba[index + 1],
          rgba[index + 2],
          rgba[index + 3],
        );
        index += 4;
      }
    }
    return output;
  }

  img.Image _boostRealtimeFaceExposure(img.Image source, double luminance) {
    return source;
  }

  img.Image _applyRealtimeInputProcessing(img.Image source) {
    final adjusted = img.grayscale(source);
    return _materializeRgba8Image(adjusted);
  }

  img.Image _applyAutoTuneRealtimeInputProcessing(
    img.Image source,
    double autoSharpenAmount,
  ) {
    if (!_enableRealtimeAutoSharpen) {
      return source;
    }

    final adjusted = img.grayscale(source);

    final sharpenAmount = autoSharpenAmount
        .clamp(0.0, _autoTuneMaxSharpenAmount.clamp(0.0, 1.0))
        .toDouble();
    if (sharpenAmount <= 0.01) {
      return _materializeRgba8Image(adjusted);
    }
    return _materializeRgba8Image(_sharpenFaceCrop(adjusted, sharpenAmount));
  }

  double _computeRealtimeAutoSharpenAmount({
    required double sharpnessQuality,
    required double lumaStdDev,
  }) {
    if (!_enableRealtimeAutoSharpen) {
      return 0.0;
    }
    final lowContrastSeverity = ((0.13 - lumaStdDev).clamp(0.0, 0.13) / 0.13)
        .clamp(0.0, 1.0)
        .toDouble();
    final blurSeverity = ((0.42 - sharpnessQuality).clamp(0.0, 0.42) / 0.42)
        .clamp(0.0, 1.0)
        .toDouble();
    return (blurSeverity * 0.86 + lowContrastSeverity * 0.22)
        .clamp(0.0, _autoTuneMaxSharpenAmount.clamp(0.0, 1.0))
        .toDouble();
  }

  img.Image _sharpenFaceCrop(img.Image source, double amount) {
    final safeAmount = amount.clamp(0.0, 1.0).toDouble();
    if (safeAmount <= 0.0) {
      return source;
    }

    final blurred = img.gaussianBlur(img.Image.from(source), radius: 1);
    final out = img.Image.from(source);
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final p = source.getPixel(x, y);
        final b = blurred.getPixel(x, y);

        int sharpenChannel(int orig, int blur) {
          final boosted = orig + (orig - blur) * safeAmount;
          return boosted.round().clamp(0, 255);
        }

        out.setPixelRgba(
          x,
          y,
          sharpenChannel(p.r.toInt(), b.r.toInt()),
          sharpenChannel(p.g.toInt(), b.g.toInt()),
          sharpenChannel(p.b.toInt(), b.b.toInt()),
          p.a.toInt(),
        );
      }
    }
    return out;
  }

  void _flattenNumericValues(dynamic value, List<double> out) {
    if (value is num) {
      out.add(value.toDouble());
      return;
    }
    if (value is List) {
      for (final element in value) {
        _flattenNumericValues(element, out);
      }
    }
  }

  double _imageSharpness(img.Image image) {
    final gray = img.grayscale(image);
    final width = gray.width;
    final height = gray.height;
    if (width < 3 || height < 3) return 0.0;

    final values = List<double>.filled((width - 2) * (height - 2), 0.0);
    var index = 0;

    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final c = gray.getPixel(x, y).r.toDouble();
        final l = gray.getPixel(x - 1, y).r.toDouble();
        final r = gray.getPixel(x + 1, y).r.toDouble();
        final t = gray.getPixel(x, y - 1).r.toDouble();
        final b = gray.getPixel(x, y + 1).r.toDouble();
        values[index++] = (4 * c - l - r - t - b);
      }
    }

    if (values.isEmpty) return 0.0;
    var mean = 0.0;
    for (final v in values) {
      mean += v;
    }
    mean /= values.length;

    var variance = 0.0;
    for (final v in values) {
      final d = v - mean;
      variance += d * d;
    }
    variance /= values.length;
    return variance;
  }

  double _lumaStdDev(img.Image image, [double? mean]) {
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0) return 0.0;
    final m = mean ?? _averageLuma(image);
    var accum = 0.0;
    final total = width * height;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = image.getPixel(x, y);
        final luma = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
        final d = luma - m;
        accum += d * d;
      }
    }
    return math.sqrt(accum / math.max(1, total));
  }

  void _emitFrame(String cameraId, List<FaceOverlayBox> overlays) {
    _emitFrameWithImage(
      cameraId,
      overlays,
      trackStats: null,
      workerStats: null,
      annotatedFrameJpeg: null,
    );
  }

  void _emitFrameWithImage(
    String cameraId,
    List<FaceOverlayBox> overlays, {
    CameraTrackRuntimeStats? trackStats,
    CameraWorkerRuntimeStats? workerStats,
    Uint8List? annotatedFrameJpeg,
    Uint8List? annotatedOverlayPng,
  }) {
    if (_frameQueue.isClosed) return;
    final processor = _processorsByCameraId[cameraId];
    _frameQueue.add(
      RecognitionFramePacket(
        cameraId: cameraId,
        overlays: overlays,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        trackStats: trackStats,
        workerStats: workerStats,
        inputFps: processor?.inputFpsEma ?? 0.0,
        recognitionFps: processor?.recognitionFpsEma ?? 0.0,
        annotatedFrameJpeg: annotatedFrameJpeg,
        annotatedOverlayPng: annotatedOverlayPng,
      ),
    );
  }

  void _markInputFrame(_Processor processor, int nowMs) {
    final previous = processor.lastInputFrameAtMs;
    processor.lastInputFrameAtMs = nowMs;
    if (previous <= 0 || nowMs <= previous) {
      return;
    }
    final deltaMs = nowMs - previous;
    if (deltaMs <= 0) {
      return;
    }
    final instant = 1000.0 / deltaMs;
    processor.inputFpsEma = processor.inputFpsEma <= 0
        ? instant
        : (processor.inputFpsEma * 0.85) + (instant * 0.15);
  }

  void _markRecognitionFrame(_Processor processor, int nowMs) {
    final previous = processor.lastRecognitionFrameAtMs;
    processor.lastRecognitionFrameAtMs = nowMs;
    if (previous <= 0 || nowMs <= previous) {
      return;
    }
    final deltaMs = nowMs - previous;
    if (deltaMs <= 0) {
      return;
    }
    final instant = 1000.0 / deltaMs;
    processor.recognitionFpsEma = processor.recognitionFpsEma <= 0
        ? instant
        : (processor.recognitionFpsEma * 0.85) + (instant * 0.15);
  }

  Uint8List? _maybeBuildOverlayPng(
    _Processor? processor,
    img.Image rgb,
    List<FaceOverlayBox> overlays,
    RecognitionZone zone,
    int nowMs,
  ) {
    if (processor == null) {
      return _buildOverlayPng(rgb.width, rgb.height, overlays, zone);
    }

    final intervalMs = _overlayRenderIntervalMs(overlays.length);
    if (nowMs - processor.lastAnnotatedFrameAtMs < intervalMs) {
      return null;
    }

    final signature = _overlaySignature(overlays, zone);
    final cached = processor.lastOverlayPng;
    if (signature == processor.lastOverlaySignature &&
        cached != null &&
        cached.isNotEmpty) {
      processor.lastAnnotatedFrameAtMs = nowMs;
      return cached;
    }

    final rebuilt = _buildOverlayPng(rgb.width, rgb.height, overlays, zone);
    if (rebuilt != null && rebuilt.isNotEmpty) {
      processor.lastAnnotatedFrameAtMs = nowMs;
      processor.lastOverlaySignature = signature;
      processor.lastOverlayPng = rebuilt;
    }
    return rebuilt;
  }

  String _overlaySignature(
    List<FaceOverlayBox> overlays,
    RecognitionZone zone,
  ) {
    final parts = <String>[];
    for (final overlay in overlays) {
      parts.add(
        '${overlay.event.isStranger ? 'S' : 'K'}:'
        '${(overlay.rectRatio.left * 200).round()},'
        '${(overlay.rectRatio.top * 200).round()},'
        '${(overlay.rectRatio.width * 200).round()},'
        '${(overlay.rectRatio.height * 200).round()},'
        '${(overlay.event.confidence * 20).round()},'
        '${overlay.event.personId ?? overlay.event.personName},'
        '${overlay.debugLabel ?? ''}',
      );
    }
    parts.sort();
    return 'v$_overlayRendererVersion-'
        '${zone.enabled ? 1 : 0}-'
        '${(zone.leftRatio * 100).round()}-'
        '${(zone.topRatio * 100).round()}-'
        '${(zone.widthRatio * 100).round()}-'
        '${(zone.heightRatio * 100).round()}-'
        '${zone.rotationDegrees.round()}-'
        '${parts.join('|')}';
  }

  int _overlayRenderIntervalMs(int overlaysCount) {
    var interval = _annotatedFrameMinIntervalMs;
    if (!_debugRealtimeOverlay) {
      interval += 60;
    }
    if (overlaysCount >= 2) {
      interval += 40;
    }
    return interval.clamp(80, 420);
  }

  Uint8List? _buildOverlayPng(
    int frameWidth,
    int frameHeight,
    List<FaceOverlayBox> overlays,
    RecognitionZone zone,
  ) {
    try {
      final overlay = img.Image(
        width: frameWidth,
        height: frameHeight,
        numChannels: 4,
      );
      const stroke = 2;

      if (zone.enabled) {
        final corners = _zoneCornersPx(zone, frameWidth, frameHeight);
        _drawPolygonStrokeManual(
          overlay,
          points: corners,
          color: img.ColorRgba8(255, 215, 0, 235),
          thickness: stroke,
        );
      }

      for (final faceOverlay in overlays) {
        final ratio = faceOverlay.rectRatio;
        final rawLeft = (ratio.left * frameWidth).floor();
        final rawTop = (ratio.top * frameHeight).floor();
        final rawRight = (ratio.right * frameWidth).ceil() - 1;
        final rawBottom = (ratio.bottom * frameHeight).ceil() - 1;
        final drawLeft = (rawLeft + _bboxOverlayOffsetXPx).clamp(
          0,
          frameWidth - 1,
        );
        final drawTop = rawTop.clamp(0, frameHeight - 1);
        final drawRight = (rawRight + _bboxOverlayOffsetXPx).clamp(
          drawLeft,
          frameWidth - 1,
        );
        final drawBottom = rawBottom.clamp(drawTop, frameHeight - 1);
        final boxWidth = drawRight - drawLeft + 1;
        final boxHeight = drawBottom - drawTop + 1;
        final bboxStroke = (boxWidth <= 5 || boxHeight <= 5) ? 1 : stroke;

        final isStranger = faceOverlay.event.isStranger;
        final color = isStranger
            ? img.ColorRgba8(255, 165, 0, 235)
            : img.ColorRgba8(120, 235, 0, 235);
        _drawRectStrokeManual(
          overlay,
          left: drawLeft,
          top: drawTop,
          right: drawRight,
          bottom: drawBottom,
          color: color,
          thickness: bboxStroke,
        );

        // Realtime debug text is rendered by Flutter widgets on top of the preview
        // so it is not affected by front-camera mirroring.
      }

      return Uint8List.fromList(img.encodePng(overlay));
    } catch (e) {
      _log.debug('Overlay PNG render failed errorType=${e.runtimeType}');
      return null;
    }
  }

  void _drawRectStrokeManual(
    img.Image image, {
    required int left,
    required int top,
    required int right,
    required int bottom,
    required img.Color color,
    int thickness = 2,
  }) {
    final x1 = left.clamp(0, image.width - 1);
    final y1 = top.clamp(0, image.height - 1);
    final x2 = right.clamp(x1, image.width - 1);
    final y2 = bottom.clamp(y1, image.height - 1);
    final t = thickness.clamp(1, 8);

    for (var i = 0; i < t; i++) {
      final lx = (x1 + i).clamp(0, image.width - 1);
      final rx = (x2 - i).clamp(lx, image.width - 1);
      final ty = (y1 + i).clamp(0, image.height - 1);
      final by = (y2 - i).clamp(ty, image.height - 1);

      for (var x = lx; x <= rx; x++) {
        image.setPixelRgba(x, ty, color.r, color.g, color.b, color.a);
        image.setPixelRgba(x, by, color.r, color.g, color.b, color.a);
      }
      for (var y = ty; y <= by; y++) {
        image.setPixelRgba(lx, y, color.r, color.g, color.b, color.a);
        image.setPixelRgba(rx, y, color.r, color.g, color.b, color.a);
      }
    }
  }

  List<Offset> _zoneCornersPx(RecognitionZone zone, int width, int height) {
    final left = zone.leftRatio * width;
    final top = zone.topRatio * height;
    final w = zone.widthRatio * width;
    final h = zone.heightRatio * height;
    final center = Offset(left + w / 2, top + h / 2);
    final angle = zone.rotationDegrees * math.pi / 180;

    Offset rotate(Offset point) {
      final dx = point.dx - center.dx;
      final dy = point.dy - center.dy;
      final rx = center.dx + dx * math.cos(angle) - dy * math.sin(angle);
      final ry = center.dy + dx * math.sin(angle) + dy * math.cos(angle);
      return Offset(rx, ry);
    }

    return <Offset>[
      rotate(Offset(left, top)),
      rotate(Offset(left + w, top)),
      rotate(Offset(left + w, top + h)),
      rotate(Offset(left, top + h)),
    ];
  }

  void _drawPolygonStrokeManual(
    img.Image image, {
    required List<Offset> points,
    required img.Color color,
    int thickness = 2,
  }) {
    if (points.length < 2) return;
    for (var i = 0; i < points.length; i++) {
      final from = points[i];
      final to = points[(i + 1) % points.length];
      _drawLineStrokeManual(
        image,
        from: from,
        to: to,
        color: color,
        thickness: thickness,
      );
    }
  }

  void _drawLineStrokeManual(
    img.Image image, {
    required Offset from,
    required Offset to,
    required img.Color color,
    int thickness = 2,
  }) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final steps = math.max(dx.abs(), dy.abs()).ceil().clamp(1, 4096);
    final t = thickness.clamp(1, 8);

    for (var i = 0; i <= steps; i++) {
      final ratio = i / steps;
      final x = (from.dx + dx * ratio).round();
      final y = (from.dy + dy * ratio).round();
      for (var ox = -t ~/ 2; ox <= t ~/ 2; ox++) {
        for (var oy = -t ~/ 2; oy <= t ~/ 2; oy++) {
          final px = (x + ox).clamp(0, image.width - 1);
          final py = (y + oy).clamp(0, image.height - 1);
          image.setPixelRgba(px, py, color.r, color.g, color.b, color.a);
        }
      }
    }
  }

  bool _updateAdaptiveFarDistanceMode(
    String cameraId,
    double faceAreaRatio,
    int minFacePixels,
    int nowMs,
  ) {
    final state = _adaptiveDistanceStates.putIfAbsent(
      cameraId,
      () => _AdaptiveDistanceState(),
    );

    final smallByArea =
        faceAreaRatio <= math.max(_minRealtimeFaceAreaRatio * 0.90, 0.018);
    final smallByPixels =
        minFacePixels <= math.max((_minRealtimeFacePixels * 0.88).round(), 44);
    final farCandidate =
        faceAreaRatio <= math.max(_minRealtimeFaceAreaRatio * 0.62, 0.010) ||
        minFacePixels <= math.max((_minRealtimeFacePixels * 0.74).round(), 36);

    if (farCandidate) {
      state.smallFaceStreak += 2;
    } else if (smallByArea || smallByPixels) {
      state.smallFaceStreak += 1;
    } else {
      state.smallFaceStreak = math.max(0, state.smallFaceStreak - 1);
    }

    if (state.smallFaceStreak >= _adaptiveFarDistanceActivationStreak) {
      state.activeUntilMs = nowMs + _adaptiveFarDistanceActiveMs;
    }

    final active = nowMs <= state.activeUntilMs;
    if (active != state.lastActive && nowMs - state.lastLogAtMs >= 1000) {
      state.lastActive = active;
      state.lastLogAtMs = nowMs;
      _log.info(
        'Adaptive far-distance ${active ? 'enabled' : 'disabled'} camera=$cameraId streak=${state.smallFaceStreak} faceArea=${faceAreaRatio.toStringAsFixed(4)} minSide=$minFacePixels',
      );
    }

    return active;
  }

  bool _shouldUseRobustRealtimeEmbedding({
    required int minFacePixels,
    required double faceAreaRatio,
    required double frameQuality,
    required bool adaptiveFarDistance,
  }) {
    if (adaptiveFarDistance) {
      return false;
    }
    return minFacePixels >= 72 &&
        faceAreaRatio >= 0.026 &&
        frameQuality >= 0.56;
  }

  bool _shouldComputeRealtimePartials({
    required int minFacePixels,
    required double faceAreaRatio,
    required double frameQuality,
    required bool adaptiveFarDistance,
    required int frameIndex,
  }) {
    if (_realtimePartialMode == _realtimePartialModeDisabled) {
      return false;
    }
    final cycle = _realtimePartialFrameCycle.clamp(1, 8).toInt();
    if (cycle > 1 && frameIndex > 0 && frameIndex % cycle != 0) {
      return false;
    }

    if (_realtimePartialMode == _realtimePartialModeAllFrames) {
      return true;
    }

    final qualityGate = _realtimePartialMinFrameQuality.clamp(0.0, 1.0);
    final areaGate = _realtimePartialMinFaceAreaRatio.clamp(0.0, 1.0);
    final pixelGate = _realtimePartialMinFacePixels.clamp(1, 4096).toInt();

    if (frameQuality < qualityGate) {
      return false;
    }
    if (faceAreaRatio < areaGate || minFacePixels < pixelGate) {
      return false;
    }
    if (adaptiveFarDistance && minFacePixels < 56) {
      return false;
    }
    return true;
  }

  void _logRealtimeDecisionTrace({
    required String cameraId,
    required String faceLogKey,
    required _MatchResult? match,
    required bool isKnown,
    required double frameQuality,
  }) {
    if (!_traceLogsEnabled) {
      return;
    }
    if (match == null) {
      _log.debug(
        'DecisionTrace camera=$cameraId face=$faceLogKey known=false reason=no_match '
        'q=${frameQuality.toStringAsFixed(2)}',
      );
      return;
    }

    _log.debug(
      'DecisionTrace camera=$cameraId face=$faceLogKey known=$isKnown '
      'person=${match.template.person.name} id=${match.template.person.id} '
      'score=${match.score.toStringAsFixed(3)} cal=${match.calibratedScore.toStringAsFixed(3)} '
      'tpl=${match.templateScore.toStringAsFixed(3)} partial=${match.partialScore.toStringAsFixed(3)} '
      'partialCov=${match.partialCoverage.toStringAsFixed(2)} ctr=${match.centroidScore.toStringAsFixed(3)} '
      'margin=${match.margin.toStringAsFixed(3)} q=${frameQuality.toStringAsFixed(2)}',
    );
  }

  double _candidateDecisionScore(
    _CandidateScore candidate, {
    required double frameQuality,
  }) {
    final qualityWeight = (0.88 + frameQuality * 0.12).clamp(0.88, 1.0);
    final partialWeight = (0.90 + candidate.partialCoverage * 0.10).clamp(
      0.90,
      1.0,
    );
    final calibratedForDecision = candidate.calibratedScore
        .clamp(-0.30, 1.08)
        .toDouble();
    final baseScore =
        calibratedForDecision * 0.16 +
        candidate.blendedScore * 0.46 +
        candidate.templateScore * 0.24 +
        candidate.partialScore * 0.14;
    final partialBonus =
        candidate.partialScore * candidate.partialCoverage * 0.05;
    final weighted = (baseScore + partialBonus) * qualityWeight * partialWeight;
    return weighted.clamp(-0.98, 0.98).toDouble();
  }

  _MatchResult? _findBestMatch(
    List<double> vector, {
    _PartialEmbeddingBundle? partialBundle,
    Set<String>? excludedPersonIds,
    double frameQuality = 1.0,
    String? cameraId,
    String? faceLogKey,
  }) {
    if (_knownRecognitionBlockedByMissingTemplateCache && cameraId != null) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final lastAt = _missingTemplateGuardLogAtByCameraId[cameraId] ?? 0;
      if (nowMs - lastAt >= 3000) {
        _missingTemplateGuardLogAtByCameraId[cameraId] = nowMs;
        _log.info(
          'Recognition degraded camera=$cameraId face=${faceLogKey ?? '-'} '
          'reason=missing_template_cache missingPeople=$_missingTemplatePeopleCount '
          'sample=[$_missingTemplatePeoplePreview]',
        );
      }
    }

    final excluded = excludedPersonIds ?? const <String>{};
    final results = HnswVectorIndex().query(
      vector,
      maxResults: 10,
      threshold: _knownMatchThreshold,
      sortByScore: true,
      descending: true,
      uniquePerPerson: false,
      advancedSearch: false,
    );
    // nếu không có kết quả thì đi tiếp như cũ
    if (results.isNotEmpty) {
      // gom theo person
      final scoresByPerson = <String, List<double>>{};
      for (final r in results) {
        scoresByPerson.putIfAbsent(r.template.person.id, () => []).add(r.score);
      }

      // tính trung bình
      final avgScores = scoresByPerson.map(
        (pid, list) => MapEntry(pid, list.reduce((a, b) => a + b) / list.length),
      );

      // sắp xếp theo điểm trung bình
      final sortedPersons = avgScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final best = sortedPersons.first;
      final second = sortedPersons.length > 1 ? sortedPersons[1] : null;
      final margin = second == null ? best.value : best.value - second.value;

      // nếu score của best đủ lớn => ngưỡng quyết định ngay và margin đủ lớn thì chấp nhận ngay
      if (best.value >= _knownCalibratedThreshold && margin >= _knownMatchMargin) {
        return _MatchResult(
          template: results.firstWhere((r) => r.template.person.id == best.key).template,
          score: best.value,
          calibratedScore: best.value,
          margin: margin,
          templateScore: best.value,
          globalScore: best.value,
          partialScore: 0.0,
          partialCoverage: 0.0,
          eyeWeight: 0.0,
          noseWeight: 0.0,
          mouthWeight: 0.0,
          centroidScore: best.value,
          dualConsensus: true,
        );
      }
    } else{
      return null;
    }

    final totalPersons = PersonScoreBucket().templatesByPersonId.length;

    Set<String>? candidatePersonIds = {};
    var usedIndexedPruning = false;
    if (results.isNotEmpty) {
      for (final item in results) {
        if (excluded.contains(item.template.person.id)) continue;
        candidatePersonIds.add(item.template.person.id);
      }
      if (candidatePersonIds.length >= 80 && totalPersons >= 200) {
        final augmented = <String>{...candidatePersonIds};
        augmented.addAll(
          _topCentroidCandidateIds(
            vector,
            excluded: excluded,
            limit: math.min(96, math.max(24, totalPersons ~/ 6)),
          ),
        );
        final minCoverage = math.min(
          totalPersons,
          math.max(120, totalPersons ~/ 2),
        );
        if (augmented.length >= minCoverage) {
          candidatePersonIds = augmented;
          usedIndexedPruning = true;
        }
      }
    }

    final Iterable<PersonScoreBucket> searchBuckets =
        candidatePersonIds
              .map((id) => PersonScoreBucket().templatesByPersonId[id])
              .whereType<PersonScoreBucket>();
    final probePartials = partialBundle ?? const _PartialEmbeddingBundle();
    final scoredBuckets = searchBuckets.where(
      (bucket) =>
          bucket.templates.isNotEmpty && !excluded.contains(bucket.person.id),
    );
    final candidates = _scoreCandidateBuckets(
      vector,
      buckets: scoredBuckets,
      partialBundle: partialBundle,
      frameQuality: frameQuality,
    );

    if (candidates.isEmpty) return null;

    final bestByTemplate = candidates.reduce(
      (a, b) => a.templateScore >= b.templateScore ? a : b,
    );
    final bestByCentroid = candidates.reduce(
      (a, b) => a.centroidScore >= b.centroidScore ? a : b,
    );

    final sorted = [...candidates]
      ..sort((a, b) => b.blendedScore.compareTo(a.blendedScore));
    final top1 = sorted.first;
    final top2 = sorted.length > 1 ? sorted[1] : null;
    final best = top1;
    final secondBest = top2;
    final bestScore = best.blendedScore;
    final secondScore = secondBest == null ? 0.0 : secondBest.blendedScore;
    final margin = bestScore - secondScore;
    final matchThreshold = _knownMatchThreshold;

    final templateConsensus =
        bestByTemplate.bucket.person.id == best.bucket.person.id;
    final centroidConsensus =
        bestByCentroid.bucket.person.id == best.bucket.person.id;
    final dualConsensus = templateConsensus && centroidConsensus;

    final accepted = bestScore >= matchThreshold;

    if (!accepted) {
      if (_traceLogsEnabled) {
        _log.debug(
          'Match decision camera=$cameraId face=${faceLogKey ?? '-'} accepted=false '
          'reason=raw '
          'top1=${top1.bucket.person.name}:${top1.templateScore.toStringAsFixed(3)}/'
          '${top1.calibratedScore.toStringAsFixed(3)}/'
          'b${top1.blendedScore.toStringAsFixed(3)}/'
          'd${top1.decisionScore.toStringAsFixed(3)} '
          'top2=${top2?.bucket.person.name ?? '-'}:'
          '${top2?.templateScore.toStringAsFixed(3) ?? '-1.000'}/'
          '${top2?.calibratedScore.toStringAsFixed(3) ?? '-1.000'}/'
          'b${top2?.blendedScore.toStringAsFixed(3) ?? '-1.000'}/'
          'd${top2?.decisionScore.toStringAsFixed(3) ?? '-1.000'} '
          'margin=${margin.toStringAsFixed(3)} '
          'thresholds(raw=${matchThreshold.toStringAsFixed(3)}) '
          'q=${frameQuality.toStringAsFixed(3)} '
          'candidates=${candidates.length} '
          'indexed=$usedIndexedPruning',
        );
      }
      if (_detailedScoreVectorLogging) {
        _log.debug(
          'Match vectors accepted=false camera=$cameraId face=${faceLogKey ?? '-'} '
          'probe=${_vectorStats(vector)} probeHead=${_vectorPreview(vector)} '
          'bestPerson=${best.template.person.name} best=${_vectorStats(best.template.vector)} '
          'bestHead=${_vectorPreview(best.template.vector)}',
        );
      }

      return null;
    }

    if (_traceLogsEnabled) {
      _log.debug(
        'Match decision camera=$cameraId face=${faceLogKey ?? '-'} accepted=true '
        'top1=${top1.bucket.person.name}:${top1.templateScore.toStringAsFixed(3)}/'
        '${top1.calibratedScore.toStringAsFixed(3)}/'
        'b${top1.blendedScore.toStringAsFixed(3)}/'
        'd${top1.decisionScore.toStringAsFixed(3)} '
        'top2=${top2?.bucket.person.name ?? '-'}:'
        '${top2?.templateScore.toStringAsFixed(3) ?? '-1.000'}/'
        '${top2?.calibratedScore.toStringAsFixed(3) ?? '-1.000'}/'
        'b${top2?.blendedScore.toStringAsFixed(3) ?? '-1.000'}/'
        'd${top2?.decisionScore.toStringAsFixed(3) ?? '-1.000'} '
        'margin=${margin.toStringAsFixed(3)} '
        'q=${frameQuality.toStringAsFixed(3)} '
        'personId=${best.template.person.id} '
        'person=${best.template.person.name} '
        'candidates=${candidates.length} '
        'indexed=$usedIndexedPruning',
      );
    }
    if (_detailedScoreVectorLogging) {
      _log.debug(
        'Match vectors accepted=true camera=$cameraId face=${faceLogKey ?? '-'} '
        'probe=${_vectorStats(vector)} probeHead=${_vectorPreview(vector)} '
        'bestPerson=${best.template.person.name} best=${_vectorStats(best.template.vector)} '
        'bestHead=${_vectorPreview(best.template.vector)}',
      );
    }

    return _MatchResult(
      template: best.template,
      score: bestScore,
      calibratedScore: bestScore,
      margin: margin,
      templateScore: best.templateScore,
      globalScore:
          (best.templateScore * 0.55 +
                  best.multiPoseScore * 0.30 +
                  best.centroidScore * 0.15)
              .clamp(-1.0, 1.0)
              .toDouble(),
      partialScore: best.partialScore,
      partialCoverage: best.partialCoverage,
      eyeWeight: probePartials.eyeWeight,
      noseWeight: probePartials.noseWeight,
      mouthWeight: probePartials.mouthWeight,
      centroidScore: best.centroidScore,
      dualConsensus: dualConsensus,
    );
  }

  Set<String> _topCentroidCandidateIds(
    List<double> vector, {
    required Set<String> excluded,
    required int limit,
  }) {
    if (limit <= 0) return const <String>{};
    final scored = <(String, double)>[];
    for (final bucket in PersonScoreBucket().templatesByPersonId.values) {
      if (bucket.templates.isEmpty) continue;
      if (excluded.contains(bucket.person.id)) continue;
      final centroidVector = bucket.centroid;
      if (centroidVector == null || centroidVector.isEmpty) continue;
      scored.add((bucket.person.id, _debiasedCosine(vector, centroidVector)));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).map((e) => e.$1).toSet();
  }

  void _startCameraCalibrationWindow(String cameraId) {
    if (_cameraThresholdProfiles.containsKey(cameraId) ||
        _calibrationWindows.containsKey(cameraId)) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final window = _CalibrationWindow(
      cameraId: cameraId,
      startedAtMs: now,
      endsAtMs: now + _cameraCalibrationDuration.inMilliseconds,
    );
    window.timer = Timer(_cameraCalibrationDuration, () {
      _finalizeCameraCalibration(cameraId);
    });
    _calibrationWindows[cameraId] = window;
    _log.info(
      'Calibration started camera=$cameraId duration=${_cameraCalibrationDuration.inSeconds}s (top-2 logs enabled)',
    );
  }

  void _recordCalibrationSample({
    required String? cameraId,
    required String? faceLogKey,
    required _CandidateScore top1,
    required _CandidateScore? top2,
    required double margin,
    required double frameQuality,
    required bool accepted,
  }) {
    if (cameraId == null) return;
    final window = _calibrationWindows[cameraId];
    if (window == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > window.endsAtMs) {
      _finalizeCameraCalibration(cameraId);
      return;
    }

    window.samples.add(
      _CalibrationSample(
        top1Raw: top1.blendedScore,
        top1Cal: top1.calibratedScore,
        top1Quality: top1.template.quality,
        top2Raw: top2?.blendedScore ?? -1.0,
        top2Cal: top2?.calibratedScore ?? -1.0,
        top2Quality: top2?.template.quality ?? 0.0,
        margin: margin,
        frameQuality: frameQuality,
        accepted: accepted,
      ),
    );

    final key = faceLogKey ?? 'face';
    final lastLogAt = window.lastLogAtByFaceKey[key] ?? 0;
    if (now - lastLogAt < _calibrationLogThrottleMs) {
      return;
    }
    window.lastLogAtByFaceKey[key] = now;

    final top2Name = top2?.bucket.person.name ?? '-';
    final top2Raw = top2?.blendedScore ?? -1.0;
    final top2Cal = top2?.calibratedScore ?? -1.0;
    if (_traceLogsEnabled) {
      _log.debug(
        'CalibTop2 camera=$cameraId face=$key q=${frameQuality.toStringAsFixed(3)} '
        'top1=${top1.bucket.person.name}:${top1.blendedScore.toStringAsFixed(3)}/${top1.calibratedScore.toStringAsFixed(3)}/qt${top1.template.quality.toStringAsFixed(3)} '
        'top2=$top2Name:${top2Raw.toStringAsFixed(3)}/${top2Cal.toStringAsFixed(3)}/qt${(top2?.template.quality ?? 0.0).toStringAsFixed(3)} '
        'margin=${margin.toStringAsFixed(3)} accepted=$accepted',
      );
    }
  }

  void _finalizeCameraCalibration(String cameraId) {
    final window = _calibrationWindows.remove(cameraId);
    if (window == null) return;
    window.timer?.cancel();

    final samples = window.samples;
    if (samples.length < 12) {
      _log.info(
        'Calibration skipped camera=$cameraId samples=${samples.length} (need >=12)',
      );
      return;
    }

    final impostorRaw = samples
        .where((s) => s.top2Raw > 0)
        .map((s) => s.top2Raw)
        .toList();
    final impostorCal = samples
        .where((s) => s.top2Cal > -0.5)
        .map((s) => s.top2Cal)
        .toList();
    final acceptedRaw = samples
        .where((s) => s.accepted)
        .map((s) => s.top1Raw)
        .toList();
    final acceptedCal = samples
        .where((s) => s.accepted)
        .map((s) => s.top1Cal)
        .toList();
    final allMargins = samples
        .where((s) => s.margin >= 0)
        .map((s) => s.margin)
        .toList();

    var lockedMatch = _knownMatchThreshold;
    var lockedCalibrated = _knownCalibratedThreshold;
    var lockedMargin = _knownMatchMargin;

    if (impostorRaw.isNotEmpty) {
      lockedMatch = math.max(
        lockedMatch,
        _percentile(impostorRaw, 0.98) + 0.012,
      );
    }
    if (acceptedRaw.isNotEmpty) {
      lockedMatch = math.min(
        lockedMatch,
        _percentile(acceptedRaw, 0.12) - 0.008,
      );
    }
    lockedMatch = lockedMatch.clamp(0.86, 0.94);

    if (impostorCal.isNotEmpty) {
      lockedCalibrated = math.max(
        lockedCalibrated,
        _percentile(impostorCal, 0.985) + 0.06,
      );
    }
    if (acceptedCal.isNotEmpty) {
      lockedCalibrated = math.min(
        lockedCalibrated,
        _percentile(acceptedCal, 0.12) - 0.05,
      );
    }
    lockedCalibrated = lockedCalibrated.clamp(0.55, 1.35);

    if (allMargins.isNotEmpty) {
      lockedMargin = math.max(lockedMargin, _percentile(allMargins, 0.28));
    }
    lockedMargin = lockedMargin.clamp(0.05, 0.14);

    final lockedStrong = (lockedMatch + 0.05).clamp(0.93, 0.97);

    final profile = _CameraThresholdProfile(
      matchThreshold: lockedMatch,
      calibratedThreshold: lockedCalibrated,
      strongThreshold: lockedStrong,
      marginThreshold: lockedMargin,
      lockedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _cameraThresholdProfiles[cameraId] = profile;

    _log.info(
      'Calibration locked camera=$cameraId samples=${samples.length} '
      'match=${profile.matchThreshold.toStringAsFixed(3)} '
      'cal=${profile.calibratedThreshold.toStringAsFixed(3)} '
      'strong=${profile.strongThreshold.toStringAsFixed(3)} '
      'margin=${profile.marginThreshold.toStringAsFixed(3)}',
    );
  }

  double _percentile(List<double> input, double p) {
    if (input.isEmpty) return 0.0;
    if (input.length == 1) return input.first;
    final values = [...input]..sort();
    final clampedP = p.clamp(0.0, 1.0);
    final rank = (values.length - 1) * clampedP;
    final low = rank.floor();
    final high = rank.ceil();
    if (low == high) return values[low];
    final ratio = rank - low;
    return values[low] * (1 - ratio) + values[high] * ratio;
  }

  double? _toFiniteDouble(dynamic value) {
    if (value is num) {
      final v = value.toDouble();
      return v.isFinite ? v : null;
    }
    if (value is String) {
      final v = double.tryParse(value);
      if (v == null || !v.isFinite) return null;
      return v;
    }
    return null;
  }

  Rect? _extractFallbackFaceRect(
    dynamic face,
    int imageWidth,
    int imageHeight,
  ) {
    final bbox = _readDynamicMember(face, 'boundingBox');
    if (bbox == null) return null;

    final left = _firstFiniteDouble(<dynamic>[
      _readDynamicMember(bbox, 'left'),
      _readDynamicMember(bbox, 'x'),
      _readMapValue(bbox, 'left'),
      _readMapValue(bbox, 'x'),
      _readMapValue(bbox, 'xmin'),
      _readNestedPointValue(bbox, 'topLeft', 'x'),
      _readNestedPointValue(bbox, 'topLeft', 'dx'),
      _readNestedPointValue(bbox, 'leftTop', 'x'),
      _readNestedPointValue(bbox, 'leftTop', 'dx'),
      _readListValue(bbox, 0),
    ]);

    final top = _firstFiniteDouble(<dynamic>[
      _readDynamicMember(bbox, 'top'),
      _readDynamicMember(bbox, 'y'),
      _readMapValue(bbox, 'top'),
      _readMapValue(bbox, 'y'),
      _readMapValue(bbox, 'ymin'),
      _readNestedPointValue(bbox, 'topLeft', 'y'),
      _readNestedPointValue(bbox, 'topLeft', 'dy'),
      _readNestedPointValue(bbox, 'leftTop', 'y'),
      _readNestedPointValue(bbox, 'leftTop', 'dy'),
      _readListValue(bbox, 1),
    ]);

    final width = _firstFiniteDouble(<dynamic>[
      _readDynamicMember(bbox, 'width'),
      _readMapValue(bbox, 'width'),
      _readListValue(bbox, 2),
      _deriveSizeFromBounds(
        _firstFiniteDouble(<dynamic>[
          _readDynamicMember(bbox, 'right'),
          _readMapValue(bbox, 'right'),
          _readMapValue(bbox, 'xmax'),
          _readNestedPointValue(bbox, 'bottomRight', 'x'),
          _readNestedPointValue(bbox, 'bottomRight', 'dx'),
        ]),
        left,
      ),
    ]);

    final height = _firstFiniteDouble(<dynamic>[
      _readDynamicMember(bbox, 'height'),
      _readMapValue(bbox, 'height'),
      _readListValue(bbox, 3),
      _deriveSizeFromBounds(
        _firstFiniteDouble(<dynamic>[
          _readDynamicMember(bbox, 'bottom'),
          _readMapValue(bbox, 'bottom'),
          _readMapValue(bbox, 'ymax'),
          _readNestedPointValue(bbox, 'bottomRight', 'y'),
          _readNestedPointValue(bbox, 'bottomRight', 'dy'),
        ]),
        top,
      ),
    ]);

    if (left == null || top == null || width == null || height == null) {
      return null;
    }

    final clampedLeft = left.clamp(0.0, imageWidth.toDouble() - 1);
    final clampedTop = top.clamp(0.0, imageHeight.toDouble() - 1);
    final maxWidth = imageWidth.toDouble() - clampedLeft;
    final maxHeight = imageHeight.toDouble() - clampedTop;
    final clampedWidth = width.clamp(0.0, maxWidth);
    final clampedHeight = height.clamp(0.0, maxHeight);
    if (clampedWidth <= 0 || clampedHeight <= 0) return null;

    return Rect.fromLTWH(clampedLeft, clampedTop, clampedWidth, clampedHeight);
  }

  double? _firstFiniteDouble(List<dynamic> values) {
    for (final value in values) {
      final parsed = _toFiniteDouble(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  double? _deriveSizeFromBounds(double? maxValue, double? minValue) {
    if (maxValue == null || minValue == null) return null;
    return maxValue - minValue;
  }

  dynamic _readDynamicMember(dynamic source, String member) {
    if (source == null) return null;
    try {
      switch (member) {
        case 'boundingBox':
          return source.boundingBox;
        case 'left':
          return source.left;
        case 'top':
          return source.top;
        case 'right':
          return source.right;
        case 'bottom':
          return source.bottom;
        case 'x':
          return source.x;
        case 'y':
          return source.y;
        case 'width':
          return source.width;
        case 'height':
          return source.height;
        case 'topLeft':
          return source.topLeft;
        case 'leftTop':
          return source.leftTop;
        case 'bottomRight':
          return source.bottomRight;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  dynamic _readMapValue(dynamic source, String key) {
    if (source is Map) {
      return source[key];
    }
    return null;
  }

  dynamic _readListValue(dynamic source, int index) {
    if (source is List && index >= 0 && index < source.length) {
      return source[index];
    }
    return null;
  }

  dynamic _readNestedPointValue(
    dynamic source,
    String pointMember,
    String axis,
  ) {
    final point =
        _readDynamicMember(source, pointMember) ??
        _readMapValue(source, pointMember);
    if (point == null) return null;

    if (axis == 'x') {
      return _readDynamicMember(point, 'x') ?? _readMapValue(point, 'x');
    }
    if (axis == 'dx') {
      return _readDynamicMember(point, 'dx') ?? _readMapValue(point, 'dx');
    }
    if (axis == 'y') {
      return _readDynamicMember(point, 'y') ?? _readMapValue(point, 'y');
    }
    if (axis == 'dy') {
      return _readDynamicMember(point, 'dy') ?? _readMapValue(point, 'dy');
    }
    return null;
  }

  bool _isInsideZone(Rect rectRatio, RecognitionZone zone) {
    final cx = rectRatio.center.dx;
    final cy = rectRatio.center.dy;
    final centerX = zone.leftRatio + zone.widthRatio / 2;
    final centerY = zone.topRatio + zone.heightRatio / 2;
    final angle = -zone.rotationDegrees * math.pi / 180;

    final dx = cx - centerX;
    final dy = cy - centerY;
    final localX = centerX + dx * math.cos(angle) - dy * math.sin(angle);
    final localY = centerY + dx * math.sin(angle) + dy * math.cos(angle);

    return localX >= zone.leftRatio &&
        localX <= zone.leftRatio + zone.widthRatio &&
        localY >= zone.topRatio &&
        localY <= zone.topRatio + zone.heightRatio;
  }

  img.Image _centerCropSquare(img.Image input) {
    final side = math.min(input.width, input.height);
    final x = ((input.width - side) / 2).round();
    final y = ((input.height - side) / 2).round();
    return img.copyCrop(input, x: x, y: y, width: side, height: side);
  }

  Rect _expandRect(
    Rect rect, {
    required int imageWidth,
    required int imageHeight,
    required double paddingRatio,
  }) {
    final padX = rect.width * paddingRatio;
    final padY = rect.height * paddingRatio;
    final left = (rect.left - padX).clamp(0.0, imageWidth.toDouble() - 1);
    final top = (rect.top - padY).clamp(0.0, imageHeight.toDouble() - 1);
    final right = (rect.right + padX).clamp(0.0, imageWidth.toDouble());
    final bottom = (rect.bottom + padY).clamp(0.0, imageHeight.toDouble());
    return Rect.fromLTRB(left, top, right, bottom);
  }

  img.Image? _cropFace(img.Image source, Rect rect) {
    final x = rect.left.floor().clamp(0, source.width - 1);
    final y = rect.top.floor().clamp(0, source.height - 1);
    final w = rect.width.ceil().clamp(8, source.width - x);
    final h = rect.height.ceil().clamp(8, source.height - y);
    if (w <= 0 || h <= 0) return null;
    return img.copyCrop(source, x: x, y: y, width: w, height: h);
  }

  img.Image? _cropFaceTight(
    img.Image source,
    Rect rect, {
    double paddingRatio = -0.06,
  }) {
    final shortestSide = math.min(rect.width, rect.height);
    final adaptivePadding = shortestSide < 64
        ? 0.14
        : shortestSide < 96
        ? 0.06
        : shortestSide < 160
        ? 0.0
        : shortestSide < 256
        ? 0.03
        : 0.05;
    final tightRect = _expandRect(
      rect,
      imageWidth: source.width,
      imageHeight: source.height,
      paddingRatio: adaptivePadding,
    );
    final x = tightRect.left.floor().clamp(0, source.width - 1);
    final y = tightRect.top.floor().clamp(0, source.height - 1);
    final w = tightRect.width.ceil().clamp(8, source.width - x);
    final h = tightRect.height.ceil().clamp(8, source.height - y);
    if (w <= 0 || h <= 0) return null;
    return img.copyCrop(source, x: x, y: y, width: w, height: h);
  }

  img.Image? _selectRecognitionCrop({
    required img.Image source,
    required Rect rect,
    _DetectedFace? detectedFace,
    FaceMeshResult? mesh,
  }) {
    final alignedFromDetection = detectedFace?.alignedCrop;
    if (alignedFromDetection != null) {
      return alignedFromDetection;
    }

    if (mesh != null) {
      final alignedFromMesh = _alignedCropFromMesh(source, mesh);
      if (alignedFromMesh != null) {
        return alignedFromMesh;
      }
    }

    return _cropFaceTight(source, rect);
  }

  img.Image? _alignedCropFromMesh(img.Image source, FaceMeshResult mesh) {
    if (mesh.landmarks.length < 363) {
      return null;
    }

    final left = _landmarkPixel(mesh, 33);
    final leftOuter = _landmarkPixel(mesh, 133);
    final right = _landmarkPixel(mesh, 263);
    final rightOuter = _landmarkPixel(mesh, 362);
    if (left == null ||
        leftOuter == null ||
        right == null ||
        rightOuter == null) {
      return null;
    }

    final leftEye = Offset(
      (left.dx + leftOuter.dx) / 2,
      (left.dy + leftOuter.dy) / 2,
    );
    final rightEye = Offset(
      (right.dx + rightOuter.dx) / 2,
      (right.dy + rightOuter.dy) / 2,
    );
    final eyeDx = rightEye.dx - leftEye.dx;
    final eyeDy = rightEye.dy - leftEye.dy;
    final eyeDistance = math.sqrt(eyeDx * eyeDx + eyeDy * eyeDy);
    final minEyeDistanceForAlign = math.min(
      _minRealtimeFacePixels.toDouble(),
      34.0,
    );
    if (eyeDistance < minEyeDistanceForAlign) {
      return null;
    }

    final angleDeg = math.atan2(eyeDy, eyeDx) * 180.0 / math.pi;
    final rotated = img.copyRotate(
      source,
      angle: -angleDeg,
      interpolation: img.Interpolation.linear,
    );

    final srcCenter = Offset(source.width / 2, source.height / 2);
    final dstCenter = Offset(rotated.width / 2, rotated.height / 2);
    final leftEyeRotated = _rotatePoint(
      leftEye,
      srcCenter,
      -angleDeg,
      dstCenter,
    );
    final rightEyeRotated = _rotatePoint(
      rightEye,
      srcCenter,
      -angleDeg,
      dstCenter,
    );

    final cx = (leftEyeRotated.dx + rightEyeRotated.dx) / 2;
    final cy =
        (leftEyeRotated.dy + rightEyeRotated.dy) / 2 + eyeDistance * 0.35;
    final side = (eyeDistance * 2.2).clamp(
      72.0,
      math.min(rotated.width, rotated.height).toDouble(),
    );

    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: side,
      height: side,
    );
    return _cropFaceTight(rotated, rect, paddingRatio: -0.08);
  }

  Offset? _landmarkPixel(FaceMeshResult mesh, int index) {
    if (index < 0 || index >= mesh.landmarks.length) {
      return null;
    }
    final lm = mesh.landmarks[index];
    return Offset(lm.x * mesh.imageWidth, lm.y * mesh.imageHeight);
  }

  Offset _rotatePoint(
    Offset point,
    Offset sourceCenter,
    double angleDeg,
    Offset targetCenter,
  ) {
    final angle = angleDeg * math.pi / 180.0;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final dx = point.dx - sourceCenter.dx;
    final dy = point.dy - sourceCenter.dy;
    final x = dx * cosA - dy * sinA;
    final y = dx * sinA + dy * cosA;
    return Offset(targetCenter.dx + x, targetCenter.dy + y);
  }

  Future<_PartialEmbeddingBundle> _buildPartialEmbeddingsFromFace(
    img.Image face, {
    required int targetDimension,
    double frameQuality = 1.0,
    bool forRealtime = false,
    bool faceAlreadyPrepared = false,
  }) async {
    if (targetDimension <= 0) {
      return const _PartialEmbeddingBundle();
    }

    final square = faceAlreadyPrepared ? face : _prepareFaceForEmbedding(face);
    if (square.width < 32 || square.height < 32) {
      return const _PartialEmbeddingBundle();
    }

    final foreheadCrop = _cropNormalized(square, 0.18, 0.02, 0.64, 0.18);
    final leftEyeCrop = _cropNormalized(square, 0.06, 0.10, 0.32, 0.22);
    final rightEyeCrop = _cropNormalized(square, 0.62, 0.10, 0.32, 0.22);
    final noseCrop = _cropNormalized(square, 0.30, 0.28, 0.40, 0.30);
    final leftCheekCrop = _cropNormalized(square, 0.04, 0.28, 0.28, 0.30);
    final rightCheekCrop = _cropNormalized(square, 0.68, 0.28, 0.28, 0.30);
    final mouthCrop = _cropNormalized(square, 0.22, 0.56, 0.56, 0.22);
    final chinCrop = _cropNormalized(square, 0.28, 0.74, 0.44, 0.18);

    Future<(List<double>?, double)> buildRegion(
      img.Image? region,
      double baseWeight,
      double minQuality,
    ) async {
      if (region == null) return (null, 0.0);
      final prepared = _prepareFaceForEmbedding(region);
      final quality = _regionQuality(
        prepared,
        minSharpness: _minTemplateSharpness * 0.40,
      );
      final gate = forRealtime
          ? minQuality
          : (minQuality * 0.72).clamp(0.12, 0.36);
      if (quality < gate) {
        return (null, 0.0);
      }
      final robustRegionEmbedding =
          forRealtime && frameQuality >= 0.74 && quality >= 0.64;
      var vector = await _embeddingFromImage(
        prepared,
        alreadyPrepared: true,
        robust: robustRegionEmbedding,
      );
      vector = _alignVectorDimension(vector, targetDimension);
      if (vector.isEmpty) return (null, 0.0);

      var weight = (baseWeight * quality).clamp(0.0, 1.0).toDouble();
      if (forRealtime) {
        weight *= frameQuality.clamp(0.0, 1.0);
      }
      return (vector, weight);
    }

    final forehead = await buildRegion(foreheadCrop, 0.10, 0.18);
    final leftEye = await buildRegion(leftEyeCrop, 0.12, _eyeRegionMinQuality);
    final rightEye = await buildRegion(
      rightEyeCrop,
      0.12,
      _eyeRegionMinQuality,
    );
    final nose = await buildRegion(noseCrop, 0.16, _noseRegionMinQuality);
    final leftCheek = await buildRegion(leftCheekCrop, 0.11, 0.20);
    final rightCheek = await buildRegion(rightCheekCrop, 0.11, 0.20);
    final mouth = await buildRegion(mouthCrop, 0.15, _mouthRegionMinQuality);
    final chin = await buildRegion(chinCrop, 0.13, 0.20);

    final eyeVector = _averageVectors(<List<double>?>[leftEye.$1, rightEye.$1]);
    final eyeWeightRaw = (leftEye.$2 + rightEye.$2).clamp(0.0, 1.0).toDouble();

    if (forRealtime) {
      final enabledRegions = _realtimePartialEnabledRegions;
      final candidates =
          <({String key, List<double>? vector, double weight})>[
                (key: 'forehead', vector: forehead.$1, weight: forehead.$2),
                (key: 'leftEye', vector: leftEye.$1, weight: leftEye.$2),
                (key: 'rightEye', vector: rightEye.$1, weight: rightEye.$2),
                (key: 'nose', vector: nose.$1, weight: nose.$2),
                (key: 'mouth', vector: mouth.$1, weight: mouth.$2),
                (key: 'leftCheek', vector: leftCheek.$1, weight: leftCheek.$2),
                (
                  key: 'rightCheek',
                  vector: rightCheek.$1,
                  weight: rightCheek.$2,
                ),
                (key: 'chin', vector: chin.$1, weight: chin.$2),
              ]
              .where(
                (entry) =>
                    enabledRegions.contains(entry.key) &&
                    entry.vector != null &&
                    entry.weight > 0,
              )
              .toList();

      if (candidates.isEmpty) {
        return const _PartialEmbeddingBundle();
      }

      candidates.sort((a, b) => b.weight.compareTo(a.weight));

      final total = candidates.fold<double>(
        0.0,
        (sum, entry) => sum + entry.weight,
      );
      if (total <= 0) {
        return const _PartialEmbeddingBundle();
      }

      List<double>? vectorOf(String key) {
        for (final entry in candidates) {
          if (entry.key == key) {
            return entry.vector;
          }
        }
        return null;
      }

      double weightOf(String key) {
        for (final entry in candidates) {
          if (entry.key == key) {
            return (entry.weight / total).clamp(0.0, 1.0).toDouble();
          }
        }
        return 0.0;
      }

      return _PartialEmbeddingBundle(
        eyeVector: null,
        leftEyeVector: vectorOf('leftEye'),
        rightEyeVector: vectorOf('rightEye'),
        noseVector: vectorOf('nose'),
        mouthVector: vectorOf('mouth'),
        foreheadVector: vectorOf('forehead'),
        leftCheekVector: vectorOf('leftCheek'),
        rightCheekVector: vectorOf('rightCheek'),
        chinVector: vectorOf('chin'),
        eyeWeight: 0.0,
        leftEyeWeight: weightOf('leftEye'),
        rightEyeWeight: weightOf('rightEye'),
        noseWeight: weightOf('nose'),
        mouthWeight: weightOf('mouth'),
        foreheadWeight: weightOf('forehead'),
        leftCheekWeight: weightOf('leftCheek'),
        rightCheekWeight: weightOf('rightCheek'),
        chinWeight: weightOf('chin'),
      );
    }

    final total =
        (forehead.$2 +
                leftEye.$2 +
                rightEye.$2 +
                nose.$2 +
                leftCheek.$2 +
                rightCheek.$2 +
                mouth.$2 +
                chin.$2)
            .clamp(0.0, 8.0);
    if (total <= 0) {
      return const _PartialEmbeddingBundle();
    }

    return _PartialEmbeddingBundle(
      eyeVector: eyeVector,
      leftEyeVector: leftEye.$1,
      rightEyeVector: rightEye.$1,
      noseVector: nose.$1,
      mouthVector: mouth.$1,
      foreheadVector: forehead.$1,
      leftCheekVector: leftCheek.$1,
      rightCheekVector: rightCheek.$1,
      chinVector: chin.$1,
      eyeWeight: eyeWeightRaw / total,
      leftEyeWeight: leftEye.$2 / total,
      rightEyeWeight: rightEye.$2 / total,
      noseWeight: nose.$2 / total,
      mouthWeight: mouth.$2 / total,
      foreheadWeight: forehead.$2 / total,
      leftCheekWeight: leftCheek.$2 / total,
      rightCheekWeight: rightCheek.$2 / total,
      chinWeight: chin.$2 / total,
    );
  }

  List<double>? _averageVectors(List<List<double>?> vectors) {
    final present = vectors.whereType<List<double>>().toList(growable: false);
    if (present.isEmpty) return null;
    final length = present.first.length;
    if (length <= 0) return null;
    final sum = List<double>.filled(length, 0.0);
    var count = 0;
    for (final vector in present) {
      final limit = math.min(length, vector.length);
      for (var i = 0; i < limit; i++) {
        sum[i] += vector[i];
      }
      count++;
    }
    if (count <= 0) return null;
    for (var i = 0; i < sum.length; i++) {
      sum[i] /= count;
    }
    return _normalizeVector(sum);
  }

  img.Image? _cropNormalized(
    img.Image source,
    double x,
    double y,
    double w,
    double h,
  ) {
    final left = (source.width * x).floor().clamp(0, source.width - 1);
    final top = (source.height * y).floor().clamp(0, source.height - 1);
    final width = (source.width * w).ceil().clamp(8, source.width - left);
    final height = (source.height * h).ceil().clamp(8, source.height - top);
    if (width <= 0 || height <= 0) return null;
    return img.copyCrop(source, x: left, y: top, width: width, height: height);
  }

  double _regionQuality(img.Image image, {required double minSharpness}) {
    final sharpnessScore = (_imageSharpness(image) / minSharpness).clamp(
      0.0,
      1.0,
    );
    final luminance = _robustFaceLuminance(image);
    final lightBalance = (1.0 - ((luminance - 0.5).abs() * 2.0)).clamp(
      0.0,
      1.0,
    );
    return (sharpnessScore * 0.78 + lightBalance * 0.22)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _robustFaceLuminance(img.Image image) {
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0) return 0.0;

    // Focus on the central face area and trim out bright/dark outliers.
    final left = (width * 0.15).floor().clamp(0, width - 1);
    final top = (height * 0.15).floor().clamp(0, height - 1);
    final right = (width * 0.85).ceil().clamp(left + 1, width);
    final bottom = (height * 0.85).ceil().clamp(top + 1, height);

    final histogram = List<int>.filled(256, 0);
    var count = 0;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final p = image.getPixel(x, y);
        final luma = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(
          0,
          255,
        );
        histogram[luma] += 1;
        count++;
      }
    }
    if (count <= 0) return _averageLuma(image);

    final lowTrim = (count * 0.08).round();
    final highTrim = (count * 0.92).round();
    var cumulative = 0;
    var weighted = 0.0;
    var kept = 0;
    for (var i = 0; i < histogram.length; i++) {
      final binCount = histogram[i];
      if (binCount == 0) continue;
      final start = cumulative;
      final end = cumulative + binCount;
      cumulative = end;

      final keepStart = math.max(start, lowTrim);
      final keepEnd = math.min(end, highTrim);
      final keep = keepEnd - keepStart;
      if (keep <= 0) continue;

      weighted += i * keep;
      kept += keep;
    }

    if (kept <= 0) return _averageLuma(image);
    return (weighted / kept / 255.0).clamp(0.0, 1.0).toDouble();
  }

  double _averageLuma(img.Image image) {
    final rgb = image.getBytes(order: img.ChannelOrder.rgb);
    if (rgb.isEmpty) return 0.0;
    var sum = 0.0;
    for (var i = 0; i < rgb.length; i += 3) {
      sum += (0.299 * rgb[i] + 0.587 * rgb[i + 1] + 0.114 * rgb[i + 2]) / 255.0;
    }
    return (sum / (rgb.length / 3)).clamp(0.0, 1.0).toDouble();
  }

  List<double> _alignVectorDimension(List<double> vector, int targetDimension) {
    if (vector.isEmpty) return const <double>[];
    if (targetDimension <= 0 || vector.length == targetDimension) {
      return vector;
    }

    List<double> aligned;
    if (vector.length > targetDimension) {
      aligned = vector.sublist(0, targetDimension);
    } else {
      aligned = List<double>.filled(targetDimension, 0.0);
      for (var i = 0; i < vector.length; i++) {
        aligned[i] = vector[i];
      }
    }

    var norm = 0.0;
    for (final value in aligned) {
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < aligned.length; i++) {
        aligned[i] = aligned[i] / norm;
      }
    }
    return aligned;
  }

  Future<List<double>> _vectorFromImage(img.Image source) async {
    final square = _centerCropSquare(source);
    final resized = await _resizeWithOpenCvDart(square, 24, 24);
    final rgb = resized!.getBytes(order: img.ChannelOrder.rgb);
    final vector = List<double>.filled(24 * 24, 0);

    var sumSq = 0.0;
    var j = 0;
    for (var i = 0; i < rgb.length; i += 3) {
      final gray =
          (0.299 * rgb[i] + 0.587 * rgb[i + 1] + 0.114 * rgb[i + 2]) / 255.0;
      vector[j] = gray;
      sumSq += gray * gray;
      j++;
    }

    final norm = math.sqrt(sumSq);
    if (norm > 0) {
      for (var i = 0; i < vector.length; i++) {
        vector[i] = vector[i] / norm;
      }
    }
    return vector;
  }

  img.Image? _cameraImageToRgb(CameraImage image) {
    if (image.format.group == ImageFormatGroup.bgra8888 &&
        image.planes.isNotEmpty) {
      final plane = image.planes.first;
      final bytes = plane.bytes;
      final rowStride = plane.bytesPerRow;
      final pixelStride = plane.bytesPerPixel ?? 4;
      final output = img.Image(width: image.width, height: image.height);
      for (var y = 0; y < image.height; y++) {
        final rowStart = y * rowStride;
        for (var x = 0; x < image.width; x++) {
          final index = rowStart + x * pixelStride;
          if (index + 3 >= bytes.length) {
            continue;
          }
          final b = bytes[index];
          final g = bytes[index + 1];
          final r = bytes[index + 2];
          final a = bytes[index + 3];
          output.setPixelRgba(x, y, r, g, b, a);
        }
      }
      return output;
    }

    if (image.format.group != ImageFormatGroup.yuv420 ||
        image.planes.length < 3) {
      return null;
    }

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final output = img.Image(width: image.width, height: image.height);
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < image.height; y++) {
      final yRow = y * yPlane.bytesPerRow;
      final uvRow = (y >> 1) * uPlane.bytesPerRow;
      for (var x = 0; x < image.width; x++) {
        final yp = yPlane.bytes[yRow + x];
        final uvOffset = uvRow + (x >> 1) * uvPixelStride;
        final up = uPlane.bytes[uvOffset];
        final vp = vPlane.bytes[uvOffset];

        final r = (yp + 1.402 * (vp - 128)).round().clamp(0, 255);
        final g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128))
            .round()
            .clamp(0, 255);
        final b = (yp + 1.772 * (up - 128)).round().clamp(0, 255);
        output.setPixelRgb(x, y, r, g, b);
      }
    }
    return output;
  }

  img.Image? _cameraImageFaceToRgb(CameraImage image, Rect rect) {
    final shortestSide = math.min(rect.width, rect.height);
    final adaptivePadding = shortestSide < 64
        ? 0.14
        : shortestSide < 96
        ? 0.06
        : shortestSide < 160
        ? 0.0
        : shortestSide < 256
        ? 0.03
        : 0.05;
    final paddedRect = _expandRect(
      rect,
      imageWidth: image.width,
      imageHeight: image.height,
      paddingRatio: adaptivePadding,
    );
    final left = paddedRect.left.floor().clamp(0, image.width - 1);
    final top = paddedRect.top.floor().clamp(0, image.height - 1);
    final width = paddedRect.width.ceil().clamp(8, image.width - left);
    final height = paddedRect.height.ceil().clamp(8, image.height - top);
    if (width <= 0 || height <= 0) {
      return null;
    }

    if (image.format.group == ImageFormatGroup.bgra8888 &&
        image.planes.isNotEmpty) {
      final plane = image.planes.first;
      final bytes = plane.bytes;
      final rowStride = plane.bytesPerRow;
      final pixelStride = plane.bytesPerPixel ?? 4;
      final output = img.Image(width: width, height: height);
      for (var y = 0; y < height; y++) {
        final sourceY = top + y;
        final rowStart = sourceY * rowStride;
        for (var x = 0; x < width; x++) {
          final sourceX = left + x;
          final index = rowStart + sourceX * pixelStride;
          if (index + 3 >= bytes.length) {
            continue;
          }
          final b = bytes[index];
          final g = bytes[index + 1];
          final r = bytes[index + 2];
          final a = bytes[index + 3];
          output.setPixelRgba(x, y, r, g, b, a);
        }
      }
      return output;
    }

    if (image.format.group != ImageFormatGroup.yuv420 ||
        image.planes.length < 3) {
      return null;
    }

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    final output = img.Image(width: width, height: height);

    for (var y = 0; y < height; y++) {
      final sourceY = top + y;
      final yRow = sourceY * yPlane.bytesPerRow;
      final uvRow = (sourceY >> 1) * uPlane.bytesPerRow;
      for (var x = 0; x < width; x++) {
        final sourceX = left + x;
        final yp = yPlane.bytes[yRow + sourceX];
        final uvOffset = uvRow + (sourceX >> 1) * uvPixelStride;
        final up = uPlane.bytes[uvOffset];
        final vp = vPlane.bytes[uvOffset];

        final r = (yp + 1.402 * (vp - 128)).round().clamp(0, 255);
        final g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128))
            .round()
            .clamp(0, 255);
        final b = (yp + 1.772 * (up - 128)).round().clamp(0, 255);
        output.setPixelRgb(x, y, r, g, b);
      }
    }

    return output;
  }

  Future<void> dispose() async {
    await _runtimeConfigSub?.cancel();
    _runtimeConfigSub = null;
    _templateMonitorTimer?.cancel();
    _templateMonitorTimer = null;
    _dbFlushTimer?.cancel();
    _dbFlushTimer = null;
    await _flushPendingEventsToDb();

    for (final socket in _realtimeWsClients.toList(growable: false)) {
      await socket.close();
    }
    _realtimeWsClients.clear();
    await _realtimeWsServer?.close(force: true);
    _realtimeWsServer = null;
    for (final p in _processorsByCameraId.values) {
      p.stillCaptureTimer?.cancel();
      p.stillCaptureTimer = null;
      if (p.controller.value.isStreamingImages) {
        await p.controller.stopImageStream();
      }
      await p.controller.dispose();
    }
    _processorsByCameraId.clear();
    _overlaysByCameraId.clear();
    _overlayTracksByCameraId.clear();
    _realtimeEventCache.clear();
    _pendingDbEvents.clear();
    _arcFaceSession?.close();
    _scrfdSession?.close();
    _faceDetectorProcessor?.close();
    _faceMeshProcessor?.close();
    await _frameQueue.close();
    await _notiQueue.close();
  }
}
