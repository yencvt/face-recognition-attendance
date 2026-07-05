import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/face_attendance_repository.dart';
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
  static const Map<String, String> _switchLabels = {
    'autoTuneRecognitionParameters': 'Tu dong dieu chinh tham so realtime',
    'debugRealtimeOverlay': 'Bat overlay debug realtime',
    'enableTraceLogs': 'Bat trace log chi tiet realtime',
    'enablePerfLogs': 'Bat perf log do tre',
    'realtimeInputGrayscale': 'Ep anh realtime sang den trang',
  };

  static const List<_RecognitionSectionDef> _configSections = [
    _RecognitionSectionDef(
      title: 'Nguong nhan dien',
      fields: [
        _RecognitionFieldDef(
          key: 'knownMatchThreshold',
          label: 'Nguong khop khuon mat',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'knownStrongThreshold',
          label: 'Nguong khop manh',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'knownCalibratedThreshold',
          label: 'Nguong khop da hieu chinh',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'knownMatchMargin',
          label: 'Bien an toan giua top1 va top2',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'minTemplateSharpness',
          label: 'Do net toi thieu cua mau dang ky',
          isInt: false,
        ),
      ],
    ),
    _RecognitionSectionDef(
      title: 'Realtime pipeline',
      fields: [
        _RecognitionFieldDef(
          key: 'cameraCalibrationDurationMs',
          label: 'Thoi gian hieu chinh camera (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'calibrationLogThrottleMs',
          label: 'Khoang cach log hieu chinh (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'fallbackSkipLogIntervalMs',
          label: 'Khoang cach log bo qua fallback (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'fallbackCaptureIntervalMs',
          label: 'Chu ky chup fallback (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'fallbackMaxInputEdge',
          label: 'Canh toi da anh fallback (px)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'processFrameIntervalMs',
          label: 'Chu ky xu ly frame (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'detectorInputWidth',
          label: 'Chieu rong input detector',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'detectorInputHeight',
          label: 'Chieu cao input detector',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'trackKeepAliveMs',
          label: 'Thoi gian giu track (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'trackMatchMinScore',
          label: 'Diem toi thieu de gan track',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'bboxSmoothingAlpha',
          label: 'He so lam muot bbox',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'annotatedFrameMinIntervalMs',
          label: 'Khoang cach frame overlay toi thieu (ms)',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'eventPublishIntervalMs',
          label: 'Khoang cach phat su kien (ms)',
          isInt: true,
        ),
      ],
    ),
    _RecognitionSectionDef(
      title: 'Chat luong realtime',
      fields: [
        _RecognitionFieldDef(
          key: 'minRealtimeFrameQuality',
          label: 'Chat luong frame toi thieu realtime',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'minRealtimeFaceAreaRatio',
          label: 'Ty le dien tich mat toi thieu realtime',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'minRealtimeFacePixels',
          label: 'So pixel mat toi thieu realtime',
          isInt: true,
        ),
      ],
    ),
    _RecognitionSectionDef(
      title: 'Dang ky khuon mat',
      fields: [
        _RecognitionFieldDef(
          key: 'minEnrollmentFaceAreaRatio',
          label: 'Ty le dien tich mat toi thieu khi dang ky',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'maxEnrollmentFaceAreaRatio',
          label: 'Ty le dien tich mat toi da khi dang ky',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'minEnrollmentFaceAspectRatio',
          label: 'Ty le khung mat toi thieu khi dang ky',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'maxEnrollmentFaceAspectRatio',
          label: 'Ty le khung mat toi da khi dang ky',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'minEnrollmentFacePixels',
          label: 'So pixel mat toi thieu khi dang ky',
          isInt: true,
        ),
      ],
    ),
    _RecognitionSectionDef(
      title: 'Detector va tim kiem',
      fields: [
        _RecognitionFieldDef(
          key: 'scrfdInputSize',
          label: 'Kich thuoc input SCRFD',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'scrfdScoreThreshold',
          label: 'Nguong diem phat hien SCRFD',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'scrfdNmsThreshold',
          label: 'Nguong NMS SCRFD',
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
          label: 'Nguong chat luong vung mat',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'noseRegionMinQuality',
          label: 'Nguong chat luong vung mui',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'mouthRegionMinQuality',
          label: 'Nguong chat luong vung mieng',
          isInt: false,
        ),
      ],
    ),
    _RecognitionSectionDef(
      title: 'Xu ly input va debug',
      fields: [
        _RecognitionFieldDef(
          key: 'realtimeInputBrightness',
          label: 'Do sang input realtime',
          isInt: true,
        ),
        _RecognitionFieldDef(
          key: 'realtimeInputContrast',
          label: 'Tuong phan input realtime',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'realtimeInputGamma',
          label: 'Gamma input realtime',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'realtimeInputSaturation',
          label: 'Bao hoa input realtime',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'autoTuneMaxSharpenAmount',
          label: 'Sharpen toi da cua auto tune',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'autoTuneLowLightThreshold',
          label: 'Nguong low-light',
          isInt: false,
        ),
        _RecognitionFieldDef(
          key: 'autoTuneOverExposureThreshold',
          label: 'Nguong over-exposure',
          isInt: false,
        ),
      ],
      switchKeys: [
        'autoTuneRecognitionParameters',
        'debugRealtimeOverlay',
        'enableTraceLogs',
        'enablePerfLogs',
        'realtimeInputGrayscale',
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
  bool _autoTuneRecognitionParameters = false;
  bool _debugRealtimeOverlay = true;
  bool _enableTraceLogs = false;
  bool _enablePerfLogs = false;
  bool _realtimeInputGrayscale = false;
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
    _configControllers['knownMatchThreshold']!.text = config.knownMatchThreshold
        .toString();
    _configControllers['knownStrongThreshold']!.text = config
        .knownStrongThreshold
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
    _configControllers['detectorInputWidth']!.text = config.detectorInputWidth
        .toString();
    _configControllers['detectorInputHeight']!.text = config.detectorInputHeight
        .toString();
    _configControllers['trackKeepAliveMs']!.text = config.trackKeepAliveMs
        .toString();
    _configControllers['trackMatchMinScore']!.text = config.trackMatchMinScore
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
    _configControllers['realtimeInputBrightness']!.text = config
        .realtimeInputBrightness
        .toString();
    _configControllers['realtimeInputContrast']!.text = config
        .realtimeInputContrast
        .toString();
    _configControllers['realtimeInputGamma']!.text = config.realtimeInputGamma
        .toString();
    _configControllers['realtimeInputSaturation']!.text = config
        .realtimeInputSaturation
        .toString();
    _configControllers['autoTuneMaxSharpenAmount']!.text = config
        .autoTuneMaxSharpenAmount
        .toString();
    _configControllers['autoTuneLowLightThreshold']!.text = config
        .autoTuneLowLightThreshold
        .toString();
    _configControllers['autoTuneOverExposureThreshold']!.text = config
        .autoTuneOverExposureThreshold
        .toString();
    _autoTuneRecognitionParameters = config.autoTuneRecognitionParameters;
    _debugRealtimeOverlay = config.debugRealtimeOverlay;
    _enableTraceLogs = config.enableTraceLogs;
    _enablePerfLogs = config.enablePerfLogs;
    _realtimeInputGrayscale = config.realtimeInputGrayscale;
  }

  int _parseIntField(String key, String label) {
    final value = int.tryParse(_configControllers[key]!.text.trim());
    if (value == null) {
      throw FormatException('Gia tri "$label" khong hop le');
    }
    return value;
  }

  double _parseDoubleField(String key, String label) {
    final value = double.tryParse(_configControllers[key]!.text.trim());
    if (value == null) {
      throw FormatException('Gia tri "$label" khong hop le');
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
          'Nguong khop khuon mat',
        ),
        knownStrongThreshold: _parseDoubleField(
          'knownStrongThreshold',
          'Nguong khop manh',
        ),
        knownCalibratedThreshold: _parseDoubleField(
          'knownCalibratedThreshold',
          'Nguong khop da hieu chinh',
        ),
        knownMatchMargin: _parseDoubleField(
          'knownMatchMargin',
          'Bien an toan giua top1 va top2',
        ),
        minTemplateSharpness: _parseDoubleField(
          'minTemplateSharpness',
          'Do net toi thieu cua mau dang ky',
        ),
        cameraCalibrationDurationMs: _parseIntField(
          'cameraCalibrationDurationMs',
          'Thoi gian hieu chinh camera (ms)',
        ),
        calibrationLogThrottleMs: _parseIntField(
          'calibrationLogThrottleMs',
          'Khoang cach log hieu chinh (ms)',
        ),
        fallbackSkipLogIntervalMs: _parseIntField(
          'fallbackSkipLogIntervalMs',
          'Khoang cach log bo qua fallback (ms)',
        ),
        fallbackCaptureIntervalMs: _parseIntField(
          'fallbackCaptureIntervalMs',
          'Chu ky chup fallback (ms)',
        ),
        fallbackMaxInputEdge: _parseIntField(
          'fallbackMaxInputEdge',
          'Canh toi da anh fallback (px)',
        ),
        processFrameIntervalMs: _parseIntField(
          'processFrameIntervalMs',
          'Chu ky xu ly frame (ms)',
        ),
        detectorInputWidth: _parseIntField(
          'detectorInputWidth',
          'Chieu rong input detector',
        ),
        detectorInputHeight: _parseIntField(
          'detectorInputHeight',
          'Chieu cao input detector',
        ),
        trackKeepAliveMs: _parseIntField(
          'trackKeepAliveMs',
          'Thoi gian giu track (ms)',
        ),
        trackMatchMinScore: _parseDoubleField(
          'trackMatchMinScore',
          'Diem toi thieu de gan track',
        ),
        bboxSmoothingAlpha: _parseDoubleField(
          'bboxSmoothingAlpha',
          'He so lam muot bbox',
        ),
        annotatedFrameMinIntervalMs: _parseIntField(
          'annotatedFrameMinIntervalMs',
          'Khoang cach frame overlay toi thieu (ms)',
        ),
        eventPublishIntervalMs: _parseIntField(
          'eventPublishIntervalMs',
          'Khoang cach phat su kien (ms)',
        ),
        minRealtimeFrameQuality: _parseDoubleField(
          'minRealtimeFrameQuality',
          'Chat luong frame toi thieu realtime',
        ),
        minRealtimeFaceAreaRatio: _parseDoubleField(
          'minRealtimeFaceAreaRatio',
          'Ty le dien tich mat toi thieu realtime',
        ),
        minRealtimeFacePixels: _parseIntField(
          'minRealtimeFacePixels',
          'So pixel mat toi thieu realtime',
        ),
        minEnrollmentFaceAreaRatio: _parseDoubleField(
          'minEnrollmentFaceAreaRatio',
          'Ty le dien tich mat toi thieu khi dang ky',
        ),
        maxEnrollmentFaceAreaRatio: _parseDoubleField(
          'maxEnrollmentFaceAreaRatio',
          'Ty le dien tich mat toi da khi dang ky',
        ),
        minEnrollmentFaceAspectRatio: _parseDoubleField(
          'minEnrollmentFaceAspectRatio',
          'Ty le khung mat toi thieu khi dang ky',
        ),
        maxEnrollmentFaceAspectRatio: _parseDoubleField(
          'maxEnrollmentFaceAspectRatio',
          'Ty le khung mat toi da khi dang ky',
        ),
        minEnrollmentFacePixels: _parseIntField(
          'minEnrollmentFacePixels',
          'So pixel mat toi thieu khi dang ky',
        ),
        scrfdInputSize: _parseIntField(
          'scrfdInputSize',
          'Kich thuoc input SCRFD',
        ),
        scrfdScoreThreshold: _parseDoubleField(
          'scrfdScoreThreshold',
          'Nguong diem phat hien SCRFD',
        ),
        scrfdNmsThreshold: _parseDoubleField(
          'scrfdNmsThreshold',
          'Nguong NMS SCRFD',
        ),
        hnswM: _parseIntField('hnswM', 'HNSW M'),
        hnswEfConstruction: _parseIntField(
          'hnswEfConstruction',
          'HNSW efConstruction',
        ),
        hnswEfSearch: _parseIntField('hnswEfSearch', 'HNSW efSearch'),
        eyeRegionMinQuality: _parseDoubleField(
          'eyeRegionMinQuality',
          'Nguong chat luong vung mat',
        ),
        noseRegionMinQuality: _parseDoubleField(
          'noseRegionMinQuality',
          'Nguong chat luong vung mui',
        ),
        mouthRegionMinQuality: _parseDoubleField(
          'mouthRegionMinQuality',
          'Nguong chat luong vung mieng',
        ),
        autoTuneRecognitionParameters: _autoTuneRecognitionParameters,
        debugRealtimeOverlay: _debugRealtimeOverlay,
        enableTraceLogs: _enableTraceLogs,
        enablePerfLogs: _enablePerfLogs,
        realtimeInputBrightness: _parseIntField(
          'realtimeInputBrightness',
          'Do sang input realtime',
        ),
        realtimeInputContrast: _parseDoubleField(
          'realtimeInputContrast',
          'Tuong phan input realtime',
        ),
        realtimeInputGamma: _parseDoubleField(
          'realtimeInputGamma',
          'Gamma input realtime',
        ),
        realtimeInputSaturation: _parseDoubleField(
          'realtimeInputSaturation',
          'Bao hoa input realtime',
        ),
        realtimeInputGrayscale: _realtimeInputGrayscale,
        autoTuneMaxSharpenAmount: _parseDoubleField(
          'autoTuneMaxSharpenAmount',
          'Sharpen toi da cua auto tune',
        ),
        autoTuneLowLightThreshold: _parseDoubleField(
          'autoTuneLowLightThreshold',
          'Nguong low-light',
        ),
        autoTuneOverExposureThreshold: _parseDoubleField(
          'autoTuneOverExposureThreshold',
          'Nguong over-exposure',
        ),
      );

      await RecognitionSettingsRepository.saveConfig(config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Da luu tham so va ap dung ngay vao luong nhan dien.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Khong luu duoc tham so: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _isApplyingConfig = false;
      });
      onStateChanged?.call();
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
        const SnackBar(content: Text('Khong doc duoc du lieu anh.')),
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
        const SnackBar(content: Text('Khong doc duoc anh tu file keo tha.')),
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
        const SnackBar(content: Text('Vui long chon hoac keo tha anh truoc.')),
      );
      return;
    }
    if (_selectedPersonIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui long chon danh sach doi tuong.')),
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
          'Kiem tra qua 30s chua xong. Co the model dang treo hoac anh qua nang.',
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kiem tra bi timeout.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = _buildSyntheticFailedResult('Loi khi chay kiem tra: $e');
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kiem tra that bai: $e')));
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
      appBar: AppBar(title: const Text('Test nhan dien tu anh upload')),
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
                label: Text(_isRunning ? 'Dang kiem tra...' : 'Kiem tra'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _showRecognitionConfigDialog,
                icon: const Icon(Icons.tune),
                label: const Text('Cau hinh'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _isRunning ? null : _clearQuick,
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
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
            title: 'Anh goc',
            bytes: _originalImageBytes,
            enableDrop: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildImagePanel(
            context,
            title: 'Anh ket qua (bbox)',
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
                        'Tha file de upload',
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
                _fileName == null ? 'Chua chon anh' : 'File: $_fileName',
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
                    ? 'Keo tha anh vao day\nhoac click de chon file'
                    : 'Chua co ket qua nhan dien',
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
              'Thong tin chi tiet ket qua',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildThresholdRow(context),
            const SizedBox(height: 8),
            _buildResultSummary(context),
            const SizedBox(height: 12),
            Text(
              'Danh sach face detect',
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
        Text('Match threshold: ${_matchThreshold.toStringAsFixed(2)}'),
        Slider(
          value: _matchThreshold,
          min: 0.30,
          max: 0.90,
          divisions: 60,
          label: _matchThreshold.toStringAsFixed(2),
          onChanged: _isRunning
              ? null
              : (value) {
                  setState(() {
                    _matchThreshold = value;
                  });
                },
        ),
      ],
    );
  }

  Widget _buildResultSummary(BuildContext context) {
    final result = _result;
    if (result == null) {
      return const Text('Chua co ket qua. Bam Kiem tra de chay nhan dien.');
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
            result.pass ? 'PASS' : 'FAILED',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(result.message),
          const SizedBox(height: 6),
          Text('So mat phat hien: ${result.matches.length}'),
          Text(
            'So doi tuong nhan dien duoc: ${result.recognizedPersonIds.length}',
          ),
          if (missingPeople.isNotEmpty)
            Text('Con thieu: ${missingPeople.join(', ')}'),
        ],
      ),
    );
  }

  Widget _buildFaceListTwoColumns(BuildContext context) {
    final result = _result;
    if (result == null || result.faceDebugInfos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Chua co danh sach face detect.'),
      );
    }

    return Column(
      children: result.faceDebugInfos
          .map((face) {
            final top1 = face.topCandidates.isEmpty
                ? 'N/A'
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
                        'Face #${face.faceIndex + 1} | det=${face.detectorScore.toStringAsFixed(3)} | top1=$top1',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildFaceColImage(
                              context,
                              title: 'Face goc',
                              bytes: face.originalFaceBytes,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildFaceColImage(
                              context,
                              title: 'Face da xu ly',
                              bytes: face.cleanedFaceBytes,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'rect=(${face.rect.left.toStringAsFixed(1)}, ${face.rect.top.toStringAsFixed(1)}, ${face.rect.width.toStringAsFixed(1)}, ${face.rect.height.toStringAsFixed(1)}) | '
                        'pixels=${face.minFacePixels} | vector=${face.vector.length}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Click de phong to cap anh face',
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
                          'Face #${face.faceIndex + 1} - Phong to',
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
                            title: 'Face goc',
                            bytes: face.originalFaceBytes,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildZoomPanel(
                            dialogContext,
                            title: 'Face da xu ly',
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

        Widget peopleList() {
          final listView = ListView.builder(
            shrinkWrap: !hasBoundedHeight,
            itemCount: _people.length,
            itemBuilder: (context, index) {
              final person = _people[index];
              final selected = _selectedPersonIds.contains(person.id);
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: selected,
                title: Text(person.name),
                subtitle: person.employeeCode.trim().isEmpty
                    ? null
                    : Text('Ma NV: ${person.employeeCode}'),
                onChanged: (nextValue) {
                  setState(() {
                    if (nextValue == true) {
                      _selectedPersonIds.add(person.id);
                    } else {
                      _selectedPersonIds.remove(person.id);
                    }
                  });
                },
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
                  'Danh sach doi tuong',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_people.isEmpty)
                  const Text('Danh sach nguoi trong he thong dang trong.')
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
      barrierLabel: 'Recognition config',
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
                                                  'Tham so recognition runtime',
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
                                                  'Popup nay luu tham so vao RecognitionSettingsRepository va ap dung ngay vao luong nhan dien dang chay.',
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
                                          'Slider Match threshold trong man test upload van chi tac dong cho bai test anh, khong ghi de len runtime config.',
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
                                            child: const Text('Dong'),
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
                                                  ? 'Dang ap dung...'
                                                  : 'Ap dung va luu',
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: section.fields
                .map(
                  (field) =>
                      SizedBox(width: 260, child: _buildConfigTextField(field)),
                )
                .toList(growable: false),
          ),
          if (section.switchKeys.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: section.switchKeys
                  .map(
                    (key) => SizedBox(
                      width: 320,
                      child: _buildConfigSwitch(
                        key,
                        onStateChanged: onStateChanged,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigTextField(_RecognitionFieldDef field) {
    return TextField(
      controller: _configControllers[field.key],
      keyboardType: TextInputType.numberWithOptions(decimal: !field.isInt),
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.72),
      ),
    );
  }

  Widget _buildConfigSwitch(String key, {VoidCallback? onStateChanged}) {
    final value = switch (key) {
      'autoTuneRecognitionParameters' => _autoTuneRecognitionParameters,
      'debugRealtimeOverlay' => _debugRealtimeOverlay,
      'enableTraceLogs' => _enableTraceLogs,
      'enablePerfLogs' => _enablePerfLogs,
      'realtimeInputGrayscale' => _realtimeInputGrayscale,
      _ => false,
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SwitchListTile(
        value: value,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(_switchLabels[key] ?? key),
        onChanged: (nextValue) {
          setState(() {
            switch (key) {
              case 'autoTuneRecognitionParameters':
                _autoTuneRecognitionParameters = nextValue;
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
              case 'realtimeInputGrayscale':
                _realtimeInputGrayscale = nextValue;
                break;
            }
          });
          onStateChanged?.call();
        },
      ),
    );
  }
}
