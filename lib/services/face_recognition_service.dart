import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart' as tfl;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:uuid/uuid.dart';

import '../database/face_attendance_repository.dart';
import '../log/log_service.dart';

class FaceOverlayBox {
  FaceOverlayBox({
    this.trackKey = '',
    required this.rectRatio,
    required this.event,
    this.debugLabel,
  });

  final String trackKey;
  final Rect rectRatio;
  final RecognitionEvent event;
  final String? debugLabel;
}

class RecognitionFramePacket {
  RecognitionFramePacket({
    required this.cameraId,
    required this.overlays,
    required this.createdAt,
    this.annotatedFrameJpeg,
    this.annotatedOverlayPng,
  });

  final String cameraId;
  final List<FaceOverlayBox> overlays;
  final int createdAt;
  final Uint8List? annotatedFrameJpeg;
  final Uint8List? annotatedOverlayPng;
}

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

class _FaceTemplate {
  _FaceTemplate({required this.person, required this.vector, required this.quality});

  final FacePerson person;
  final List<double> vector;
  final double quality;
}

class _MatchResult {
  _MatchResult({required this.template, required this.score, required this.calibratedScore});

  final _FaceTemplate template;
  final double score;
  final double calibratedScore;
}

class _CandidateScore {
  _CandidateScore({
    required this.bucket,
    required this.template,
    required this.templateScore,
    required this.centroidScore,
    required this.blendedScore,
    required this.calibratedScore,
  });

  final _PersonScoreBucket bucket;
  final _FaceTemplate template;
  final double templateScore;
  final double centroidScore;
  final double blendedScore;
  final double calibratedScore;
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

double _dotProduct(List<double> a, List<double> b) {
  final len = math.min(a.length, b.length);
  var s = 0.0;
  for (var i = 0; i < len; i++) {
    s += a[i] * b[i];
  }
  return s;
}

class _PersonScoreBucket {
  _PersonScoreBucket({required this.person});

  final FacePerson person;
  final List<_FaceTemplate> templates = [];
  List<double>? centroid;
  double interClassMean = 0.78;
  double interClassStd = 0.10;

  void addTemplate(_FaceTemplate template) {
    templates.add(template);
  }

  void finalize() {
    if (templates.isEmpty) {
      centroid = null;
      return;
    }

    final length = templates.first.vector.length;
    final sum = List<double>.filled(length, 0);
    var totalWeight = 0.0;
    for (final template in templates) {
      final vector = template.vector;
      final weight = template.quality.clamp(0.2, 1.0);
      final limit = math.min(length, vector.length);
      for (var i = 0; i < limit; i++) {
        sum[i] += vector[i] * weight;
      }
      totalWeight += weight;
    }

    if (totalWeight > 0) {
      for (var i = 0; i < sum.length; i++) {
        sum[i] /= totalWeight;
      }
    }

    var norm = 0.0;
    for (final value in sum) {
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < sum.length; i++) {
        sum[i] /= norm;
      }
    }
    centroid = sum;
  }

  double bestTemplateScore(List<double> vector) {
    if (templates.isEmpty) return 0.0;

    var best = -1.0;
    for (final template in templates) {
      final score = _dotProduct(vector, template.vector) * (0.80 + template.quality * 0.20);
      if (score > best) {
        best = score;
      }
    }
    return best;
  }

  double centroidScore(List<double> vector) {
    final c = centroid;
    if (c == null || c.isEmpty) {
      return 0.0;
    }

    return _dotProduct(vector, c);
  }

  double scoreAgainst(List<double> vector) {
    final t = bestTemplateScore(vector);
    final c = centroidScore(vector);
    if (c == 0.0) return t;

    final blended = c * 0.65 + t * 0.35;
    return blended.clamp(-1.0, 1.0);
  }

  double calibrate(double rawScore) {
    final std = interClassStd < 0.015 ? 0.015 : interClassStd;
    return (rawScore - interClassMean) / std;
  }
}

class _Processor {
  _Processor({required this.controller});

  final CameraController controller;
  bool busy = false;
  int frameCount = 0;
  Timer? stillCaptureTimer;
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
  });

  final String key;
  Rect currentRect;
  Rect targetRect;
  RecognitionEvent event;
  int lastSeenAt;
}

class FaceRecognitionService {
  FaceRecognitionService._();

  static final FaceRecognitionService instance = FaceRecognitionService._();

  final OnnxRuntime _onnxRuntime = OnnxRuntime();
  final LogService _log = LogService();
  final Uuid _uuid = const Uuid();

  final Map<String, _Processor> _processorsByCameraId = {};
  final Map<String, List<FaceOverlayBox>> _overlaysByCameraId = {};
  final Map<String, int> _lastEventAt = {};
  final Map<String, Map<String, _CameraTrack>> _overlayTracksByCameraId = {};
  final Map<String, int> _fallbackFaceSkipCountByCameraId = {};
  final Map<String, int> _fallbackFaceSkipLogAtByCameraId = {};
  final List<_FaceTemplate> _templates = [];
  final Map<String, _PersonScoreBucket> _templatesByPersonId = {};
  final Map<String, _CameraThresholdProfile> _cameraThresholdProfiles = {};
  final Map<String, _CalibrationWindow> _calibrationWindows = {};

  final StreamController<RecognitionFramePacket> _frameQueue = StreamController<RecognitionFramePacket>.broadcast();
  final StreamController<FaceRecognitionNotification> _notiQueue = StreamController<FaceRecognitionNotification>.broadcast();

