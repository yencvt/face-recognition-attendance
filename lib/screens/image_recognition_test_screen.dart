import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_cam/models/face_person.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/face_attendance_repository.dart';
import '../l10n/app_i18n.dart';
import '../database/recognition_settings_repository.dart';
import '../services/face_recognition_service.dart';

class _RecognitionFieldDef {
  const _RecognitionFieldDef({
    required this.key,
    required this.label,
    required this.isInt,
  });

  final String key;
  final String label;
  final bool isInt;
}

class _RecognitionSectionDef {
  const _RecognitionSectionDef({
    required this.title,
    required this.fields,
    this.switchKeys = const <String>[],
  });

  final String title;
  final List<_RecognitionFieldDef> fields;
  final List<String> switchKeys;
}

class ImageRecognitionTestScreen extends StatefulWidget {
  const ImageRecognitionTestScreen({super.key});

  @override
  State<ImageRecognitionTestScreen> createState() =>
      _ImageRecognitionTestScreenState();
}

class _ImageRecognitionTestScreenState
    extends State<ImageRecognitionTestScreen> {
  String _l(BuildContext context, String vi, String en) {
    return AppI18n.of(context).locale.languageCode == 'en' ? en : vi;
  }

  String _sectionTitleText(BuildContext context, String title) {
    final en = <String, String>{
      'Ngưỡng nhận diện': 'Recognition thresholds',
      'Luồng xử lý thời gian thực': 'Realtime pipeline',
      'Theo dõi ByteTrack': 'ByteTrack tracking',
      'Chất lượng thời gian thực': 'Realtime quality',
      'Đăng ký khuôn mặt': 'Enrollment constraints',
      'Phát hiện và tìm kiếm': 'Detection and search',
      'Xử lý đầu vào và gỡ lỗi': 'Input processing and debug',
    };
    return _l(context, title, en[title] ?? title);
  }

  String _fieldLabelText(BuildContext context, String label) {
    final en = <String, String>{
      'Ngưỡng khớp khuôn mặt': 'Known match threshold',
      'Ngưỡng khớp đã hiệu chỉnh': 'Calibrated match threshold',
      'Biên an toàn giữa hạng 1 và hạng 2':
          'Safety margin between rank 1 and rank 2',
      'Độ nét tối thiểu của mẫu đăng ký':
          'Minimum enrollment template sharpness',
      'Thời gian hiệu chỉnh camera (ms)': 'Camera calibration duration (ms)',
      'Khoảng cách log hiệu chỉnh (ms)': 'Calibration log interval (ms)',
      'Khoảng cách log bỏ qua fallback (ms)': 'Fallback skip-log interval (ms)',
      'Chu kỳ chụp fallback (ms)': 'Fallback capture interval (ms)',
      'Cạnh tối đa ảnh fallback (px)': 'Fallback max input edge (px)',
      'Chu kỳ xử lý khung hình (ms)': 'Frame processing interval (ms)',
      'Số khung hình giữ lại của xử lý đơn luồng': 'Keep-latest frame count',
      'Số luồng Face Mesh tối đa': 'Maximum Face Mesh workers',
      'Chiều rộng đầu vào bộ phát hiện': 'Detector input width',
      'Chiều cao đầu vào bộ phát hiện': 'Detector input height',
      'Thời gian giữ track (ms)': 'Track keep-alive duration (ms)',
      'Điểm tối thiểu để gán track': 'Minimum score to assign track',
      'ByteTrack: thời gian tái dùng người đã biết (ms)':
          'ByteTrack: known-track cache reuse (ms)',
      'ByteTrack: thời gian tái dùng người lạ (ms)':
          'ByteTrack: stranger-track cache reuse (ms)',
      'ByteTrack: ngưỡng refresh yaw/pitch (độ)':
          'ByteTrack: yaw/pitch refresh threshold (deg)',
      'Hệ số làm mượt bbox': 'Bounding-box smoothing factor',
      'Khoảng cách lớp phủ tối thiểu giữa các khung hình (ms)':
          'Minimum annotated-frame interval (ms)',
      'Khoảng cách phát sự kiện (ms)': 'Event publish interval (ms)',
      'Chất lượng khung hình tối thiểu thời gian thực':
          'Minimum realtime frame quality',
      'Tỷ lệ diện tích mặt tối thiểu thời gian thực':
          'Minimum realtime face area ratio',
      'Số pixel mặt tối thiểu thời gian thực': 'Minimum realtime face pixels',
      'Vùng cục bộ thời gian thực: ngưỡng chất lượng tối thiểu':
          'Realtime partial: minimum quality threshold',
      'Vùng cục bộ thời gian thực: tỷ lệ diện tích mặt tối thiểu':
          'Realtime partial: minimum face area ratio',
      'Vùng cục bộ thời gian thực: số pixel mặt tối thiểu':
          'Realtime partial: minimum face pixels',
      'Vùng cục bộ thời gian thực: chế độ (0=chất lượng/kích thước, 1=mọi khung hình, 2=tắt)':
          'Realtime partial: mode (0=quality/size, 1=every frame, 2=off)',
      'Vùng cục bộ thời gian thực: chu kỳ khung hình (N = 1/N khung)':
          'Realtime partial: frame cycle (N = 1/N frames)',
      'Tỷ lệ diện tích mặt tối thiểu khi đăng ký':
          'Minimum enrollment face area ratio',
      'Tỷ lệ diện tích mặt tối đa khi đăng ký':
          'Maximum enrollment face area ratio',
      'Tỷ lệ khung mặt tối thiểu khi đăng ký':
          'Minimum enrollment face aspect ratio',
      'Tỷ lệ khung mặt tối đa khi đăng ký':
          'Maximum enrollment face aspect ratio',
      'Số pixel mặt tối thiểu khi đăng ký': 'Minimum enrollment face pixels',
      'Kích thước đầu vào SCRFD': 'SCRFD input size',
      'Ngưỡng điểm phát hiện SCRFD': 'SCRFD score threshold',
      'Ngưỡng NMS SCRFD': 'SCRFD NMS threshold',
      'HNSW M': 'HNSW M',
      'HNSW efConstruction': 'HNSW efConstruction',
      'HNSW efSearch': 'HNSW efSearch',
      'Ngưỡng chất lượng vùng mắt': 'Eye region quality threshold',
      'Ngưỡng chất lượng vùng mũi': 'Nose region quality threshold',
      'Ngưỡng chất lượng vùng miệng': 'Mouth region quality threshold',
      'Mức làm sắc nét tự động tối đa': 'Maximum auto-sharpen amount',
      'Mức làm sắc nét tự động tối đa (0.0..1.0)':
          'Maximum auto-sharpen amount (0.0..1.0)',
    };
    return _l(context, label, en[label] ?? label);
  }

  String _regionLabelText(BuildContext context, String vi) {
    final en = <String, String>{
      'Trán': 'Forehead',
      'Mắt trái': 'Left eye',
      'Mắt phải': 'Right eye',
      'Mũi': 'Nose',
      'Má trái': 'Left cheek',
      'Má phải': 'Right cheek',
      'Miệng': 'Mouth',
      'Cằm': 'Chin',
    };
    return _l(context, vi, en[vi] ?? vi);
  }

  String _switchLabelText(BuildContext context, String key) {
    final vi = _switchLabels[key] ?? key;
    final en = <String, String>{
      'enableRealtimeAutoSharpen': 'Enable realtime auto-sharpen',
      'debugRealtimeOverlay': 'Enable realtime debug overlay',
      'enableTraceLogs': 'Enable detailed trace logs',
      'enablePerfLogs': 'Enable performance logs',
      'realtimeCropFacesFromCameraImage':
          'Realtime: crop faces directly from camera image',
    };
    return _l(context, vi, en[key] ?? vi);
  }

  static const Map<String, String> _switchLabels = {
    'enableRealtimeAutoSharpen': 'Bật tự động làm sắc nét ảnh thời gian thực',
    'debugRealtimeOverlay': 'Bật lớp phủ gỡ lỗi thời gian thực',
    'enableTraceLogs': 'Bật nhật ký theo vết chi tiết thời gian thực',
    'enablePerfLogs': 'Bật nhật ký hiệu năng độ trễ',
    'realtimeCropFacesFromCameraImage':
        'Thời gian thực: cắt từng khuôn mặt trực tiếp từ ảnh camera',
  };

  static const List<_RecognitionSectionDef> _configSections = [
    _RecognitionSectionDef(
      title: 'Ngưỡng nhận diện',
      fields: [
        _RecognitionFieldDef(
          key: 'knownMatchThreshold',
          label: 'Ngưỡng khớp khuôn mặt',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'knownCalibratedThreshold',
          label: 'Ngưỡng khớp đã hiệu chỉnh',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'knownMatchMargin',
          label: 'Biên an toàn giữa hạng 1 và hạng 2',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'minTemplateSharpness',
          label: 'Độ nét tối thiểu của mẫu đăng ký',
          isInt: false,
        ),
      ],
    ),
    _RecognitionSectionDef(
      title: 'Luồng xử lý thời gian thực',
      fields: [
        _RecognitionFieldDef(
          key: 'cameraCalibrationDurationMs',
          label: 'Thời gian hiệu chỉnh camera (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'calibrationLogThrottleMs',
          label: 'Khoảng cách log hiệu chỉnh (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'fallbackSkipLogIntervalMs',
          label: 'Khoảng cách log bỏ qua fallback (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'fallbackCaptureIntervalMs',
          label: 'Chu kỳ chụp fallback (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'fallbackMaxInputEdge',
          label: 'Cạnh tối đa ảnh fallback (px)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'processFrameIntervalMs',
          label: 'Chu kỳ xử lý khung hình (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'singleFlightKeepLatestFrames',
          label: 'Số khung hình giữ lại của xử lý đơn luồng',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'faceMeshMaxWorkers',
          label: 'Số luồng Face Mesh tối đa',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'detectorInputWidth',
          label: 'Chiều rộng đầu vào bộ phát hiện',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'detectorInputHeight',
          label: 'Chiều cao đầu vào bộ phát hiện',
          isInt: true,
        ),
      ],
    ),
    _RecognitionSectionDef(
      title: 'Theo dõi ByteTrack',
      fields: [
        _RecognitionFieldDef(
          key: 'trackKeepAliveMs',
          label: 'Thời gian giữ track (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'trackMatchMinScore',
          label: 'Điểm tối thiểu để gán track',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'trackReuseKnownMs',
          label: 'ByteTrack: thời gian tái dùng người đã biết (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'trackReuseStrangerMs',
          label: 'ByteTrack: thời gian tái dùng người lạ (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'trackPoseRefreshDeltaDeg',
          label: 'ByteTrack: ngưỡng refresh yaw/pitch (độ)',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'bboxSmoothingAlpha',
          label: 'Hệ số làm mượt bbox',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'annotatedFrameMinIntervalMs',
          label: 'Khoảng cách lớp phủ tối thiểu giữa các khung hình (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'eventPublishIntervalMs',
          label: 'Khoảng cách phát sự kiện (ms)',
          isInt: true,
        ),
      ],
    ),
    _RecognitionSectionDef(
      title: 'Chất lượng thời gian thực',
      fields: [
        _RecognitionFieldDef(
          key: 'minRealtimeFrameQuality',
          label: 'Chất lượng khung hình tối thiểu thời gian thực',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'minRealtimeFaceAreaRatio',
          label: 'Tỷ lệ diện tích mặt tối thiểu thời gian thực',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'minRealtimeFacePixels',
          label: 'Số pixel mặt tối thiểu thời gian thực',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'realtimePartialMinFrameQuality',
          label: 'Vùng cục bộ thời gian thực: ngưỡng chất lượng tối thiểu',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'realtimePartialMinFaceAreaRatio',
          label: 'Vùng cục bộ thời gian thực: tỷ lệ diện tích mặt tối thiểu',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'realtimePartialMinFacePixels',
          label: 'Vùng cục bộ thời gian thực: số pixel mặt tối thiểu',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'realtimePartialMode',
          label:
              'Vùng cục bộ thời gian thực: chế độ (0=chất lượng/kích thước, 1=mọi khung hình, 2=tắt)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'realtimePartialFrameCycle',
          label:
              'Vùng cục bộ thời gian thực: chu kỳ khung hình (N = 1/N khung)',
          isInt: true,
        ),
      ],
    ),
    _RecognitionSectionDef(
      title: 'Đăng ký khuôn mặt',
      fields: [
        _RecognitionFieldDef(
          key: 'minEnrollmentFaceAreaRatio',
          label: 'Tỷ lệ diện tích mặt tối thiểu khi đăng ký',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'maxEnrollmentFaceAreaRatio',
          label: 'Tỷ lệ diện tích mặt tối đa khi đăng ký',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'minEnrollmentFaceAspectRatio',
          label: 'Tỷ lệ khung mặt tối thiểu khi đăng ký',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'maxEnrollmentFaceAspectRatio',
          label: 'Tỷ lệ khung mặt tối đa khi đăng ký',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'minEnrollmentFacePixels',
          label: 'Số pixel mặt tối thiểu khi đăng ký',
          isInt: true,
        ),
      ],
    ),
    _RecognitionSectionDef(
      title: 'Phát hiện và tìm kiếm',
      fields: [
        _RecognitionFieldDef(
          key: 'scrfdInputSize',
          label: 'Kích thước đầu vào SCRFD',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'scrfdScoreThreshold',
          label: 'Ngưỡng điểm phát hiện SCRFD',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'scrfdNmsThreshold',
          label: 'Ngưỡng NMS SCRFD',
          isInt: false,
        ),
        _RecognitionFieldDef(key: 'hnswM', label: 'HNSW M', isInt: true),
        _RecognitionFieldDef(
          key: 'hnswEfConstruction',
          label: 'HNSW efConstruction',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'hnswEfSearch',
          label: 'HNSW efSearch',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'eyeRegionMinQuality',
          label: 'Ngưỡng chất lượng vùng mắt',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'noseRegionMinQuality',
          label: 'Ngưỡng chất lượng vùng mũi',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'mouthRegionMinQuality',
          label: 'Ngưỡng chất lượng vùng miệng',
          isInt: false,
        ),
      ],
    ),
    _RecognitionSectionDef(
      title: 'Xử lý đầu vào và gỡ lỗi',
      fields: [
        _RecognitionFieldDef(
          key: 'autoTuneMaxSharpenAmount',
          label: 'Mức làm sắc nét tự động tối đa (0.0..1.0)',
          isInt: false,
        ),
      ],
      switchKeys: [
        'enableRealtimeAutoSharpen',
        'debugRealtimeOverlay',
        'enableTraceLogs',
        'enablePerfLogs',
        'realtimeCropFacesFromCameraImage',
      ],
    ),
  ];

  final FaceRecognitionService _service = FaceRecognitionService.instance;
  final Map<String, TextEditingController> _configControllers = {
    for (final section in _configSections)
      for (final field in section.fields) field.key: TextEditingController(),
  };

  List<FacePerson> _people = const <FacePerson>[];
  final Set<String> _selectedPersonIds = <String>{};

  Uint8List? _originalImageBytes;
  String? _fileName;

  bool _isRunning = false;
  bool _isDraggingUpload = false;
  bool _isLoadingConfig = true;
  bool _isApplyingConfig = false;
  bool _enableRealtimeAutoSharpen = false;
  bool _debugRealtimeOverlay = true;
  bool _enableTraceLogs = false;
  bool _enablePerfLogs = false;
  bool _realtimeCropFacesFromCameraImage = false;
  final Set<String> _expandedConfigSections = <String>{
    'Ngưỡng nhận diện',
    'Theo dõi ByteTrack',
    'Chất lượng thời gian thực',
    'Xử lý đầu vào và gỡ lỗi',
  };
  Set<String> _realtimePartialEnabledRegions = <String>{
    'forehead',
    'leftEye',
    'rightEye',
    'nose',
    'leftCheek',
    'rightCheek',
    'mouth',
    'chin',
  };

  static const Map<String, String> _partialRegionLabels = {
    'forehead': 'Trán',
    'leftEye': 'Mắt trái',
    'rightEye': 'Mắt phải',
    'nose': 'Mũi',
    'leftCheek': 'Má trái',
    'rightCheek': 'Má phải',
    'mouth': 'Miệng',
    'chin': 'Cằm',
  };
  double _matchThreshold = 0.55;
  UploadedImageRecognitionResult? _result;

  @override
  void initState() {
    super.initState();
    _loadPeople();
    _loadRecognitionConfig();
  }

  @override
  void dispose() {
    for (final controller in _configControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPeople() async {
    final people = await FaceAttendanceRepository.getPeople();
    if (!mounted) return;
    setState(() {
      _people = people;
      final validIds = people.map((p) => p.id).toSet();
      _selectedPersonIds.removeWhere((id) => !validIds.contains(id));
    });
  }

  Future<void> _loadRecognitionConfig() async {
    final config =
        await RecognitionSettingsRepository.getOrCreateDefaultConfig();
    if (!mounted) return;
    _fillConfigControllers(config);
    setState(() {
      _isLoadingConfig = false;
    });
  }

  void _fillConfigControllers(RecognitionRuntimeConfig config) {
    _matchThreshold = config.knownMatchThreshold;
    _configControllers['knownMatchThreshold']!.text = config.knownMatchThreshold
        .toString();
    _configControllers['knownCalibratedThreshold']!.text = config
        .knownCalibratedThreshold
        .toString();
    _configControllers['knownMatchMargin']!.text = config.knownMatchMargin
        .toString();
    _configControllers['minTemplateSharpness']!.text = config
        .minTemplateSharpness
        .toString();
    _configControllers['cameraCalibrationDurationMs']!.text = config
        .cameraCalibrationDurationMs
        .toString();
    _configControllers['calibrationLogThrottleMs']!.text = config
        .calibrationLogThrottleMs
        .toString();
    _configControllers['fallbackSkipLogIntervalMs']!.text = config
        .fallbackSkipLogIntervalMs
        .toString();
    _configControllers['fallbackCaptureIntervalMs']!.text = config
        .fallbackCaptureIntervalMs
        .toString();
    _configControllers['fallbackMaxInputEdge']!.text = config
        .fallbackMaxInputEdge
        .toString();
    _configControllers['processFrameIntervalMs']!.text = config
        .processFrameIntervalMs
        .toString();
    _configControllers['singleFlightKeepLatestFrames']!.text = config
        .singleFlightKeepLatestFrames
        .toString();
    _configControllers['faceMeshMaxWorkers']!.text = config.faceMeshMaxWorkers
        .toString();
    _configControllers['detectorInputWidth']!.text = config.detectorInputWidth
        .toString();
    _configControllers['detectorInputHeight']!.text = config.detectorInputHeight
        .toString();
    _configControllers['trackKeepAliveMs']!.text = config.trackKeepAliveMs
        .toString();
    _configControllers['trackMatchMinScore']!.text = config.trackMatchMinScore
        .toString();
    _configControllers['trackReuseKnownMs']!.text = config.trackReuseKnownMs
        .toString();
    _configControllers['trackReuseStrangerMs']!.text = config
        .trackReuseStrangerMs
        .toString();
    _configControllers['trackPoseRefreshDeltaDeg']!.text = config
        .trackPoseRefreshDeltaDeg
        .toString();
    _configControllers['bboxSmoothingAlpha']!.text = config.bboxSmoothingAlpha
        .toString();
    _configControllers['annotatedFrameMinIntervalMs']!.text = config
        .annotatedFrameMinIntervalMs
        .toString();
    _configControllers['eventPublishIntervalMs']!.text = config
        .eventPublishIntervalMs
        .toString();
    _configControllers['minRealtimeFrameQuality']!.text = config
        .minRealtimeFrameQuality
        .toString();
    _configControllers['minRealtimeFaceAreaRatio']!.text = config
        .minRealtimeFaceAreaRatio
        .toString();
    _configControllers['minRealtimeFacePixels']!.text = config
        .minRealtimeFacePixels
        .toString();
    _configControllers['realtimePartialMinFrameQuality']!.text = config
        .realtimePartialMinFrameQuality
        .toString();
    _configControllers['realtimePartialMinFaceAreaRatio']!.text = config
        .realtimePartialMinFaceAreaRatio
        .toString();
    _configControllers['realtimePartialMinFacePixels']!.text = config
        .realtimePartialMinFacePixels
        .toString();
    _configControllers['realtimePartialMode']!.text = config.realtimePartialMode
        .toString();
    _configControllers['realtimePartialFrameCycle']!.text = config
        .realtimePartialFrameCycle
        .toString();
    _realtimePartialEnabledRegions = config.realtimePartialEnabledRegions
        .split(',')
        .map((item) => item.trim())
        .where((item) => _partialRegionLabels.containsKey(item))
        .toSet();
    if (_realtimePartialEnabledRegions.isEmpty) {
      _realtimePartialEnabledRegions = _partialRegionLabels.keys.toSet();
    }
    _configControllers['minEnrollmentFaceAreaRatio']!.text = config
        .minEnrollmentFaceAreaRatio
        .toString();
    _configControllers['maxEnrollmentFaceAreaRatio']!.text = config
        .maxEnrollmentFaceAreaRatio
        .toString();
    _configControllers['minEnrollmentFaceAspectRatio']!.text = config
        .minEnrollmentFaceAspectRatio
        .toString();
    _configControllers['maxEnrollmentFaceAspectRatio']!.text = config
        .maxEnrollmentFaceAspectRatio
        .toString();
    _configControllers['minEnrollmentFacePixels']!.text = config
        .minEnrollmentFacePixels
        .toString();
    _configControllers['scrfdInputSize']!.text = config.scrfdInputSize
        .toString();
    _configControllers['scrfdScoreThreshold']!.text = config.scrfdScoreThreshold
        .toString();
    _configControllers['scrfdNmsThreshold']!.text = config.scrfdNmsThreshold
        .toString();
    _configControllers['hnswM']!.text = config.hnswM.toString();
    _configControllers['hnswEfConstruction']!.text = config.hnswEfConstruction
        .toString();
    _configControllers['hnswEfSearch']!.text = config.hnswEfSearch.toString();
    _configControllers['eyeRegionMinQuality']!.text = config.eyeRegionMinQuality
        .toString();
    _configControllers['noseRegionMinQuality']!.text = config
        .noseRegionMinQuality
        .toString();
    _configControllers['mouthRegionMinQuality']!.text = config
        .mouthRegionMinQuality
        .toString();
    _configControllers['autoTuneMaxSharpenAmount']!.text = config
        .autoTuneMaxSharpenAmount
        .toString();
    _enableRealtimeAutoSharpen = config.enableRealtimeAutoSharpen;
    _debugRealtimeOverlay = config.debugRealtimeOverlay;
    _enableTraceLogs = config.enableTraceLogs;
    _enablePerfLogs = config.enablePerfLogs;
    _realtimeCropFacesFromCameraImage = config.realtimeCropFacesFromCameraImage;
  }

  int _parseIntField(String key, String label) {
    final value = int.tryParse(_configControllers[key]!.text.trim());
    if (value == null) {
      throw FormatException(
        _l(
          context,
          'Giá trị "${_fieldLabelText(context, label)}" không hợp lệ',
          'Invalid value for "${_fieldLabelText(context, label)}"',
        ),
      );
    }
    return value;
  }

  double _parseDoubleField(String key, String label) {
    final value = double.tryParse(_configControllers[key]!.text.trim());
    if (value == null) {
      throw FormatException(
        _l(
          context,
          'Giá trị "${_fieldLabelText(context, label)}" không hợp lệ',
          'Invalid value for "${_fieldLabelText(context, label)}"',
        ),
      );
    }
    return value;
  }

  Future<void> _applyRecognitionConfig({VoidCallback? onStateChanged}) async {
    setState(() {
      _isApplyingConfig = true;
    });
    onStateChanged?.call();

    try {
      final config = RecognitionRuntimeConfig(
        knownMatchThreshold: _parseDoubleField(
          'knownMatchThreshold',
          'Ngưỡng khớp khuôn mặt',
        ),
        knownCalibratedThreshold: _parseDoubleField(
          'knownCalibratedThreshold',
          'Ngưỡng khớp đã hiệu chỉnh',
        ),
        knownMatchMargin: _parseDoubleField(
          'knownMatchMargin',
          'Biên an toàn giữa hạng 1 và hạng 2',
        ),
        minTemplateSharpness: _parseDoubleField(
          'minTemplateSharpness',
          'Độ nét tối thiểu của mẫu đăng ký',
        ),
        cameraCalibrationDurationMs: _parseIntField(
          'cameraCalibrationDurationMs',
          'Thời gian hiệu chỉnh camera (ms)',
        ),
        calibrationLogThrottleMs: _parseIntField(
          'calibrationLogThrottleMs',
          'Khoảng cách log hiệu chỉnh (ms)',
        ),
        fallbackSkipLogIntervalMs: _parseIntField(
          'fallbackSkipLogIntervalMs',
          'Khoảng cách log bỏ qua fallback (ms)',
        ),
        fallbackCaptureIntervalMs: _parseIntField(
          'fallbackCaptureIntervalMs',
          'Chu kỳ chụp fallback (ms)',
        ),
        fallbackMaxInputEdge: _parseIntField(
          'fallbackMaxInputEdge',
          'Cạnh tối đa ảnh fallback (px)',
        ),
        processFrameIntervalMs: _parseIntField(
          'processFrameIntervalMs',
          'Chu kỳ xử lý khung hình (ms)',
        ),
        singleFlightKeepLatestFrames: _parseIntField(
          'singleFlightKeepLatestFrames',
          'Số khung hình giữ lại của xử lý đơn luồng',
        ),
        faceMeshMaxWorkers: _parseIntField(
          'faceMeshMaxWorkers',
          'Số luồng Face Mesh tối đa',
        ),
        detectorInputWidth: _parseIntField(
          'detectorInputWidth',
          'Chiều rộng đầu vào bộ phát hiện',
        ),
        detectorInputHeight: _parseIntField(
          'detectorInputHeight',
          'Chiều cao đầu vào bộ phát hiện',
        ),
        trackKeepAliveMs: _parseIntField(
          'trackKeepAliveMs',
          'Thời gian giữ track (ms)',
        ),
        trackMatchMinScore: _parseDoubleField(
          'trackMatchMinScore',
          'Điểm tối thiểu để gán track',
        ),
        trackReuseKnownMs: _parseIntField(
          'trackReuseKnownMs',
          'ByteTrack: thời gian tái dùng người đã biết (ms)',
        ),
        trackReuseStrangerMs: _parseIntField(
          'trackReuseStrangerMs',
          'ByteTrack: thời gian tái dùng người lạ (ms)',
        ),
        trackPoseRefreshDeltaDeg: _parseDoubleField(
          'trackPoseRefreshDeltaDeg',
          'ByteTrack: ngưỡng refresh yaw/pitch (độ)',
        ),
        bboxSmoothingAlpha: _parseDoubleField(
          'bboxSmoothingAlpha',
          'Hệ số làm mượt bbox',
        ),
        annotatedFrameMinIntervalMs: _parseIntField(
          'annotatedFrameMinIntervalMs',
          'Khoảng cách lớp phủ tối thiểu giữa các khung hình (ms)',
        ),
        eventPublishIntervalMs: _parseIntField(
          'eventPublishIntervalMs',
          'Khoảng cách phát sự kiện (ms)',
        ),
        minRealtimeFrameQuality: _parseDoubleField(
          'minRealtimeFrameQuality',
          'Chất lượng khung hình tối thiểu thời gian thực',
        ),
        minRealtimeFaceAreaRatio: _parseDoubleField(
          'minRealtimeFaceAreaRatio',
          'Tỷ lệ diện tích mặt tối thiểu thời gian thực',
        ),
        minRealtimeFacePixels: _parseIntField(
          'minRealtimeFacePixels',
          'Số pixel mặt tối thiểu thời gian thực',
        ),
        realtimePartialMinFrameQuality: _parseDoubleField(
          'realtimePartialMinFrameQuality',
          'Vùng cục bộ thời gian thực: ngưỡng chất lượng tối thiểu',
        ),
        realtimePartialMinFaceAreaRatio: _parseDoubleField(
          'realtimePartialMinFaceAreaRatio',
          'Vùng cục bộ thời gian thực: tỷ lệ diện tích mặt tối thiểu',
        ),
        realtimePartialMinFacePixels: _parseIntField(
          'realtimePartialMinFacePixels',
          'Vùng cục bộ thời gian thực: số pixel mặt tối thiểu',
        ),
        realtimePartialMode: _parseIntField(
          'realtimePartialMode',
          'Vùng cục bộ thời gian thực: chế độ',
        ),
        realtimePartialEnabledRegions: _realtimePartialEnabledRegions.join(','),
        realtimePartialFrameCycle: _parseIntField(
          'realtimePartialFrameCycle',
          'Vùng cục bộ thời gian thực: chu kỳ khung hình',
        ),
        minEnrollmentFaceAreaRatio: _parseDoubleField(
          'minEnrollmentFaceAreaRatio',
          'Tỷ lệ diện tích mặt tối thiểu khi đăng ký',
        ),
        maxEnrollmentFaceAreaRatio: _parseDoubleField(
          'maxEnrollmentFaceAreaRatio',
          'Tỷ lệ diện tích mặt tối đa khi đăng ký',
        ),
        minEnrollmentFaceAspectRatio: _parseDoubleField(
          'minEnrollmentFaceAspectRatio',
          'Tỷ lệ khung mặt tối thiểu khi đăng ký',
        ),
        maxEnrollmentFaceAspectRatio: _parseDoubleField(
          'maxEnrollmentFaceAspectRatio',
          'Tỷ lệ khung mặt tối đa khi đăng ký',
        ),
        minEnrollmentFacePixels: _parseIntField(
          'minEnrollmentFacePixels',
          'Số pixel mặt tối thiểu khi đăng ký',
        ),
        scrfdInputSize: _parseIntField(
          'scrfdInputSize',
          'Kích thước input SCRFD',
        ),
        scrfdScoreThreshold: _parseDoubleField(
          'scrfdScoreThreshold',
          'Ngưỡng điểm phát hiện SCRFD',
        ),
        scrfdNmsThreshold: _parseDoubleField(
          'scrfdNmsThreshold',
          'Ngưỡng NMS SCRFD',
        ),
        hnswM: _parseIntField('hnswM', 'HNSW M'),
        hnswEfConstruction: _parseIntField(
          'hnswEfConstruction',
          'HNSW efConstruction',
        ),
        hnswEfSearch: _parseIntField('hnswEfSearch', 'HNSW efSearch'),
        eyeRegionMinQuality: _parseDoubleField(
          'eyeRegionMinQuality',
          'Ngưỡng chất lượng vùng mắt',
        ),
        noseRegionMinQuality: _parseDoubleField(
          'noseRegionMinQuality',
          'Ngưỡng chất lượng vùng mũi',
        ),
        mouthRegionMinQuality: _parseDoubleField(
          'mouthRegionMinQuality',
          'Ngưỡng chất lượng vùng miệng',
        ),
        enableRealtimeAutoSharpen: _enableRealtimeAutoSharpen,
        debugRealtimeOverlay: _debugRealtimeOverlay,
        enableTraceLogs: _enableTraceLogs,
        enablePerfLogs: _enablePerfLogs,
        realtimeCropFacesFromCameraImage: _realtimeCropFacesFromCameraImage,
        autoTuneMaxSharpenAmount: _parseDoubleField(
          'autoTuneMaxSharpenAmount',
          'Mức làm sắc nét tự động tối đa',
        ),
      );

      setState(() {
        _matchThreshold = config.knownMatchThreshold;
      });
      onStateChanged?.call();

      await RecognitionSettingsRepository.saveConfig(config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              context,
              'Đã lưu tham số và áp dụng ngay vào luồng nhận diện.',
              'Parameters were saved and applied immediately to recognition flow.',
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              context,
              'Không lưu được tham số: $e',
              'Failed to save parameters: $e',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingConfig = false;
        });
        onStateChanged?.call();
      }
    }
  }

  Future<void> _pickImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (!mounted || picked == null || picked.files.isEmpty) {
      return;
    }

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              context,
              'Không đọc được dữ liệu ảnh.',
              'Cannot read image data.',
            ),
          ),
        ),
      );
      return;
    }

    _setSelectedImage(bytes, file.name);
  }

  Future<void> _onDropFiles(DropDoneDetails details) async {
    if (details.files.isEmpty) return;
    final dropped = details.files.first;

    Uint8List bytes = Uint8List(0);
    try {
      bytes = await dropped.readAsBytes();
      if (bytes.isEmpty && dropped.path.isNotEmpty) {
        bytes = await File(dropped.path).readAsBytes();
      }
    } catch (_) {
      if (dropped.path.isNotEmpty) {
        try {
          bytes = await File(dropped.path).readAsBytes();
        } catch (_) {}
      }
    }

    if (!mounted) return;
    if (bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              context,
              'Không đọc được ảnh từ file kéo thả.',
              'Cannot read image from dropped file.',
            ),
          ),
        ),
      );
      return;
    }

    final name = dropped.name.isNotEmpty
        ? dropped.name
        : (dropped.path.isNotEmpty
              ? dropped.path.split(RegExp(r'[/\\]')).last
              : 'dropped_image');
    _setSelectedImage(bytes, name);
  }

  void _setSelectedImage(Uint8List bytes, String fileName) {
    setState(() {
      _fileName = fileName;
      _originalImageBytes = bytes;
      _result = null;
    });
  }

  void _clearQuick() {
    setState(() {
      _fileName = null;
      _originalImageBytes = null;
      _result = null;
      _isDraggingUpload = false;
    });
  }

  Future<void> _runTest() async {
    if (_originalImageBytes == null || _originalImageBytes!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              context,
              'Vui lòng chọn hoặc kéo thả ảnh trước.',
              'Please pick or drop an image first.',
            ),
          ),
        ),
      );
      return;
    }
    if (_selectedPersonIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              context,
              'Vui lòng chọn danh sách đối tượng.',
              'Please select people for testing.',
            ),
          ),
        ),
      );
      return;
    }

    final selectedPeople = _people
        .where((p) => _selectedPersonIds.contains(p.id))
        .toList(growable: false);

    setState(() {
      _isRunning = true;
      _result = null;
    });

    try {
      final result = await _service
          .analyzeUploadedImage(
            imageBytes: _originalImageBytes!,
            selectedPeople: selectedPeople,
            matchThreshold: _matchThreshold,
            compareAgainstWholeGallery: false,
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _result = _buildSyntheticFailedResult(
          _l(
            context,
            'Kiểm tra quá 30s chưa xong. Có thể model đang treo hoặc ảnh quá nặng.',
            'Test exceeded 30s. The model may be stalled or image is too heavy.',
          ),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l(context, 'Kiểm tra bị timeout.', 'Test timed out.')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = _buildSyntheticFailedResult(
          _l(
            context,
            'Lỗi khi chạy kiểm tra: $e',
            'Error while running test: $e',
          ),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(context, 'Kiểm tra thất bại: $e', 'Test failed: $e'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  UploadedImageRecognitionResult _buildSyntheticFailedResult(String message) {
    return UploadedImageRecognitionResult(
      pass: false,
      message: message,
      annotatedImageBytes: _originalImageBytes ?? Uint8List(0),
      matches: const <UploadedImageRecognitionFaceMatch>[],
      faceDebugInfos: const <UploadedImageRecognitionFaceDebugInfo>[],
      recognizedPersonIds: <String>{},
      missingPersonIds: _selectedPersonIds.toList(growable: false),
      matchThreshold: _matchThreshold,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _l(
            context,
            'Kiểm thử nhận diện từ ảnh tải lên',
            'Image upload recognition test',
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1100;
            if (!wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMainContent(context),
                    const SizedBox(height: 16),
                    _buildRightSelectionPanel(context),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildMainContent(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 360,
                    child: _buildRightSelectionPanel(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopRegion(context),
        const SizedBox(height: 12),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _isRunning ? null : _runTest,
                icon: _isRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_circle_fill),
                label: Text(
                  _isRunning
                      ? _l(context, 'Đang kiểm tra...', 'Running...')
                      : _l(context, 'Kiểm tra', 'Run test'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _showRecognitionConfigDialog,
                icon: const Icon(Icons.tune),
                label: Text(_l(context, 'Cấu hình', 'Settings')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _isRunning ? null : _clearQuick,
                icon: const Icon(Icons.clear),
                label: Text(_l(context, 'Xóa nhanh', 'Quick clear')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildBottomRegion(context),
      ],
    );
  }

  Widget _buildTopRegion(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildImagePanel(
            context,
            title: _l(context, 'Ảnh gốc', 'Original image'),
            bytes: _originalImageBytes,
            enableDrop: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildImagePanel(
            context,
            title: _l(context, 'Ảnh kết quả (bbox)', 'Result image (bbox)'),
            bytes: _result?.annotatedImageBytes,
            enableDrop: false,
          ),
        ),
      ],
    );
  }

  Widget _buildImagePanel(
    BuildContext context, {
    required String title,
    required Uint8List? bytes,
    required bool enableDrop,
  }) {
    final isDropActive = _isDraggingUpload && enableDrop;
    final borderColor = isDropActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).dividerColor;

    final imageArea = AnimatedScale(
      scale: isDropActive ? 1.01 : 1.0,
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: isDropActive ? 3 : 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isDropActive
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.24),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              fit: StackFit.expand,
              children: [
                bytes != null && bytes.isNotEmpty
                    ? Image.memory(bytes, fit: BoxFit.contain)
                    : _buildUploadHint(enableDrop),
                if (isDropActive)
                  AnimatedOpacity(
                    opacity: isDropActive ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08),
                      alignment: Alignment.center,
                      child: Text(
                        _l(
                          context,
                          'Thả tệp để tải lên',
                          'Drop file to upload',
                        ),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (enableDrop)
              DropTarget(
                onDragEntered: (_) {
                  setState(() {
                    _isDraggingUpload = true;
                  });
                },
                onDragExited: (_) {
                  setState(() {
                    _isDraggingUpload = false;
                  });
                },
                onDragDone: (details) async {
                  setState(() {
                    _isDraggingUpload = false;
                  });
                  await _onDropFiles(details);
                },
                child: InkWell(onTap: _pickImage, child: imageArea),
              )
            else
              imageArea,
            if (enableDrop) ...[
              const SizedBox(height: 8),
              Text(
                _fileName == null
                    ? _l(context, 'Chưa chọn ảnh', 'No image selected')
                    : _l(context, 'Tệp: $_fileName', 'File: $_fileName'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUploadHint(bool enableDrop) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enableDrop ? Icons.upload_file : Icons.image_not_supported,
                size: 42,
              ),
              const SizedBox(height: 8),
              Text(
                enableDrop
                    ? _l(
                        context,
                        'Kéo thả ảnh vào đây\nhoặc bấm để chọn tệp',
                        'Drag and drop image here\nor click to select a file',
                      )
                    : _l(
                        context,
                        'Chưa có kết quả nhận diện',
                        'No recognition result yet',
                      ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomRegion(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _l(context, 'Thông tin chi tiết kết quả', 'Result details'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildThresholdRow(context),
            const SizedBox(height: 8),
            _buildResultSummary(context),
            const SizedBox(height: 12),
            Text(
              _l(context, 'Danh sách khuôn mặt phát hiện', 'Detected faces'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _buildFaceListTwoColumns(context),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _l(
            context,
            'Ngưỡng so khớp: ${_matchThreshold.toStringAsFixed(2)}',
            'Match threshold: ${_matchThreshold.toStringAsFixed(2)}',
          ),
        ),
        Slider(
          value: _matchThreshold,
          min: 0,
          max: 1,
          divisions: 100,
          label: _matchThreshold.toStringAsFixed(2),
          onChanged: _isRunning
              ? null
              : (value) {
                  setState(() {
                    _matchThreshold = value;
                    _configControllers['knownMatchThreshold']!.text = value
                        .toStringAsFixed(2);
                  });
                },
        ),
      ],
    );
  }

  Widget _buildResultSummary(BuildContext context) {
    final result = _result;
    if (result == null) {
      return Text(
        _l(
          context,
          'Chưa có kết quả. Bấm Kiểm tra để chạy nhận diện.',
          'No results yet. Press Run test to start recognition.',
        ),
      );
    }

    final missingPeople = _people
        .where((p) => result.missingPersonIds.contains(p.id))
        .map((p) => p.name)
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: result.pass
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.pass
                ? _l(context, 'ĐẠT', 'PASS')
                : _l(context, 'KHÔNG ĐẠT', 'FAILED'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(result.message),
          const SizedBox(height: 6),
          Text(
            _l(
              context,
              'Số khuôn mặt phát hiện: ${result.matches.length}',
              'Detected faces: ${result.matches.length}',
            ),
          ),
          Text(
            _l(
              context,
              'Số đối tượng nhận diện được: ${result.recognizedPersonIds.length}',
              'Recognized people: ${result.recognizedPersonIds.length}',
            ),
          ),
          if (missingPeople.isNotEmpty)
            Text(
              _l(
                context,
                'Còn thiếu: ${missingPeople.join(', ')}',
                'Missing: ${missingPeople.join(', ')}',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFaceListTwoColumns(BuildContext context) {
    final result = _result;
    if (result == null || result.faceDebugInfos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          _l(
            context,
            'Chưa có danh sách khuôn mặt phát hiện.',
            'No detected face list yet.',
          ),
        ),
      );
    }

    return Column(
      children: result.faceDebugInfos
          .map((face) {
            final top1 = face.topCandidates.isEmpty
                ? _l(context, 'Không có', 'None')
                : face.topCandidates.first.personName;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showFaceZoomDialog(face),
                child: Ink(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _l(
                          context,
                          'Khuôn mặt #${face.faceIndex + 1} | điểm phát hiện=${face.detectorScore.toStringAsFixed(3)} | ứng viên đầu=$top1',
                          'Face #${face.faceIndex + 1} | detection=${face.detectorScore.toStringAsFixed(3)} | top candidate=$top1',
                        ),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildFaceColImage(
                              context,
                              title: _l(
                                context,
                                'Khuôn mặt gốc',
                                'Original face',
                              ),
                              bytes: face.originalFaceBytes,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildFaceColImage(
                              context,
                              title: _l(
                                context,
                                'Khuôn mặt đã xử lý',
                                'Processed face',
                              ),
                              bytes: face.cleanedFaceBytes,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _l(
                          context,
                          'khung=(${face.rect.left.toStringAsFixed(1)}, ${face.rect.top.toStringAsFixed(1)}, ${face.rect.width.toStringAsFixed(1)}, ${face.rect.height.toStringAsFixed(1)}) | pixel=${face.minFacePixels} | chiều dài vector=${face.vector.length}',
                          'rect=(${face.rect.left.toStringAsFixed(1)}, ${face.rect.top.toStringAsFixed(1)}, ${face.rect.width.toStringAsFixed(1)}, ${face.rect.height.toStringAsFixed(1)}) | pixels=${face.minFacePixels} | vector length=${face.vector.length}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _l(
                          context,
                          'Bấm để phóng to cặp ảnh khuôn mặt',
                          'Click to zoom the face image pair',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Future<void> _showFaceZoomDialog(
    UploadedImageRecognitionFaceDebugInfo face,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _l(
                            dialogContext,
                            'Khuôn mặt #${face.faceIndex + 1} - Phóng to',
                            'Face #${face.faceIndex + 1} - Zoom',
                          ),
                          style: Theme.of(dialogContext).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildZoomPanel(
                            dialogContext,
                            title: _l(
                              dialogContext,
                              'Khuôn mặt gốc',
                              'Original face',
                            ),
                            bytes: face.originalFaceBytes,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildZoomPanel(
                            dialogContext,
                            title: _l(
                              dialogContext,
                              'Khuôn mặt đã xử lý',
                              'Processed face',
                            ),
                            bytes: face.cleanedFaceBytes,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildZoomPanel(
    BuildContext context, {
    required String title,
    required Uint8List bytes,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFaceColImage(
    BuildContext context, {
    required String title,
    required Uint8List bytes,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRightSelectionPanel(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.hasBoundedHeight;
        final allSelected =
            _people.isNotEmpty && _selectedPersonIds.length == _people.length;

        Widget peopleList() {
          final listView = ListView.builder(
            shrinkWrap: !hasBoundedHeight,
            itemCount: _people.length,
            itemBuilder: (context, index) {
              final person = _people[index];
              final selected = _selectedPersonIds.contains(person.id);
              return Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: selected,
                  title: Text(person.name),
                  subtitle: person.employeeCode.trim().isEmpty
                      ? null
                      : Text(
                          _l(
                            context,
                            'Mã NV: ${person.employeeCode}',
                            'Employee code: ${person.employeeCode}',
                          ),
                        ),
                  onChanged: (nextValue) {
                    setState(() {
                      if (nextValue == true) {
                        _selectedPersonIds.add(person.id);
                      } else {
                        _selectedPersonIds.remove(person.id);
                      }
                    });
                  },
                ),
              );
            },
          );

          if (hasBoundedHeight) {
            return Expanded(child: listView);
          }
          return SizedBox(height: 420, child: listView);
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _l(context, 'Danh sách đối tượng', 'People list'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _l(context, 'Chọn danh sách kiểm thử', 'Select test list'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _l(context, 'Chọn tất cả đối tượng', 'Select all people'),
                    ),
                    subtitle: Text(
                      _l(
                        context,
                        'Bật để tự động chọn toàn bộ danh sách hiện có.',
                        'Enable to automatically select everyone in the list.',
                      ),
                    ),
                    value: allSelected,
                    onChanged: _people.isEmpty
                        ? null
                        : (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedPersonIds
                                  ..clear()
                                  ..addAll(_people.map((p) => p.id));
                              } else {
                                _selectedPersonIds.clear();
                              }
                            });
                          },
                  ),
                ),
                const SizedBox(height: 12),
                if (_people.isEmpty)
                  Text(
                    _l(
                      context,
                      'Danh sách người trong hệ thống đang trống.',
                      'People list is empty.',
                    ),
                  )
                else
                  peopleList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRecognitionConfigDialog() async {
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: _l(context, 'Cấu hình nhận diện', 'Recognition settings'),
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Material(
          type: MaterialType.transparency,
          child: StatefulBuilder(
            builder: (dialogContext, dialogSetState) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => Navigator.of(dialogContext).pop(),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0, -0.08),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          ),
                          child: Container(
                            width: math.min(
                              MediaQuery.of(dialogContext).size.width - 24,
                              1220.0,
                            ),
                            margin: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.90),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.14),
                                  blurRadius: 36,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 18,
                                  sigmaY: 18,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    18,
                                    20,
                                    20,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _l(
                                                    dialogContext,
                                                    'Tham số nhận diện thời gian thực',
                                                    'Realtime recognition parameters',
                                                  ),
                                                  style: Theme.of(dialogContext)
                                                      .textTheme
                                                      .titleLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _l(
                                                    dialogContext,
                                                    'Bảng này lưu tham số vào RecognitionSettingsRepository và áp dụng ngay vào luồng nhận diện đang chạy.',
                                                    'This panel saves parameters to RecognitionSettingsRepository and applies them immediately to the running recognition pipeline.',
                                                  ),
                                                  style: Theme.of(
                                                    dialogContext,
                                                  ).textTheme.bodyMedium,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          IconButton.filledTonal(
                                            onPressed: () => Navigator.of(
                                              dialogContext,
                                            ).pop(),
                                            icon: const Icon(Icons.close),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.52,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: Text(
                                          _l(
                                            dialogContext,
                                            'Thanh trượt ngưỡng so khớp trong màn kiểm thử ảnh chỉ tác động cho bài kiểm thử hiện tại, không ghi đè lên cấu hình thời gian thực.',
                                            'The match-threshold slider in this screen only affects the current image test and does not override realtime configuration.',
                                          ),
                                          style: Theme.of(
                                            dialogContext,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Flexible(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight:
                                                MediaQuery.of(
                                                  dialogContext,
                                                ).size.height *
                                                0.76,
                                          ),
                                          child: _isLoadingConfig
                                              ? const Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                )
                                              : SingleChildScrollView(
                                                  child: Column(
                                                    children: _configSections
                                                        .map(
                                                          (
                                                            section,
                                                          ) => _buildConfigSection(
                                                            dialogContext,
                                                            section,
                                                            onStateChanged: () =>
                                                                dialogSetState(
                                                                  () {},
                                                                ),
                                                          ),
                                                        )
                                                        .toList(
                                                          growable: false,
                                                        ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          OutlinedButton(
                                            onPressed: () => Navigator.of(
                                              dialogContext,
                                            ).pop(),
                                            child: Text(
                                              _l(
                                                dialogContext,
                                                'Đóng',
                                                'Close',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          FilledButton.icon(
                                            onPressed:
                                                _isApplyingConfig ||
                                                    _isLoadingConfig
                                                ? null
                                                : () => _applyRecognitionConfig(
                                                    onStateChanged: () =>
                                                        dialogSetState(() {}),
                                                  ),
                                            icon: _isApplyingConfig
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Icon(Icons.save),
                                            label: Text(
                                              _isApplyingConfig
                                                  ? _l(
                                                      dialogContext,
                                                      'Đang áp dụng...',
                                                      'Applying...',
                                                    )
                                                  : _l(
                                                      dialogContext,
                                                      'Áp dụng và lưu',
                                                      'Apply and save',
                                                    ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return child;
      },
    );
  }

  Widget _buildConfigSection(
    BuildContext context,
    _RecognitionSectionDef section, {
    VoidCallback? onStateChanged,
  }) {
    final isExpanded = _expandedConfigSections.contains(section.title);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.28)
              : Theme.of(context).dividerColor.withValues(alpha: 0.24),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: isExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedConfigSections.add(section.title);
              } else {
                _expandedConfigSections.remove(section.title);
              }
            });
            onStateChanged?.call();
          },
          title: Row(
            children: [
              Icon(
                _sectionIcon(section.title),
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _sectionTitleText(context, section.title),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (section.fields.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${section.fields.length}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final int fieldColumns = width >= 980
                    ? 3
                    : width >= 640
                    ? 2
                    : 1;
                final int switchColumns = width >= 920 ? 2 : 1;

                return Column(
                  children: [
                    if (section.fields.isNotEmpty)
                      GridView.builder(
                        itemCount: section.fields.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: fieldColumns,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 94,
                        ),
                        itemBuilder: (context, index) {
                          final field = section.fields[index];
                          return _buildConfigFieldTile(context, field);
                        },
                      ),
                    if (section.switchKeys.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      GridView.builder(
                        itemCount: section.switchKeys.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: switchColumns,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 72,
                        ),
                        itemBuilder: (context, index) => _buildConfigSwitch(
                          section.switchKeys[index],
                          onStateChanged: onStateChanged,
                        ),
                      ),
                    ],
                    if (section.title == 'Chất lượng thời gian thực') ...[
                      const SizedBox(height: 10),
                      _buildPartialRegionSelector(
                        onStateChanged: onStateChanged,
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _sectionIcon(String title) {
    switch (title) {
      case 'Ngưỡng nhận diện':
        return Icons.verified_user;
      case 'Realtime pipeline':
      case 'Luồng xử lý thời gian thực':
        return Icons.speed;
      case 'Theo dõi ByteTrack':
        return Icons.track_changes;
      case 'Chất lượng thời gian thực':
        return Icons.high_quality;
      case 'Đăng ký khuôn mặt':
        return Icons.badge;
      case 'Phát hiện và tìm kiếm':
        return Icons.radar;
      case 'Xử lý đầu vào và gỡ lỗi':
        return Icons.tune;
      default:
        return Icons.settings;
    }
  }

  Widget _buildConfigFieldTile(
    BuildContext context,
    _RecognitionFieldDef field,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _fieldLabelText(context, field.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Expanded(child: _buildConfigTextField(field)),
        ],
      ),
    );
  }

  Widget _buildPartialRegionSelector({VoidCallback? onStateChanged}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _l(
              context,
              'Vùng cục bộ thời gian thực: chọn vùng sử dụng',
              'Realtime partial: select enabled regions',
            ),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 3 : 2;
              final entries = _partialRegionLabels.entries.toList(
                growable: false,
              );
              return GridView.builder(
                itemCount: entries.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 44,
                ),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final selected = _realtimePartialEnabledRegions.contains(
                    entry.key,
                  );
                  return Material(
                    color: Colors.transparent,
                    child: CheckboxListTile(
                      dense: true,
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(_regionLabelText(context, entry.value)),
                      value: selected,
                      onChanged: (next) {
                        if (next == null) {
                          return;
                        }
                        if (!next &&
                            _realtimePartialEnabledRegions.length <= 1) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _l(
                                  context,
                                  'Cần giữ lại ít nhất 1 vùng cục bộ',
                                  'At least one partial region must remain selected',
                                ),
                              ),
                            ),
                          );
                          return;
                        }
                        setState(() {
                          if (next) {
                            _realtimePartialEnabledRegions.add(entry.key);
                          } else {
                            _realtimePartialEnabledRegions.remove(entry.key);
                          }
                        });
                        onStateChanged?.call();
                      },
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            _l(
              context,
              'Đã chọn ${_realtimePartialEnabledRegions.length}/${_partialRegionLabels.length} vùng',
              'Selected ${_realtimePartialEnabledRegions.length}/${_partialRegionLabels.length} regions',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildConfigTextField(_RecognitionFieldDef field) {
    return TextField(
      controller: _configControllers[field.key],
      keyboardType: TextInputType.numberWithOptions(decimal: !field.isInt),
      decoration: InputDecoration(
        hintText: field.isInt
            ? _l(context, 'Nhập số nguyên', 'Enter an integer')
            : _l(context, 'Nhập số thập phân', 'Enter a decimal number'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.52),
          ),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.86),
      ),
    );
  }

  Widget _buildConfigSwitch(String key, {VoidCallback? onStateChanged}) {
    final value = switch (key) {
      'enableRealtimeAutoSharpen' => _enableRealtimeAutoSharpen,
      'debugRealtimeOverlay' => _debugRealtimeOverlay,
      'enableTraceLogs' => _enableTraceLogs,
      'enablePerfLogs' => _enablePerfLogs,
      'realtimeCropFacesFromCameraImage' => _realtimeCropFacesFromCameraImage,
      _ => false,
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        value: value,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        title: Text(_switchLabelText(context, key)),
        onChanged: (nextValue) {
          setState(() {
            switch (key) {
              case 'enableRealtimeAutoSharpen':
                _enableRealtimeAutoSharpen = nextValue;
                break;
              case 'debugRealtimeOverlay':
                _debugRealtimeOverlay = nextValue;
                break;
              case 'enableTraceLogs':
                _enableTraceLogs = nextValue;
                break;
              case 'enablePerfLogs':
                _enablePerfLogs = nextValue;
                break;
              case 'realtimeCropFacesFromCameraImage':
                _realtimeCropFacesFromCameraImage = nextValue;
                break;
            }
          });
          onStateChanged?.call();
        },
      ),
    );
  }
}