  List<CameraDescription> _availableCameras = [];
  bool _initialized = false;
  bool _arcFaceAttempted = false;
  OrtSession? _arcFaceSession;
  String _arcFaceInputName = 'data';
  String _arcFaceOutputName = 'fc1';
  FaceDetectorProcessor? _faceDetectorProcessor;
  FaceMeshProcessor? _faceMeshProcessor;
  FaceMeshInferencePipeline? _faceMeshPipeline;
  final tfl.FaceDetector _fallbackFaceDetector = tfl.FaceDetector();

  Timer? _templateMonitorTimer;
  bool _templateRefreshBusy = false;
  int _lastPeopleCacheVersion = -1;
  int _onnxFallbackCount = 0;

  static const double _knownMatchThreshold = 0.88;
  static const double _knownStrongThreshold = 0.94;
  static const double _knownCalibratedThreshold = 0.70;
  static const double _knownMatchMargin = 0.06;
  static const double _minTemplateSharpness = 18.0;
  static const Duration _cameraCalibrationDuration = Duration(seconds: 25);
  static const int _calibrationLogThrottleMs = 750;
  static const int _fallbackSkipLogIntervalMs = 3000;

  Stream<RecognitionFramePacket> get frameQueue => _frameQueue.stream;
  Stream<FaceRecognitionNotification> get notificationQueue => _notiQueue.stream;

  List<FaceOverlayBox> overlaysFor(String cameraId) => _overlaysByCameraId[cameraId] ?? const [];

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _availableCameras = await availableCameras();
      if (_supportsNativeFacePipeline) {
        await _ensureMediaPipeProcessors();
      } else {
        await _fallbackFaceDetector.initialize(model: tfl.FaceDetectionModel.backCamera);
      }
      await _ensureArcFaceSession();
      await _loadTemplates();
      _lastPeopleCacheVersion = await FaceAttendanceRepository.getFacePeopleCacheVersion();
      _startTemplateMonitor();
      _log.info('FaceRecognitionService initialized: mode=$runtimeModeLabel cameras=${_availableCameras.length} arcFace=${_arcFaceSession != null}');
    } catch (_) {
      // Keep app startup stable when detector initialization fails.
      _log.error('FaceRecognitionService initialization failed');
    }
  }

  bool get _supportsNativeFacePipeline {
    return !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  }

  String get runtimeModeLabel {
    if (_supportsNativeFacePipeline) {
      return 'MediaPipe Face Mesh + ArcFace ONNX';
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
    _lastPeopleCacheVersion = await FaceAttendanceRepository.getFacePeopleCacheVersion();
  }

  void invalidateZoneCache(String? cameraId) {
    // This baseline implementation fetches zones on demand and does not keep
    // a dedicated zone cache, so invalidation is a no-op for compatibility.
  }

  Future<void> rebuildVectorsForPerson(String personId) async {
    // Keep compatibility with newer UI actions that request per-person vector
    // rebuild. In this baseline service, templates are loaded from persisted
    // images, so refreshing templates is sufficient.
    await refreshTemplates();
  }

  Future<EnrollmentFaceCropResult> preprocessEnrollmentImage(
    Uint8List bytes, {
    String? poseLabel,
  }) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return EnrollmentFaceCropResult(
        ok: false,
        message: 'Anh khong hop le.',
      );
    }

    final cropped = _centerCropSquare(decoded);
    final sharpness = _imageSharpness(cropped);
    final encoded = Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
    final areaRatio = (cropped.width * cropped.height) /
        (decoded.width * decoded.height).clamp(1, 1 << 30);
    final aspectRatio = cropped.height == 0 ? 1.0 : cropped.width / cropped.height;

    return EnrollmentFaceCropResult(
      ok: true,
      message: 'OK',
      imageBytes: encoded,
      faceAreaRatio: areaRatio,
      faceAspectRatio: aspectRatio,
      sharpness: sharpness,
    );
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
      final version = await FaceAttendanceRepository.getFacePeopleCacheVersion();
      if (version == _lastPeopleCacheVersion) return;
      await _loadTemplates();
      _lastPeopleCacheVersion = version;
      _log.info('Face template cache refreshed version=$version templates=${_templates.length} persons=${_templatesByPersonId.length}');
    } catch (e) {
      _log.error('Face template cache sync failed error=$e');
    } finally {
      _templateRefreshBusy = false;
    }
  }

  Future<void> _ensureMediaPipeProcessors() async {
    if (_faceDetectorProcessor != null && _faceMeshProcessor != null && _faceMeshPipeline != null) {
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

    try {
      _arcFaceSession = await _onnxRuntime.createSessionFromAsset('assets/models/arcface.onnx');
      final session = _arcFaceSession;
      if (session != null) {
        if (session.inputNames.isNotEmpty) {
          _arcFaceInputName = session.inputNames.first;
        }
        if (session.outputNames.isNotEmpty) {
          _arcFaceOutputName = session.outputNames.first;
        }
      }
    } catch (_) {
      _arcFaceSession = null;
    }
  }

  CameraController? previewControllerFor(String cameraId) => _processorsByCameraId[cameraId]?.controller;

  bool isRunning(String cameraId) => _processorsByCameraId.containsKey(cameraId);

  Future<void> ensureProcessorForCamera(String cameraId, {int preferredDeviceIndex = 0}) async {
    if (_processorsByCameraId.containsKey(cameraId)) {
      return;
    }

    if (_availableCameras.isEmpty) {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        return;
      }
    }

    final safeIndex = preferredDeviceIndex.clamp(0, _availableCameras.length - 1).toInt();
    final desc = _availableCameras[safeIndex];
    _log.info('Starting recognition processor camera=$cameraId device=${desc.name} mode=$runtimeModeLabel');
    final controller = CameraController(
      desc,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: _preferredImageFormat(),
    );
    try {
      await controller.initialize();
    } catch (e) {
      _log.error('CameraController initialize failed camera=$cameraId error=$e');
      rethrow;
    }

    final processor = _Processor(controller: controller);
    _processorsByCameraId[cameraId] = processor;
    _startCameraCalibrationWindow(cameraId);

    try {
      if (!controller.supportsImageStreaming()) {
        _log.error('CameraController does not support image streaming camera=$cameraId');
        _startStillCaptureFallback(cameraId, processor);
        return;
      }

      await controller.startImageStream((image) {
        unawaited(_processFrame(cameraId, processor, image));
      });
    } catch (_) {
      // Keep preview available when streaming frames is not supported.
      _log.error('Failed to start image stream camera=$cameraId');
      _startStillCaptureFallback(cameraId, processor);
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
    await processor.controller.dispose();
    _overlaysByCameraId.remove(cameraId);
    _overlayTracksByCameraId.remove(cameraId);
    _fallbackFaceSkipCountByCameraId.remove(cameraId);
    _fallbackFaceSkipLogAtByCameraId.remove(cameraId);
    final window = _calibrationWindows.remove(cameraId);
    window?.timer?.cancel();
    _emitFrame(cameraId, const []);
  }

  void _startStillCaptureFallback(String cameraId, _Processor processor) {
    processor.stillCaptureTimer?.cancel();
    processor.stillCaptureTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      unawaited(_captureStillFrame(cameraId, processor));
    });
    _log.info('Still-image fallback started camera=$cameraId mode=$runtimeModeLabel');
  }

  Future<void> _captureStillFrame(String cameraId, _Processor processor) async {
    if (processor.busy || !processor.controller.value.isInitialized) return;
    if (processor.controller.value.isTakingPicture) return;

    processor.busy = true;
    try {
      final file = await processor.controller.takePicture();
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      RecognitionZone zone;
      try {
        zone = await FaceAttendanceRepository.getZoneByCameraId(cameraId);
      } catch (e) {
        _log.error('Fallback zone load failed camera=$cameraId error=$e');
        zone = RecognitionZone.defaults(cameraId: cameraId);
      }

      await _processFallbackImage(cameraId, zone, decoded);
    } catch (e, st) {
      final stLine = st.toString().split('\n').first;
      _log.error('Still-image fallback failed camera=$cameraId errorType=${e.runtimeType} error=$e stack=$stLine');
    } finally {
      processor.busy = false;
    }
  }

  Future<void> stopAllProcessors() async {
    final ids = _processorsByCameraId.keys.toList(growable: false);
    for (final id in ids) {
      await stopProcessor(id);
    }
  }

  Future<void> _loadTemplates() async {
    final people = await FaceAttendanceRepository.getPeople();
    final result = <_FaceTemplate>[];
    final byPerson = <String, _PersonScoreBucket>{};

    for (final p in people) {
      final bucket = byPerson.putIfAbsent(p.id, () => _PersonScoreBucket(person: p));
      final encodedImages = <String>[];
      if (p.imageBase64.trim().isNotEmpty) {
        encodedImages.add(p.imageBase64);
      }

      try {
        final extraImages = await FaceAttendanceRepository.getPersonImages(p.id);
        encodedImages.addAll(extraImages.map((image) => image.imageBase64));
      } catch (_) {
        // Keep the primary image usable even if the extra-image lookup fails.
      }

      for (final encodedImage in encodedImages) {
        if (encodedImage.trim().isEmpty) continue;
        try {
          final bytes = base64Decode(encodedImage);
          final decoded = img.decodeImage(bytes);
          if (decoded == null) continue;
          final sharpness = _imageSharpness(decoded);
          if (sharpness < _minTemplateSharpness) continue;
          final v = await _embeddingFromImage(decoded);
          final quality = (sharpness / 140.0).clamp(0.2, 1.0);
          final template = _FaceTemplate(person: p, vector: v, quality: quality);
          result.add(template);
          bucket.addTemplate(template);
        } catch (_) {
          continue;
        }
      }
    }

    _templates
      ..clear()
      ..addAll(result);
    _templatesByPersonId
      ..clear()
      ..addAll(byPerson);

    for (final bucket in _templatesByPersonId.values) {
      bucket.finalize();
    }

    final buckets = _templatesByPersonId.values.toList(growable: false);
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
        sims.add(_dotProduct(c, oc));
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

  Future<void> _processFrame(String cameraId, _Processor processor, CameraImage image) async {
    if (processor.busy) return;
    processor.frameCount++;
    if (processor.frameCount % 3 != 0) return;

    processor.busy = true;
    try {
      final zone = await FaceAttendanceRepository.getZoneByCameraId(cameraId);
      if (!zone.enabled) {
        _overlaysByCameraId[cameraId] = const [];
        _overlayTracksByCameraId.remove(cameraId);
        _emitFrame(cameraId, const []);
        processor.busy = false;
        return;
      }

      if (_supportsNativeFacePipeline) {
        final rgb = _cameraImageToRgb(image);
        final frameInput = _buildMediaPipeFrame(image);
        if (rgb == null || frameInput == null) {
          processor.busy = false;
          return;
        }

        final inference = await _runMediaPipeInference(frameInput);
        final faces = inference?.meshResults ?? const <FaceMeshResult>[];

        final overlays = <FaceOverlayBox>[];
        final nextTracks = <String, _CameraTrack>{};
        for (final f in faces) {
          final rect = f.boundingRect(targetSize: Size(rgb.width.toDouble(), rgb.height.toDouble()));
          final ratio = Rect.fromLTWH(
            (rect.left / rgb.width).clamp(0.0, 1.0),
            (rect.top / rgb.height).clamp(0.0, 1.0),
            (rect.width / rgb.width).clamp(0.0, 1.0),
            (rect.height / rgb.height).clamp(0.0, 1.0),
          );

          if (!_isInsideZone(ratio, zone)) {
            continue;
          }

          final crop = _alignFaceCrop(rgb, f);
          if (crop == null) continue;

          final frameQuality = (_imageSharpness(crop) / 140.0).clamp(0.0, 1.0);
          final vector = await _embeddingFromImage(crop);
          final faceLogKey = '${(ratio.center.dx * 100).round()}_${(ratio.center.dy * 100).round()}';
          final match = _findBestMatch(
            vector,
            excludedPersonIds: nextTracks.values.map((track) => track.event.personId).whereType<String>().toSet(),
            frameQuality: frameQuality,
            cameraId: cameraId,
            faceLogKey: faceLogKey,
          );
          final isKnown = match != null && match.score >= _knownMatchThreshold;

          final now = DateTime.now().millisecondsSinceEpoch;
          final event = isKnown
              ? RecognitionEvent(
                  id: _uuid.v4(),
                  personId: match.template.person.id,
                  personName: match.template.person.name,
                  cameraId: cameraId,
                  confidence: match.score.clamp(0, 0.99),
                  isStranger: false,
                  createdAt: now,
                  snapshotBase64: match.template.person.imageBase64,
                )
              : RecognitionEvent(
                  id: _uuid.v4(),
                  personName: 'Nguoi la',
                  cameraId: cameraId,
                  confidence: (match == null ? 0.42 : (1 - match.score)).clamp(0.30, 0.76),
                  isStranger: true,
                  createdAt: now,
                );

            final key = _matchTrackKey(cameraId, ratio, event, nextTracks);
          nextTracks[key] = _CameraTrack(
            key: key,
            currentRect: ratio,
            targetRect: ratio,
            event: event,
            lastSeenAt: now,
          );
          overlays.add(FaceOverlayBox(rectRatio: ratio, event: event));

            final eventKey = event.isStranger
              ? 'stranger_${cameraId}_${(ratio.center.dx * 10).round()}_${(ratio.center.dy * 10).round()}'
              : 'known_${cameraId}_${event.personId}_${(ratio.center.dx * 10).round()}_${(ratio.center.dy * 10).round()}';
          final lastAt = _lastEventAt[eventKey] ?? 0;
          if (now - lastAt > 1500) {
            _lastEventAt[eventKey] = now;
            unawaited(FaceAttendanceRepository.addEvent(event));
            if (!_notiQueue.isClosed) {
              _notiQueue.add(FaceRecognitionNotification(cameraId: cameraId, event: event));
            }
          }
        }

        _overlayTracksByCameraId[cameraId] = nextTracks;
        _overlaysByCameraId[cameraId] = overlays;
        _emitFrame(cameraId, overlays);
        if (processor.frameCount % 60 == 0) {
          _log.debug('Processed frame camera=$cameraId overlays=${overlays.length} mode=$runtimeModeLabel');
        }
      } else {
        final rgb = _cameraImageToRgb(image);
        if (rgb == null) return;
        await _processFallbackImage(cameraId, zone, rgb);
      }
    } catch (_) {
      // Keep frame pipeline alive when one frame fails.
      if (processor.frameCount % 60 == 0) {
        _log.error('Frame processing failed camera=$cameraId mode=$runtimeModeLabel');
      }
    } finally {
      processor.busy = false;
    }
  }

    Future<void> _processFallbackImage(String cameraId, RecognitionZone zone, img.Image rgb) async {
      try {
        final encoded = Uint8List.fromList(img.encodeJpg(rgb, quality: 92));
        List<tfl.Face> faces = const <tfl.Face>[];
        try {
          faces = await _fallbackFaceDetector.detectFaces(
            encoded,
            mode: tfl.FaceDetectionMode.fast,
          );
        } catch (e, st) {
          final stLine = st.toString().split('\n').first;
          _log.error('Fallback detectFaces failed camera=$cameraId errorType=${e.runtimeType} error=$e stack=$stLine');
        }

        final overlays = <FaceOverlayBox>[];
        final nextTracks = <String, _CameraTrack>{};
        for (final f in faces) {
          try {
            final bbox = f.boundingBox;
            final left = _toFiniteDouble(bbox.topLeft.x);
            final top = _toFiniteDouble(bbox.topLeft.y);
            final width = _toFiniteDouble(bbox.width);
            final height = _toFiniteDouble(bbox.height);
            if (left == null || top == null || width == null || height == null) {
              continue;
            }
            if (width <= 1 || height <= 1) {
              continue;
            }

            final rect = Rect.fromLTWH(left, top, width, height);
            final ratio = Rect.fromLTWH(
              (rect.left / rgb.width).clamp(0.0, 1.0),
              (rect.top / rgb.height).clamp(0.0, 1.0),
              (rect.width / rgb.width).clamp(0.0, 1.0),
              (rect.height / rgb.height).clamp(0.0, 1.0),
            );

            if (!_isInsideZone(ratio, zone)) continue;

            final crop = _cropFace(rgb, rect);
            if (crop == null) continue;

            final frameQuality = (_imageSharpness(crop) / 140.0).clamp(0.0, 1.0);
            final vector = await _embeddingFromImage(crop);
            final faceLogKey = '${(ratio.center.dx * 100).round()}_${(ratio.center.dy * 100).round()}';
            final match = _findBestMatch(
              vector,
              excludedPersonIds: nextTracks.values.map((track) => track.event.personId).whereType<String>().toSet(),
              frameQuality: frameQuality,
              cameraId: cameraId,
              faceLogKey: faceLogKey,
            );
            final isKnown = match != null && match.score >= _knownMatchThreshold;
            final now = DateTime.now().millisecondsSinceEpoch;
            final event = isKnown
                ? RecognitionEvent(
                    id: _uuid.v4(),
                    personId: match.template.person.id,
                    personName: match.template.person.name,
                    cameraId: cameraId,
                    confidence: match.score.clamp(0, 0.99),
                    isStranger: false,
                    createdAt: now,
                    snapshotBase64: match.template.person.imageBase64,
                  )
                : RecognitionEvent(
                    id: _uuid.v4(),
                    personName: 'Nguoi la',
                    cameraId: cameraId,
                    confidence: (match == null ? 0.42 : (1 - match.score)).clamp(0.30, 0.76),
                    isStranger: true,
                    createdAt: now,
                  );

            final key = _matchTrackKey(cameraId, ratio, event, nextTracks);
            nextTracks[key] = _CameraTrack(
              key: key,
              currentRect: ratio,
              targetRect: ratio,
              event: event,
              lastSeenAt: now,
            );
            overlays.add(FaceOverlayBox(rectRatio: ratio, event: event));

            final eventKey = event.isStranger
                ? 'stranger_${cameraId}_${(ratio.center.dx * 10).round()}_${(ratio.center.dy * 10).round()}'
                : 'known_${cameraId}_${event.personId}_${(ratio.center.dx * 10).round()}_${(ratio.center.dy * 10).round()}';
            final lastAt = _lastEventAt[eventKey] ?? 0;
            if (now - lastAt > 1500) {
              _lastEventAt[eventKey] = now;
              unawaited(FaceAttendanceRepository.addEvent(event));
              if (!_notiQueue.isClosed) {
                _notiQueue.add(FaceRecognitionNotification(cameraId: cameraId, event: event));
              }
            }
          } catch (e) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final count = (_fallbackFaceSkipCountByCameraId[cameraId] ?? 0) + 1;
            _fallbackFaceSkipCountByCameraId[cameraId] = count;
            final lastAt = _fallbackFaceSkipLogAtByCameraId[cameraId] ?? 0;
            if (now - lastAt >= _fallbackSkipLogIntervalMs) {
              _fallbackFaceSkipLogAtByCameraId[cameraId] = now;
              _log.debug('Fallback face skipped camera=$cameraId skipped=$count errorType=${e.runtimeType}');
              _fallbackFaceSkipCountByCameraId[cameraId] = 0;
            }
            continue;
          }
        }

        _overlayTracksByCameraId[cameraId] = nextTracks;
        _overlaysByCameraId[cameraId] = overlays;
        _emitFrame(cameraId, overlays);
      } catch (e, st) {
        final stLine = st.toString().split('\n').first;
        _log.error('Fallback processing failed camera=$cameraId errorType=${e.runtimeType} error=$e stack=$stLine');
      }
  }

        Future<FaceMeshMultiInferenceResult?> _runMediaPipeInference(_CameraFrameInput input) async {
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

        _CameraFrameInput? _buildMediaPipeFrame(CameraImage image) {
          final rotationDegrees = _rotationDegreesFor(image);

          if (defaultTargetPlatform == TargetPlatform.android) {
            final bytes = _cameraImageToNv21Bytes(image);
            if (bytes == null) return null;
            final nv21 = FaceMeshNv21Image.tryFromSinglePlane(
              bytes: bytes,
              width: image.width,
              height: image.height,
              bytesPerRow: image.width,
            );
            return nv21 == null ? null : _CameraFrameInput(image: nv21, rotationDegrees: rotationDegrees);
          }

          if (defaultTargetPlatform == TargetPlatform.iOS) {
            if (image.planes.isEmpty) return null;
            final plane = image.planes.first;
            final pixelFormat = image.format.group == ImageFormatGroup.bgra8888
                ? FaceMeshPixelFormat.bgra
                : FaceMeshPixelFormat.rgba;
            final faceImage = FaceMeshImage(
              pixels: Uint8List.fromList(plane.bytes),
              width: image.width,
              height: image.height,
              pixelFormat: pixelFormat,
              bytesPerRow: plane.bytesPerRow,
            );
            return _CameraFrameInput(image: faceImage, rotationDegrees: rotationDegrees);
          }

          return null;
        }

        int _rotationDegreesFor(CameraImage image) {
          final processor = _processorsByCameraId.values.isEmpty ? null : _processorsByCameraId.values.first;
          if (processor == null) return 0;
          final cameraOrientation = processor.controller.description.sensorOrientation;
          if (defaultTargetPlatform == TargetPlatform.android) {
            return cameraOrientation;
          }
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            return cameraOrientation;
          }
          return 0;
        }

        Uint8List? _cameraImageToNv21Bytes(CameraImage image) {
          if (image.format.group != ImageFormatGroup.yuv420 || image.planes.length < 3) {
            return null;
          }

          final yPlane = image.planes[0];
          final uPlane = image.planes[1];
          final vPlane = image.planes[2];
          final out = Uint8List(image.width * image.height * 3 ~/ 2);

          var offset = 0;
          for (var y = 0; y < image.height; y++) {
            final yRow = y * yPlane.bytesPerRow;
            for (var x = 0; x < image.width; x++) {
              out[offset++] = yPlane.bytes[yRow + x];
            }
          }

          final uvHeight = image.height ~/ 2;
          final uvWidth = image.width ~/ 2;
          final uStride = uPlane.bytesPerRow;
          final vStride = vPlane.bytesPerRow;
          final uPixelStride = uPlane.bytesPerPixel ?? 1;
          final vPixelStride = vPlane.bytesPerPixel ?? 1;

          for (var y = 0; y < uvHeight; y++) {
            final uRow = y * uStride;
            final vRow = y * vStride;
            for (var x = 0; x < uvWidth; x++) {
              final uIndex = uRow + x * uPixelStride;
              final vIndex = vRow + x * vPixelStride;
              out[offset++] = vPlane.bytes[vIndex];
              out[offset++] = uPlane.bytes[uIndex];
            }
          }

          return out;
        }

        String _matchTrackKey(String cameraId, Rect ratio, RecognitionEvent event, Map<String, _CameraTrack> nextTracks) {
          if (!event.isStranger && event.personId != null && event.personId!.isNotEmpty) {
            final previousTracks = _overlayTracksByCameraId[cameraId] ?? const <String, _CameraTrack>{};
            final knownKeys = <String>[
              ...previousTracks.keys,
              ...nextTracks.keys,
            ].where((key) => key.startsWith('known_${cameraId}_${event.personId}_')).toList(growable: false);

            String? bestKnownKey;
            var bestKnownScore = 0.0;
            for (final key in knownKeys) {
              final candidate = previousTracks[key] ?? nextTracks[key];
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

          var bestKey = 'stranger_${cameraId}_${(ratio.center.dx * 100).round()}_${(ratio.center.dy * 100).round()}';
          var bestScore = 0.0;
          for (final entry in nextTracks.entries) {
            final candidate = entry.value;
            final score = _rectIoU(candidate.currentRect, ratio) + (1 - _rectCenterDistance(candidate.currentRect, ratio).clamp(0.0, 1.0));
            if (score > bestScore) {
              bestScore = score;
              bestKey = entry.key;
            }
          }
          return bestKey;
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

        img.Image? _alignFaceCrop(img.Image source, FaceMeshResult face) {
          final faceRect = face.boundingRect(targetSize: Size(source.width.toDouble(), source.height.toDouble()));
          final expanded = _expandedRect(faceRect, source.width, source.height, 1.35);
          final crop = _cropFace(source, expanded);
          if (crop == null || face.landmarks.length <= 263) {
            return crop;
          }

          final leftEye = face.landmarks[33];
          final rightEye = face.landmarks[263];
          final angle = math.atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x) * 180 / math.pi;
          final rotated = img.copyRotate(crop, angle: -angle);
          return _centerCropSquare(rotated);
        }

        Rect _expandedRect(Rect rect, int width, int height, double factor) {
          final cx = rect.center.dx;
          final cy = rect.center.dy;
          final w = rect.width * factor;
          final h = rect.height * factor;
          final left = (cx - w / 2).clamp(0.0, width.toDouble() - 1);
          final top = (cy - h / 2).clamp(0.0, height.toDouble() - 1);
          final right = (cx + w / 2).clamp(left + 1, width.toDouble());
          final bottom = (cy + h / 2).clamp(top + 1, height.toDouble());
          return Rect.fromLTRB(left, top, right, bottom);
        }

  Future<List<double>> _embeddingFromImage(img.Image source) async {
    final aligned = _centerCropSquare(source);
    final session = _arcFaceSession;
    if (session == null) {
      return _vectorFromImage(aligned);
    }

    try {
      final resized = img.copyResize(aligned, width: 112, height: 112, interpolation: img.Interpolation.linear);
      final rgb = resized.getBytes(order: img.ChannelOrder.rgb);
      final input = List<double>.filled(1 * 3 * 112 * 112, 0);
      for (var y = 0; y < 112; y++) {
        for (var x = 0; x < 112; x++) {
          final pixelIndex = (y * 112 + x) * 3;
          final spatialIndex = y * 112 + x;
          input[spatialIndex] = (rgb[pixelIndex] - 127.5) / 128.0;
          input[112 * 112 + spatialIndex] = (rgb[pixelIndex + 1] - 127.5) / 128.0;
          input[2 * 112 * 112 + spatialIndex] = (rgb[pixelIndex + 2] - 127.5) / 128.0;
        }
      }

      final inputs = {
        _arcFaceInputName: await OrtValue.fromList(input, [1, 3, 112, 112]),
      };
      final outputs = await session.run(inputs);
      final output = outputs[_arcFaceOutputName] ?? (outputs.isNotEmpty ? outputs.values.first : null);
      final values = output == null ? const <dynamic>[] : await output.asList();
      final flattened = <double>[];
      _flattenNumericValues(values, flattened);
      if (flattened.isEmpty) {
        if (_onnxFallbackCount < 5) {
          _onnxFallbackCount++;
          _log.error('ArcFace output flatten failed, fallback vector used');
        }
        return _vectorFromImage(aligned);
      }

      final vector = flattened.length > 512 ? flattened.sublist(flattened.length - 512) : flattened;
      final norm = math.sqrt(vector.fold<double>(0, (sum, v) => sum + v * v));
      if (norm > 0) {
        for (var i = 0; i < vector.length; i++) {
          vector[i] = vector[i] / norm;
        }
      }
      return vector;
    } catch (e) {
      if (_onnxFallbackCount < 5) {
        _onnxFallbackCount++;
        _log.error('ArcFace inference failed, fallback vector used error=$e');
      }
      return _vectorFromImage(aligned);
    }
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

    final values = <double>[];
    values.length = (width - 2) * (height - 2);
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

  void _emitFrame(String cameraId, List<FaceOverlayBox> overlays) {
    if (_frameQueue.isClosed) return;
    _frameQueue.add(
      RecognitionFramePacket(
        cameraId: cameraId,
        overlays: overlays,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  _MatchResult? _findBestMatch(
    List<double> vector, {
    Set<String>? excludedPersonIds,
    double frameQuality = 1.0,
    String? cameraId,
    String? faceLogKey,
  }) {
    _CandidateScore? best;
    _CandidateScore? secondBest;
    _CandidateScore? bestByTemplate;
    _CandidateScore? bestByCentroid;
    final candidates = <_CandidateScore>[];
    final excluded = excludedPersonIds ?? const <String>{};

    for (final bucket in _templatesByPersonId.values) {
      if (bucket.templates.isEmpty) continue;
      if (excluded.contains(bucket.person.id)) continue;

      _FaceTemplate bestTemplate = bucket.templates.first;
      var templateScore = -1.0;
      for (final template in bucket.templates) {
        final score = _dotProduct(vector, template.vector) * (0.80 + template.quality * 0.20);
        if (score > templateScore) {
          templateScore = score;
          bestTemplate = template;
        }
      }
      final centroidScore = bucket.centroidScore(vector);
      final score = bucket.scoreAgainst(vector);
      final calibrated = bucket.calibrate(score);
      final candidate = _CandidateScore(
        bucket: bucket,
        template: bestTemplate,
        templateScore: templateScore,
        centroidScore: centroidScore,
        blendedScore: score,
        calibratedScore: calibrated,
      );
      candidates.add(candidate);

      if (bestByTemplate == null || candidate.templateScore > bestByTemplate.templateScore) {
        bestByTemplate = candidate;
      }

      if (bestByCentroid == null || candidate.centroidScore > bestByCentroid.centroidScore) {
        bestByCentroid = candidate;
      }

      if (best == null || candidate.calibratedScore > best.calibratedScore) {
        secondBest = best;
        best = candidate;
      } else if (secondBest == null || candidate.calibratedScore > secondBest.calibratedScore) {
        secondBest = candidate;
      }
    }

    if (best == null) return null;

    final profile = cameraId == null ? null : _cameraThresholdProfiles[cameraId];
    final baseMatchThreshold = profile?.matchThreshold ?? _knownMatchThreshold;
    final baseCalibratedThreshold = profile?.calibratedThreshold ?? _knownCalibratedThreshold;
    final strongThreshold = profile?.strongThreshold ?? _knownStrongThreshold;
    final marginThreshold = profile?.marginThreshold ?? _knownMatchMargin;

    final qualityPenalty = ((0.55 - frameQuality).clamp(0.0, 0.55)) * 0.20;
    final matchThreshold = baseMatchThreshold + qualityPenalty;
    final calibratedThreshold = baseCalibratedThreshold + qualityPenalty * 1.2;

    final sorted = [...candidates]..sort((a, b) => b.calibratedScore.compareTo(a.calibratedScore));
    final top1 = sorted.first;
    final top2 = sorted.length > 1 ? sorted[1] : null;

    final margin = best.calibratedScore - (secondBest?.calibratedScore ?? 0.0);
    var rejectionReason = '';
    if (best.blendedScore < matchThreshold) {
      rejectionReason = 'raw';
    } else if (best.calibratedScore < calibratedThreshold) {
      rejectionReason = 'calibrated';
    }

    final templateConsensus = bestByTemplate != null && bestByTemplate.bucket.person.id == best.bucket.person.id;
    final centroidConsensus = bestByCentroid != null && bestByCentroid.bucket.person.id == best.bucket.person.id;
    final dualConsensus = templateConsensus && centroidConsensus;

    if (rejectionReason.isEmpty && !dualConsensus && best.blendedScore < strongThreshold) {
      rejectionReason = 'consensus';
    }

    if (rejectionReason.isEmpty && margin < marginThreshold && best.blendedScore < strongThreshold) {
      rejectionReason = 'ambiguous';
    }

    final accepted = rejectionReason.isEmpty;
    _recordCalibrationSample(
      cameraId: cameraId,
      faceLogKey: faceLogKey,
      top1: top1,
      top2: top2,
      margin: margin,
      frameQuality: frameQuality,
      accepted: accepted,
    );

    if (!accepted) {
      if (_templatesByPersonId.isNotEmpty) {
        switch (rejectionReason) {
          case 'raw':
            _log.debug('Match rejected best=${best.blendedScore.toStringAsFixed(3)} cal=${best.calibratedScore.toStringAsFixed(3)} margin=${margin.toStringAsFixed(3)} threshold=${matchThreshold.toStringAsFixed(3)} q=${frameQuality.toStringAsFixed(3)} persons=${_templatesByPersonId.length}');
            break;
          case 'calibrated':
            _log.debug('Match rejected calibrated best=${best.blendedScore.toStringAsFixed(3)} cal=${best.calibratedScore.toStringAsFixed(3)} required=${calibratedThreshold.toStringAsFixed(3)} q=${frameQuality.toStringAsFixed(3)} persons=${_templatesByPersonId.length}');
            break;
          case 'consensus':
            _log.debug('Match rejected consensus best=${best.blendedScore.toStringAsFixed(3)} cal=${best.calibratedScore.toStringAsFixed(3)} tpl=${bestByTemplate?.bucket.person.name} ctr=${bestByCentroid?.bucket.person.name} strong=${strongThreshold.toStringAsFixed(3)}');
            break;
          default:
            _log.debug('Match rejected ambiguous best=${best.blendedScore.toStringAsFixed(3)} cal=${best.calibratedScore.toStringAsFixed(3)} margin=${margin.toStringAsFixed(3)} required=${marginThreshold.toStringAsFixed(3)} strong=${strongThreshold.toStringAsFixed(3)} persons=${_templatesByPersonId.length}');
        }
      }
      return null;
    }

    _log.debug('Match accepted best=${best.blendedScore.toStringAsFixed(3)} cal=${best.calibratedScore.toStringAsFixed(3)} margin=${margin.toStringAsFixed(3)} q=${frameQuality.toStringAsFixed(3)} person=${best.template.person.name}');

    return _MatchResult(
      template: best.template,
      score: best.blendedScore,
      calibratedScore: best.calibratedScore,
    );
  }

  void _startCameraCalibrationWindow(String cameraId) {
    if (_cameraThresholdProfiles.containsKey(cameraId) || _calibrationWindows.containsKey(cameraId)) {
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
    _log.info('Calibration started camera=$cameraId duration=${_cameraCalibrationDuration.inSeconds}s (top-2 logs enabled)');
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
    _log.debug(
      'CalibTop2 camera=$cameraId face=$key q=${frameQuality.toStringAsFixed(3)} '
      'top1=${top1.bucket.person.name}:${top1.blendedScore.toStringAsFixed(3)}/${top1.calibratedScore.toStringAsFixed(3)}/qt${top1.template.quality.toStringAsFixed(3)} '
      'top2=$top2Name:${top2Raw.toStringAsFixed(3)}/${top2Cal.toStringAsFixed(3)}/qt${(top2?.template.quality ?? 0.0).toStringAsFixed(3)} '
      'margin=${margin.toStringAsFixed(3)} accepted=$accepted',
    );
  }

  void _finalizeCameraCalibration(String cameraId) {
    final window = _calibrationWindows.remove(cameraId);
    if (window == null) return;
    window.timer?.cancel();

    final samples = window.samples;
    if (samples.length < 12) {
      _log.info('Calibration skipped camera=$cameraId samples=${samples.length} (need >=12)');
      return;
    }

    final impostorRaw = samples.where((s) => s.top2Raw > 0).map((s) => s.top2Raw).toList();
    final impostorCal = samples.where((s) => s.top2Cal > -0.5).map((s) => s.top2Cal).toList();
    final acceptedRaw = samples.where((s) => s.accepted).map((s) => s.top1Raw).toList();
    final acceptedCal = samples.where((s) => s.accepted).map((s) => s.top1Cal).toList();
    final allMargins = samples.where((s) => s.margin >= 0).map((s) => s.margin).toList();

    var lockedMatch = _knownMatchThreshold;
    var lockedCalibrated = _knownCalibratedThreshold;
    var lockedMargin = _knownMatchMargin;

    if (impostorRaw.isNotEmpty) {
      lockedMatch = math.max(lockedMatch, _percentile(impostorRaw, 0.98) + 0.012);
    }
    if (acceptedRaw.isNotEmpty) {
      lockedMatch = math.min(lockedMatch, _percentile(acceptedRaw, 0.12) - 0.008);
    }
    lockedMatch = lockedMatch.clamp(0.86, 0.94);

    if (impostorCal.isNotEmpty) {
      lockedCalibrated = math.max(lockedCalibrated, _percentile(impostorCal, 0.985) + 0.06);
    }
    if (acceptedCal.isNotEmpty) {
      lockedCalibrated = math.min(lockedCalibrated, _percentile(acceptedCal, 0.12) - 0.05);
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
    return null;
  }

  bool _isInsideZone(Rect rectRatio, RecognitionZone zone) {
    final cx = rectRatio.center.dx;
    final cy = rectRatio.center.dy;
    return cx >= zone.leftRatio &&
        cx <= zone.leftRatio + zone.widthRatio &&
        cy >= zone.topRatio &&
        cy <= zone.topRatio + zone.heightRatio;
  }

  img.Image _centerCropSquare(img.Image input) {
    final side = math.min(input.width, input.height);
    final x = ((input.width - side) / 2).round();
    final y = ((input.height - side) / 2).round();
    return img.copyCrop(input, x: x, y: y, width: side, height: side);
  }

  img.Image? _cropFace(img.Image source, Rect rect) {
    final x = rect.left.floor().clamp(0, source.width - 1);
    final y = rect.top.floor().clamp(0, source.height - 1);
    final w = rect.width.ceil().clamp(8, source.width - x);
    final h = rect.height.ceil().clamp(8, source.height - y);
    if (w <= 0 || h <= 0) return null;
    return img.copyCrop(source, x: x, y: y, width: w, height: h);
  }

  List<double> _vectorFromImage(img.Image source) {
    final square = _centerCropSquare(source);
    final resized = img.copyResize(square, width: 24, height: 24, interpolation: img.Interpolation.linear);
    final rgb = resized.getBytes(order: img.ChannelOrder.rgb);
    final vector = List<double>.filled(24 * 24, 0);

    var sumSq = 0.0;
    var j = 0;
    for (var i = 0; i < rgb.length; i += 3) {
      final gray = (0.299 * rgb[i] + 0.587 * rgb[i + 1] + 0.114 * rgb[i + 2]) / 255.0;
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
    if (image.format.group == ImageFormatGroup.bgra8888 && image.planes.isNotEmpty) {
      final bytes = image.planes.first.bytes;
      final output = img.Image(width: image.width, height: image.height);
      var index = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
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

    if (image.format.group != ImageFormatGroup.yuv420 || image.planes.length < 3) {
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
        final g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round().clamp(0, 255);
        final b = (yp + 1.772 * (up - 128)).round().clamp(0, 255);
        output.setPixelRgb(x, y, r, g, b);
      }
    }
    return output;
  }

  Future<void> dispose() async {
    _templateMonitorTimer?.cancel();
    _templateMonitorTimer = null;
    for (final p in _processorsByCameraId.values) {
      if (p.controller.value.isStreamingImages) {
        await p.controller.stopImageStream();
      }
      await p.controller.dispose();
    }
    _processorsByCameraId.clear();
    _overlaysByCameraId.clear();
    _overlayTracksByCameraId.clear();
    _arcFaceSession?.close();
    _faceDetectorProcessor?.close();
    _faceMeshProcessor?.close();
    await _frameQueue.close();
    await _notiQueue.close();
  }
}
