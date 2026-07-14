import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../database/report_settings_repository.dart';
import '../database/recognition_settings_repository.dart';
import '../database/settings_repository.dart';
import '../l10n/app_i18n.dart';
import 'image_recognition_test_screen.dart';
import 'people_management_screen.dart';
import 'user_management_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _l(BuildContext context, String vi, String en) {
    return AppI18n.of(context).locale.languageCode == 'en' ? en : vi;
  }

  String _ln(String vi, String en) {
    return AppI18nController.localeNotifier.value.languageCode == 'en'
        ? en
        : vi;
  }

  static const Map<String, String> _recognitionParameterLabels = {
    'knownMatchThreshold': 'Ngưỡng khớp khuôn mặt',
    'knownCalibratedThreshold': 'Ngưỡng khớp đã hiệu chỉnh theo camera',
    'knownMatchMargin': 'Biên an toàn giữa nhất và nhì',
    'minTemplateSharpness': 'Độ nét tối thiểu của mẫu đăng ký',
    'cameraCalibrationDurationMs': 'Thời gian hiệu chỉnh camera (ms)',
    'calibrationLogThrottleMs': 'Khoảng cách log hiệu chỉnh (ms)',
    'fallbackSkipLogIntervalMs': 'Khoảng cách log bỏ qua fallback (ms)',
    'fallbackCaptureIntervalMs': 'Chu kỳ chụp fallback (ms)',
    'fallbackMaxInputEdge': 'Cạnh tối đa ảnh fallback (px)',
    'processFrameIntervalMs': 'Chu kỳ xử lý frame (ms)',
    'faceMeshMaxWorkers': 'Số luồng Face Mesh tối đa',
    'detectorInputWidth': 'Chiều rộng input detector',
    'detectorInputHeight': 'Chiều cao input detector',
    'trackKeepAliveMs': 'Thời gian giữ track (ms)',
    'trackMatchMinScore': 'Điểm tối thiểu để gán track',
    'bboxSmoothingAlpha': 'Hệ số làm mượt khung bbox',
    'annotatedFrameMinIntervalMs': 'Khoảng cách frame overlay tối thiểu (ms)',
    'eventPublishIntervalMs': 'Khoảng cách phát sự kiện (ms)',
    'minRealtimeFrameQuality': 'Chất lượng frame tối thiểu realtime',
    'minRealtimeFaceAreaRatio': 'Tỷ lệ diện tích mặt tối thiểu realtime',
    'minRealtimeFacePixels': 'Số pixel mặt tối thiểu realtime',
    'minEnrollmentFaceAreaRatio': 'Tỷ lệ diện tích mặt tối thiểu khi đăng ký',
    'maxEnrollmentFaceAreaRatio': 'Tỷ lệ diện tích mặt tối đa khi đăng ký',
    'minEnrollmentFaceAspectRatio': 'Tỷ lệ khung mặt tối thiểu khi đăng ký',
    'maxEnrollmentFaceAspectRatio': 'Tỷ lệ khung mặt tối đa khi đăng ký',
    'minEnrollmentFacePixels': 'Số pixel mặt tối thiểu khi đăng ký',
    'scrfdInputSize': 'Kích thước input SCRFD',
    'scrfdScoreThreshold': 'Ngưỡng điểm phát hiện SCRFD',
    'scrfdNmsThreshold': 'Ngưỡng NMS SCRFD',
    'hnswM': 'HNSW M (số cạnh mỗi node)',
    'hnswEfConstruction': 'HNSW efConstruction',
    'hnswEfSearch': 'HNSW efSearch',
    'eyeRegionMinQuality': 'Ngưỡng chất lượng vùng mắt',
    'noseRegionMinQuality': 'Ngưỡng chất lượng vùng mũi',
    'mouthRegionMinQuality': 'Ngưỡng chất lượng vùng miệng',
    'enableRealtimeAutoSharpen': 'Bật auto sharpen realtime',
    'enableTraceLogs': 'Bật trace log chi tiết realtime',
    'enablePerfLogs': 'Bật perf log độ trễ (Perf[...])',
    'autoTuneMaxSharpenAmount': 'enableRealtimeAutoSharpenMaxAmount (0.0..1.0)',
  };

  static const Map<String, String> _recognitionParameterNotes = {
    'knownMatchThreshold':
        'Ngưỡng điểm so khớp tổng quan để chấp nhận danh tính.',
    'knownCalibratedThreshold':
        'Ngưỡng điểm sau hiệu chỉnh theo độ tách biệt giữa các người.',
    'knownMatchMargin':
        'Khoảng cách tối thiểu giữa top1 và top2 để tránh nhầm lẫn.',
    'minTemplateSharpness': 'Độ nét tối thiểu của ảnh mẫu khi tạo vector.',
    'cameraCalibrationDurationMs':
        'Thời gian gom mẫu để hiệu chỉnh threshold theo camera.',
    'calibrationLogThrottleMs': 'Tần suất ghi log trong giai đoạn hiệu chỉnh.',
    'fallbackSkipLogIntervalMs':
        'Khoảng cách log khi bỏ qua frame lỗi fallback.',
    'fallbackCaptureIntervalMs':
        'Khoảng cách giữa 2 lần chụp fallback khi camera không stream được.',
    'fallbackMaxInputEdge':
        'Giới hạn cạnh lớn nhất của frame fallback trước khi xử lý để giảm tải CPU.',
    'processFrameIntervalMs':
        'Khoảng cách xử lý giữa 2 frame, nhỏ hơn thì nhanh hơn nhưng nặng máy.',
    'faceMeshMaxWorkers':
        'Số worker tối đa chạy song song cho luồng Face Mesh detect/crop/ArcFace.',
    'detectorInputWidth':
        'Độ rộng ảnh đưa vào detector; lớn hơn tăng chất lượng nhưng chậm hơn.',
    'detectorInputHeight':
        'Độ cao ảnh đưa vào detector; lớn hơn tăng chất lượng nhưng chậm hơn.',
    'trackKeepAliveMs': 'Thời gian giữ đối tượng theo dõi trước khi reset.',
    'trackMatchMinScore':
        'Điểm tối thiểu để nối bbox hiện tại với track trước đó.',
    'bboxSmoothingAlpha':
        'Hệ số làm mượt bbox, cao thì bám theo nhanh nhưng dễ rung.',
    'annotatedFrameMinIntervalMs':
        'Chu kỳ tối thiểu vẽ overlay debug, giảm để cập nhật nhanh hơn.',
    'eventPublishIntervalMs':
        'Khoảng cách tối thiểu giữa 2 sự kiện cùng đối tượng.',
    'minRealtimeFrameQuality':
        'Ngưỡng chất lượng frame realtime để cho phép nhận diện.',
    'minRealtimeFaceAreaRatio':
        'Tỷ lệ diện tích mặt tối thiểu trên khung hình.',
    'minRealtimeFacePixels':
        'Cạnh ngắn nhất của mặt (pixel) để tránh nhận diện mặt quá nhỏ.',
    'minEnrollmentFaceAreaRatio':
        'Ngưỡng nhỏ nhất cho diện tích mặt khi đăng ký.',
    'maxEnrollmentFaceAreaRatio':
        'Ngưỡng lớn nhất cho diện tích mặt khi đăng ký.',
    'minEnrollmentFaceAspectRatio':
        'Tỷ lệ khung mặt nhỏ nhất cho phép khi đăng ký.',
    'maxEnrollmentFaceAspectRatio':
        'Tỷ lệ khung mặt lớn nhất cho phép khi đăng ký.',
    'minEnrollmentFacePixels':
        'Kích thước cạnh ngắn tối thiểu của mặt khi đăng ký.',
    'scrfdInputSize':
        'Kích thước input model SCRFD, lớn hơn thì tinh hơn nhưng chậm hơn.',
    'scrfdScoreThreshold': 'Ngưỡng điểm detector SCRFD để giữ lại bbox.',
    'scrfdNmsThreshold': 'Ngưỡng NMS SCRFD để loại bbox trùng lặp.',
    'hnswM':
        'Số kết nối tối đa mỗi node trong đồ thị HNSW; lớn hơn thì tìm tốt hơn nhưng tốn RAM hơn.',
    'hnswEfConstruction':
        'Độ rộng tìm kiếm khi xây dựng index HNSW; lớn hơn thì index chặt hơn nhưng build chậm hơn.',
    'hnswEfSearch':
        'Độ rộng tìm kiếm lúc query HNSW; lớn hơn thì chính xác hơn nhưng chậm hơn.',
    'eyeRegionMinQuality':
        'Ngưỡng chất lượng vùng mắt để đưa vào partial embedding.',
    'noseRegionMinQuality':
        'Ngưỡng chất lượng vùng mũi để đưa vào partial embedding.',
    'mouthRegionMinQuality':
        'Ngưỡng chất lượng vùng miệng để đưa vào partial embedding.',
    'enableRealtimeAutoSharpen':
        'Tự động tăng sharpen ảnh realtime theo độ mờ và độ tương phản thấp.',
    'enableTraceLogs':
        'Bật các log DecisionTrace/Match/GateSkip/CalibTop2 để debug. Tắt để giảm lag.',
    'enablePerfLogs':
        'Bật log hiệu năng Perf[ws]/Perf[db]. Tắt để tránh IO log không cần thiết.',
    'autoTuneMaxSharpenAmount':
        'Giới hạn mức sharpen tối đa khi bật enableRealtimeAutoSharpen.',
  };

  late TextEditingController _signalingServerController;
  late TextEditingController _stunServersController;
  late TextEditingController _turnServersController;
  late TextEditingController _turnUsernameController;
  late TextEditingController _turnPasswordController;
  late TextEditingController _iceTransportPolicyController;
  late TextEditingController _knownMatchThresholdController;
  late TextEditingController _knownCalibratedThresholdController;
  late TextEditingController _knownMatchMarginController;
  late TextEditingController _minTemplateSharpnessController;
  late TextEditingController _cameraCalibrationDurationMsController;
  late TextEditingController _calibrationLogThrottleMsController;
  late TextEditingController _fallbackSkipLogIntervalMsController;
  late TextEditingController _fallbackCaptureIntervalMsController;
  late TextEditingController _fallbackMaxInputEdgeController;
  late TextEditingController _processFrameIntervalMsController;
  late TextEditingController _faceMeshMaxWorkersController;
  late TextEditingController _detectorInputWidthController;
  late TextEditingController _detectorInputHeightController;
  late TextEditingController _trackKeepAliveMsController;
  late TextEditingController _trackMatchMinScoreController;
  late TextEditingController _bboxSmoothingAlphaController;
  late TextEditingController _annotatedFrameMinIntervalMsController;
  late TextEditingController _eventPublishIntervalMsController;
  late TextEditingController _minRealtimeFrameQualityController;
  late TextEditingController _minRealtimeFaceAreaRatioController;
  late TextEditingController _minRealtimeFacePixelsController;
  late TextEditingController _minEnrollmentFaceAreaRatioController;
  late TextEditingController _maxEnrollmentFaceAreaRatioController;
  late TextEditingController _minEnrollmentFaceAspectRatioController;
  late TextEditingController _maxEnrollmentFaceAspectRatioController;
  late TextEditingController _minEnrollmentFacePixelsController;
  late TextEditingController _scrfdInputSizeController;
  late TextEditingController _scrfdScoreThresholdController;
  late TextEditingController _scrfdNmsThresholdController;
  late TextEditingController _hnswMController;
  late TextEditingController _hnswEfConstructionController;
  late TextEditingController _hnswEfSearchController;
  late TextEditingController _eyeRegionMinQualityController;
  late TextEditingController _noseRegionMinQualityController;
  late TextEditingController _mouthRegionMinQualityController;
  late TextEditingController _autoTuneMaxSharpenAmountController;
  late TextEditingController _reportExportDirectoryController;
  late TextEditingController _reportExportTimeController;
  late TextEditingController _reportApiHostController;
  late TextEditingController _reportApiPortController;
  late TextEditingController _reportFilePrefixController;
  String _selectedRecognitionPreset = 'strict';
  bool _enableRealtimeAutoSharpen = false;
  bool _enableAudioProcessing = true;
  bool _debugRealtimeOverlay = true;
  bool _enableTraceLogs = false;
  bool _enablePerfLogs = false;
  bool _enableScheduledReportExport = false;
  bool _enablePublicReportApi = true;
  final bool _isRecognitionAdvancedExpanded = false;
  bool _isLoading = true;

  String _recognitionLabel(String key) =>
      _recognitionParameterLabels[key] ?? key;

  String _presetDisplayName(String preset) {
    switch (preset) {
      case 'accuracy':
        return _ln('Accuracy cao', 'High accuracy');
      case 'balanced':
        return _ln('Cân bằng', 'Balanced');
      case 'low-light':
        return _ln('Ánh sáng yếu', 'Low light');
      case 'far-distance':
        return _ln('Ở xa camera', 'Far distance');
      case 'speed':
        return _ln('Tốc độ cao', 'High speed');
      case 'strict':
        return _ln('Chống nhận nhầm', 'Strict anti-mismatch');
      case 'recall':
        return _ln('Ưu tiên không bỏ sót', 'Recall priority');
      default:
        return _ln('Tùy chỉnh', 'Custom');
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadSettings();
  }

  void _initializeControllers() {
    _signalingServerController = TextEditingController();
    _stunServersController = TextEditingController();
    _turnServersController = TextEditingController();
    _turnUsernameController = TextEditingController();
    _turnPasswordController = TextEditingController();
    _iceTransportPolicyController = TextEditingController();
    _knownMatchThresholdController = TextEditingController();
    _knownCalibratedThresholdController = TextEditingController();
    _knownMatchMarginController = TextEditingController();
    _minTemplateSharpnessController = TextEditingController();
    _cameraCalibrationDurationMsController = TextEditingController();
    _calibrationLogThrottleMsController = TextEditingController();
    _fallbackSkipLogIntervalMsController = TextEditingController();
    _fallbackCaptureIntervalMsController = TextEditingController();
    _fallbackMaxInputEdgeController = TextEditingController();
    _processFrameIntervalMsController = TextEditingController();
    _faceMeshMaxWorkersController = TextEditingController();
    _detectorInputWidthController = TextEditingController();
    _detectorInputHeightController = TextEditingController();
    _trackKeepAliveMsController = TextEditingController();
    _trackMatchMinScoreController = TextEditingController();
    _bboxSmoothingAlphaController = TextEditingController();
    _annotatedFrameMinIntervalMsController = TextEditingController();
    _eventPublishIntervalMsController = TextEditingController();
    _minRealtimeFrameQualityController = TextEditingController();
    _minRealtimeFaceAreaRatioController = TextEditingController();
    _minRealtimeFacePixelsController = TextEditingController();
    _minEnrollmentFaceAreaRatioController = TextEditingController();
    _maxEnrollmentFaceAreaRatioController = TextEditingController();
    _minEnrollmentFaceAspectRatioController = TextEditingController();
    _maxEnrollmentFaceAspectRatioController = TextEditingController();
    _minEnrollmentFacePixelsController = TextEditingController();
    _scrfdInputSizeController = TextEditingController();
    _scrfdScoreThresholdController = TextEditingController();
    _scrfdNmsThresholdController = TextEditingController();
    _hnswMController = TextEditingController();
    _hnswEfConstructionController = TextEditingController();
    _hnswEfSearchController = TextEditingController();
    _eyeRegionMinQualityController = TextEditingController();
    _noseRegionMinQualityController = TextEditingController();
    _mouthRegionMinQualityController = TextEditingController();
    _autoTuneMaxSharpenAmountController = TextEditingController();
    _reportExportDirectoryController = TextEditingController();
    _reportExportTimeController = TextEditingController();
    _reportApiHostController = TextEditingController();
    _reportApiPortController = TextEditingController();
    _reportFilePrefixController = TextEditingController();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await SettingsRepository.getOrCreateDefaultSettings();
      final recognitionConfig =
          await RecognitionSettingsRepository.getOrCreateDefaultConfig();
      final reportConfig =
          await ReportSettingsRepository.getOrCreateDefaultConfig();
      if (!mounted) return;
      setState(() {
        _signalingServerController.text = settings.signalingServerUrl;
        _turnUsernameController.text = settings.turnUsername;
        _turnPasswordController.text = settings.turnPassword;
        _iceTransportPolicyController.text = settings.iceTransportPolicy;
        _enableAudioProcessing = settings.enableAudioProcessing;
        _knownMatchThresholdController.text = recognitionConfig
            .knownMatchThreshold
            .toString();
        _knownCalibratedThresholdController.text = recognitionConfig
            .knownCalibratedThreshold
            .toString();
        _knownMatchMarginController.text = recognitionConfig.knownMatchMargin
            .toString();
        _minTemplateSharpnessController.text = recognitionConfig
            .minTemplateSharpness
            .toString();
        _cameraCalibrationDurationMsController.text = recognitionConfig
            .cameraCalibrationDurationMs
            .toString();
        _calibrationLogThrottleMsController.text = recognitionConfig
            .calibrationLogThrottleMs
            .toString();
        _fallbackSkipLogIntervalMsController.text = recognitionConfig
            .fallbackSkipLogIntervalMs
            .toString();
        _fallbackCaptureIntervalMsController.text = recognitionConfig
            .fallbackCaptureIntervalMs
            .toString();
        _fallbackMaxInputEdgeController.text = recognitionConfig
            .fallbackMaxInputEdge
            .toString();
        _processFrameIntervalMsController.text = recognitionConfig
            .processFrameIntervalMs
            .toString();
        _faceMeshMaxWorkersController.text = recognitionConfig
            .faceMeshMaxWorkers
            .toString();
        _detectorInputWidthController.text = recognitionConfig
            .detectorInputWidth
            .toString();
        _detectorInputHeightController.text = recognitionConfig
            .detectorInputHeight
            .toString();
        _trackKeepAliveMsController.text = recognitionConfig.trackKeepAliveMs
            .toString();
        _trackMatchMinScoreController.text = recognitionConfig
            .trackMatchMinScore
            .toString();
        _bboxSmoothingAlphaController.text = recognitionConfig
            .bboxSmoothingAlpha
            .toString();
        _annotatedFrameMinIntervalMsController.text = recognitionConfig
            .annotatedFrameMinIntervalMs
            .toString();
        _eventPublishIntervalMsController.text = recognitionConfig
            .eventPublishIntervalMs
            .toString();
        _minRealtimeFrameQualityController.text = recognitionConfig
            .minRealtimeFrameQuality
            .toString();
        _minRealtimeFaceAreaRatioController.text = recognitionConfig
            .minRealtimeFaceAreaRatio
            .toString();
        _minRealtimeFacePixelsController.text = recognitionConfig
            .minRealtimeFacePixels
            .toString();
        _minEnrollmentFaceAreaRatioController.text = recognitionConfig
            .minEnrollmentFaceAreaRatio
            .toString();
        _maxEnrollmentFaceAreaRatioController.text = recognitionConfig
            .maxEnrollmentFaceAreaRatio
            .toString();
        _minEnrollmentFaceAspectRatioController.text = recognitionConfig
            .minEnrollmentFaceAspectRatio
            .toString();
        _maxEnrollmentFaceAspectRatioController.text = recognitionConfig
            .maxEnrollmentFaceAspectRatio
            .toString();
        _minEnrollmentFacePixelsController.text = recognitionConfig
            .minEnrollmentFacePixels
            .toString();
        _scrfdInputSizeController.text = recognitionConfig.scrfdInputSize
            .toString();
        _scrfdScoreThresholdController.text = recognitionConfig
            .scrfdScoreThreshold
            .toString();
        _scrfdNmsThresholdController.text = recognitionConfig.scrfdNmsThreshold
            .toString();
        _hnswMController.text = recognitionConfig.hnswM.toString();
        _hnswEfConstructionController.text = recognitionConfig
            .hnswEfConstruction
            .toString();
        _hnswEfSearchController.text = recognitionConfig.hnswEfSearch
            .toString();
        _eyeRegionMinQualityController.text = recognitionConfig
            .eyeRegionMinQuality
            .toString();
        _noseRegionMinQualityController.text = recognitionConfig
            .noseRegionMinQuality
            .toString();
        _mouthRegionMinQualityController.text = recognitionConfig
            .mouthRegionMinQuality
            .toString();
        _autoTuneMaxSharpenAmountController.text = recognitionConfig
            .autoTuneMaxSharpenAmount
            .toString();
        _enableRealtimeAutoSharpen =
            recognitionConfig.enableRealtimeAutoSharpen;
        _debugRealtimeOverlay = recognitionConfig.debugRealtimeOverlay;
        _enableTraceLogs = recognitionConfig.enableTraceLogs;
        _enablePerfLogs = recognitionConfig.enablePerfLogs;
        _reportExportDirectoryController.text =
            reportConfig.scheduledExportDirectory;
        _reportExportTimeController.text = reportConfig.scheduledExportTime;
        _reportApiHostController.text = reportConfig.apiHost;
        _reportApiPortController.text = reportConfig.apiPort.toString();
        _reportFilePrefixController.text = reportConfig.filePrefix;
        _enableScheduledReportExport = reportConfig.scheduledExportEnabled;
        _enablePublicReportApi = reportConfig.apiEnabled;
        _selectedRecognitionPreset = _recognitionPresetForConfig(
          recognitionConfig,
        );

        try {
          final stunList = jsonDecode(settings.stunServers) as List<dynamic>;
          _stunServersController.text = stunList.cast<String>().join('\n');
        } catch (_) {
          _stunServersController.text = settings.stunServers;
        }

        try {
          final turnList = jsonDecode(settings.turnServers) as List<dynamic>;
          _turnServersController.text = turnList.cast<String>().join('\n');
        } catch (_) {
          _turnServersController.text = settings.turnServers;
        }

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(context, 'Lỗi tải cấu hình: $e', 'Failed to load settings: $e'),
          ),
        ),
      );
    }
  }

  Future<void> _saveSettings() async {
    try {
      double parseDouble(TextEditingController controller, String label) {
        final value = double.tryParse(controller.text.trim());
        if (value == null) {
          throw FormatException(
            'Giá trị "${_recognitionLabel(label)}" không hợp lệ',
          );
        }
        return value;
      }

      int parseInt(TextEditingController controller, String label) {
        final value = int.tryParse(controller.text.trim());
        if (value == null) {
          throw FormatException(
            'Giá trị "${_recognitionLabel(label)}" không hợp lệ',
          );
        }
        return value;
      }

      final stunList = _stunServersController.text
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();

      final turnList = _turnServersController.text
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();

      final signalingUrl = _signalingServerController.text.trim();
      if (signalingUrl.isEmpty) {
        _showErrorSnackBar(
          _ln(
            'Vui lòng nhập URL máy chủ Signaling',
            'Please enter the Signaling server URL',
          ),
        );
        return;
      }

      if (stunList.isEmpty && turnList.isEmpty) {
        _showErrorSnackBar(
          _ln(
            'Vui lòng nhập ít nhất một STUN hoặc TURN server',
            'Please provide at least one STUN or TURN server',
          ),
        );
        return;
      }

      final settings = WebRTCSettings(
        id: 'default_webrtc_config',
        signalingServerUrl: signalingUrl,
        stunServers: jsonEncode(stunList),
        turnServers: jsonEncode(turnList),
        turnUsername: _turnUsernameController.text.trim(),
        turnPassword: _turnPasswordController.text.trim(),
        iceTransportPolicy: _iceTransportPolicyController.text.trim(),
        enableAudioProcessing: _enableAudioProcessing,
      );

      await SettingsRepository.saveSettings(settings);

      final previousRecognitionConfig =
          await RecognitionSettingsRepository.getOrCreateDefaultConfig();
      final recognitionConfig = previousRecognitionConfig.copyWith(
        knownMatchThreshold: parseDouble(
          _knownMatchThresholdController,
          'knownMatchThreshold',
        ),
        knownCalibratedThreshold: parseDouble(
          _knownCalibratedThresholdController,
          'knownCalibratedThreshold',
        ),
        knownMatchMargin: parseDouble(
          _knownMatchMarginController,
          'knownMatchMargin',
        ),
        minTemplateSharpness: parseDouble(
          _minTemplateSharpnessController,
          'minTemplateSharpness',
        ),
        cameraCalibrationDurationMs: parseInt(
          _cameraCalibrationDurationMsController,
          'cameraCalibrationDurationMs',
        ),
        calibrationLogThrottleMs: parseInt(
          _calibrationLogThrottleMsController,
          'calibrationLogThrottleMs',
        ),
        fallbackSkipLogIntervalMs: parseInt(
          _fallbackSkipLogIntervalMsController,
          'fallbackSkipLogIntervalMs',
        ),
        fallbackCaptureIntervalMs: parseInt(
          _fallbackCaptureIntervalMsController,
          'fallbackCaptureIntervalMs',
        ),
        fallbackMaxInputEdge: parseInt(
          _fallbackMaxInputEdgeController,
          'fallbackMaxInputEdge',
        ),
        processFrameIntervalMs: parseInt(
          _processFrameIntervalMsController,
          'processFrameIntervalMs',
        ),
        faceMeshMaxWorkers: parseInt(
          _faceMeshMaxWorkersController,
          'faceMeshMaxWorkers',
        ),
        detectorInputWidth: parseInt(
          _detectorInputWidthController,
          'detectorInputWidth',
        ),
        detectorInputHeight: parseInt(
          _detectorInputHeightController,
          'detectorInputHeight',
        ),
        trackKeepAliveMs: parseInt(
          _trackKeepAliveMsController,
          'trackKeepAliveMs',
        ),
        trackMatchMinScore: parseDouble(
          _trackMatchMinScoreController,
          'trackMatchMinScore',
        ),
        bboxSmoothingAlpha: parseDouble(
          _bboxSmoothingAlphaController,
          'bboxSmoothingAlpha',
        ),
        annotatedFrameMinIntervalMs: parseInt(
          _annotatedFrameMinIntervalMsController,
          'annotatedFrameMinIntervalMs',
        ),
        eventPublishIntervalMs: parseInt(
          _eventPublishIntervalMsController,
          'eventPublishIntervalMs',
        ),
        minRealtimeFrameQuality: parseDouble(
          _minRealtimeFrameQualityController,
          'minRealtimeFrameQuality',
        ),
        minRealtimeFaceAreaRatio: parseDouble(
          _minRealtimeFaceAreaRatioController,
          'minRealtimeFaceAreaRatio',
        ),
        minRealtimeFacePixels: parseInt(
          _minRealtimeFacePixelsController,
          'minRealtimeFacePixels',
        ),
        minEnrollmentFaceAreaRatio: parseDouble(
          _minEnrollmentFaceAreaRatioController,
          'minEnrollmentFaceAreaRatio',
        ),
        maxEnrollmentFaceAreaRatio: parseDouble(
          _maxEnrollmentFaceAreaRatioController,
          'maxEnrollmentFaceAreaRatio',
        ),
        minEnrollmentFaceAspectRatio: parseDouble(
          _minEnrollmentFaceAspectRatioController,
          'minEnrollmentFaceAspectRatio',
        ),
        maxEnrollmentFaceAspectRatio: parseDouble(
          _maxEnrollmentFaceAspectRatioController,
          'maxEnrollmentFaceAspectRatio',
        ),
        minEnrollmentFacePixels: parseInt(
          _minEnrollmentFacePixelsController,
          'minEnrollmentFacePixels',
        ),
        scrfdInputSize: parseInt(_scrfdInputSizeController, 'scrfdInputSize'),
        scrfdScoreThreshold: parseDouble(
          _scrfdScoreThresholdController,
          'scrfdScoreThreshold',
        ),
        scrfdNmsThreshold: parseDouble(
          _scrfdNmsThresholdController,
          'scrfdNmsThreshold',
        ),
        hnswM: parseInt(_hnswMController, 'hnswM'),
        hnswEfConstruction: parseInt(
          _hnswEfConstructionController,
          'hnswEfConstruction',
        ),
        hnswEfSearch: parseInt(_hnswEfSearchController, 'hnswEfSearch'),
        eyeRegionMinQuality: parseDouble(
          _eyeRegionMinQualityController,
          'eyeRegionMinQuality',
        ),
        noseRegionMinQuality: parseDouble(
          _noseRegionMinQualityController,
          'noseRegionMinQuality',
        ),
        mouthRegionMinQuality: parseDouble(
          _mouthRegionMinQualityController,
          'mouthRegionMinQuality',
        ),
        enableRealtimeAutoSharpen: _enableRealtimeAutoSharpen,
        debugRealtimeOverlay: _debugRealtimeOverlay,
        enableTraceLogs: _enableTraceLogs,
        enablePerfLogs: _enablePerfLogs,
        autoTuneMaxSharpenAmount: parseDouble(
          _autoTuneMaxSharpenAmountController,
          'autoTuneMaxSharpenAmount',
        ),
      );
      await RecognitionSettingsRepository.saveConfig(recognitionConfig);

      final scheduleTime = _reportExportTimeController.text.trim();
      final scheduleParts = scheduleTime.split(':');
      if (scheduleParts.length != 2 ||
          int.tryParse(scheduleParts[0]) == null ||
          int.tryParse(scheduleParts[1]) == null) {
        _showErrorSnackBar(
          _ln(
            'Thời gian chạy job phải theo định dạng HH:mm',
            'Job time must be in HH:mm format',
          ),
        );
        return;
      }

      final scheduleHour = int.parse(scheduleParts[0]);
      final scheduleMinute = int.parse(scheduleParts[1]);
      if (scheduleHour < 0 ||
          scheduleHour > 23 ||
          scheduleMinute < 0 ||
          scheduleMinute > 59) {
        _showErrorSnackBar(
          _ln('Thời gian chạy job không hợp lệ', 'Invalid job time'),
        );
        return;
      }

      final reportApiPort = int.tryParse(_reportApiPortController.text.trim());
      if (reportApiPort == null ||
          reportApiPort <= 0 ||
          reportApiPort > 65535) {
        _showErrorSnackBar(
          _ln(
            'Cổng API báo cáo không hợp lệ (1-65535)',
            'Invalid report API port (1-65535)',
          ),
        );
        return;
      }

      final reportConfig = ReportExportConfig(
        scheduledExportEnabled: _enableScheduledReportExport,
        scheduledExportDirectory: _reportExportDirectoryController.text.trim(),
        scheduledExportTime:
            '${scheduleHour.toString().padLeft(2, '0')}:${scheduleMinute.toString().padLeft(2, '0')}',
        apiEnabled: _enablePublicReportApi,
        apiHost: _reportApiHostController.text.trim().isEmpty
            ? '0.0.0.0'
            : _reportApiHostController.text.trim(),
        apiPort: reportApiPort,
        filePrefix: _reportFilePrefixController.text.trim().isEmpty
            ? 'attendance_report'
            : _reportFilePrefixController.text.trim(),
      );
      await ReportSettingsRepository.saveConfig(reportConfig);

      if (!mounted) return;
      _showSuccessSnackBar(
        _ln(
          'Cấu hình đã được lưu và áp dụng ngay lập tức',
          'Settings have been saved and applied immediately',
        ),
      );
    } catch (e) {
      _showErrorSnackBar(
        _ln('Lỗi lưu cấu hình: $e', 'Failed to save settings: $e'),
      );
    }
  }

  void _setRecognitionControllers(RecognitionRuntimeConfig config) {
    _knownMatchThresholdController.text = config.knownMatchThreshold.toString();
    _knownCalibratedThresholdController.text = config.knownCalibratedThreshold
        .toString();
    _knownMatchMarginController.text = config.knownMatchMargin.toString();
    _minTemplateSharpnessController.text = config.minTemplateSharpness
        .toString();
    _cameraCalibrationDurationMsController.text = config
        .cameraCalibrationDurationMs
        .toString();
    _calibrationLogThrottleMsController.text = config.calibrationLogThrottleMs
        .toString();
    _fallbackSkipLogIntervalMsController.text = config.fallbackSkipLogIntervalMs
        .toString();
    _fallbackCaptureIntervalMsController.text = config.fallbackCaptureIntervalMs
        .toString();
    _fallbackMaxInputEdgeController.text = config.fallbackMaxInputEdge
        .toString();
    _processFrameIntervalMsController.text = config.processFrameIntervalMs
        .toString();
    _faceMeshMaxWorkersController.text = config.faceMeshMaxWorkers.toString();
    _detectorInputWidthController.text = config.detectorInputWidth.toString();
    _detectorInputHeightController.text = config.detectorInputHeight.toString();
    _trackKeepAliveMsController.text = config.trackKeepAliveMs.toString();
    _trackMatchMinScoreController.text = config.trackMatchMinScore.toString();
    _bboxSmoothingAlphaController.text = config.bboxSmoothingAlpha.toString();
    _annotatedFrameMinIntervalMsController.text = config
        .annotatedFrameMinIntervalMs
        .toString();
    _eventPublishIntervalMsController.text = config.eventPublishIntervalMs
        .toString();
    _minRealtimeFrameQualityController.text = config.minRealtimeFrameQuality
        .toString();
    _minRealtimeFaceAreaRatioController.text = config.minRealtimeFaceAreaRatio
        .toString();
    _minRealtimeFacePixelsController.text = config.minRealtimeFacePixels
        .toString();
    _minEnrollmentFaceAreaRatioController.text = config
        .minEnrollmentFaceAreaRatio
        .toString();
    _maxEnrollmentFaceAreaRatioController.text = config
        .maxEnrollmentFaceAreaRatio
        .toString();
    _minEnrollmentFaceAspectRatioController.text = config
        .minEnrollmentFaceAspectRatio
        .toString();
    _maxEnrollmentFaceAspectRatioController.text = config
        .maxEnrollmentFaceAspectRatio
        .toString();
    _minEnrollmentFacePixelsController.text = config.minEnrollmentFacePixels
        .toString();
    _scrfdInputSizeController.text = config.scrfdInputSize.toString();
    _scrfdScoreThresholdController.text = config.scrfdScoreThreshold.toString();
    _scrfdNmsThresholdController.text = config.scrfdNmsThreshold.toString();
    _hnswMController.text = config.hnswM.toString();
    _hnswEfConstructionController.text = config.hnswEfConstruction.toString();
    _hnswEfSearchController.text = config.hnswEfSearch.toString();
    _eyeRegionMinQualityController.text = config.eyeRegionMinQuality.toString();
    _noseRegionMinQualityController.text = config.noseRegionMinQuality
        .toString();
    _mouthRegionMinQualityController.text = config.mouthRegionMinQuality
        .toString();
    _autoTuneMaxSharpenAmountController.text = config.autoTuneMaxSharpenAmount
        .toString();
    _enableRealtimeAutoSharpen = config.enableRealtimeAutoSharpen;
    _debugRealtimeOverlay = config.debugRealtimeOverlay;
    _enableTraceLogs = config.enableTraceLogs;
    _enablePerfLogs = config.enablePerfLogs;
  }

  RecognitionRuntimeConfig _presetAccuracyConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.95,
      knownCalibratedThreshold: 0.92,
      knownMatchMargin: 0.22,
      minTemplateSharpness: 36.0,
      processFrameIntervalMs: 80,
      eventPublishIntervalMs: 70000,
      minRealtimeFrameQuality: 0.28,
      minRealtimeFaceAreaRatio: 0.05,
      minRealtimeFacePixels: 72,
      scrfdScoreThreshold: 0.62,
      scrfdNmsThreshold: 0.34,
      enableRealtimeAutoSharpen: false,
    );
  }

  RecognitionRuntimeConfig _presetBalancedConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.92,
      knownCalibratedThreshold: 0.78,
      knownMatchMargin: 0.18,
      minTemplateSharpness: 28.0,
      processFrameIntervalMs: 50,
      eventPublishIntervalMs: 60000,
      minRealtimeFrameQuality: 0.22,
      minRealtimeFaceAreaRatio: 0.035,
      minRealtimeFacePixels: 56,
      scrfdScoreThreshold: 0.55,
      scrfdNmsThreshold: 0.38,
      hnswM: 20,
      hnswEfConstruction: 144,
      hnswEfSearch: 160,
      eyeRegionMinQuality: 0.24,
      noseRegionMinQuality: 0.22,
      mouthRegionMinQuality: 0.22,
      enableRealtimeAutoSharpen: false,
    );
  }

  RecognitionRuntimeConfig _presetLowLightConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.97,
      knownCalibratedThreshold: 0.95,
      knownMatchMargin: 0.28,
      minTemplateSharpness: 40.0,
      processFrameIntervalMs: 70,
      eventPublishIntervalMs: 90000,
      minRealtimeFrameQuality: 0.33,
      minRealtimeFaceAreaRatio: 0.06,
      minRealtimeFacePixels: 80,
      scrfdInputSize: 640,
      scrfdScoreThreshold: 0.66,
      scrfdNmsThreshold: 0.32,
      hnswM: 24,
      hnswEfConstruction: 200,
      hnswEfSearch: 240,
      eyeRegionMinQuality: 0.32,
      noseRegionMinQuality: 0.30,
      mouthRegionMinQuality: 0.30,
      enableRealtimeAutoSharpen: true,
    );
  }

  RecognitionRuntimeConfig _presetFarDistanceConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.955,
      knownCalibratedThreshold: 0.90,
      knownMatchMargin: 0.20,
      minTemplateSharpness: 32.0,
      processFrameIntervalMs: 60,
      eventPublishIntervalMs: 70000,
      minRealtimeFrameQuality: 0.20,
      minRealtimeFaceAreaRatio: 0.015,
      minRealtimeFacePixels: 30,
      scrfdInputSize: 640,
      scrfdScoreThreshold: 0.50,
      scrfdNmsThreshold: 0.36,
      hnswM: 24,
      hnswEfConstruction: 180,
      hnswEfSearch: 220,
      eyeRegionMinQuality: 0.22,
      noseRegionMinQuality: 0.20,
      mouthRegionMinQuality: 0.20,
      enableRealtimeAutoSharpen: true,
    );
  }

  RecognitionRuntimeConfig _presetSpeedConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.90,
      knownCalibratedThreshold: 0.74,
      knownMatchMargin: 0.15,
      minTemplateSharpness: 24.0,
      processFrameIntervalMs: 34,
      eventPublishIntervalMs: 45000,
      minRealtimeFrameQuality: 0.16,
      minRealtimeFaceAreaRatio: 0.026,
      minRealtimeFacePixels: 44,
      scrfdInputSize: 512,
      scrfdScoreThreshold: 0.47,
      scrfdNmsThreshold: 0.42,
      enableRealtimeAutoSharpen: false,
    );
  }

  RecognitionRuntimeConfig _presetStrictConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.965,
      knownCalibratedThreshold: 0.94,
      knownMatchMargin: 0.26,
      minTemplateSharpness: 38.0,
      processFrameIntervalMs: 70,
      eventPublishIntervalMs: 80000,
      minRealtimeFrameQuality: 0.30,
      minRealtimeFaceAreaRatio: 0.055,
      minRealtimeFacePixels: 76,
      scrfdInputSize: 640,
      scrfdScoreThreshold: 0.64,
      scrfdNmsThreshold: 0.33,
      hnswM: 24,
      hnswEfConstruction: 200,
      hnswEfSearch: 220,
      eyeRegionMinQuality: 0.30,
      noseRegionMinQuality: 0.28,
      mouthRegionMinQuality: 0.28,
      enableRealtimeAutoSharpen: false,
    );
  }

  RecognitionRuntimeConfig _presetRecallConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.90,
      knownCalibratedThreshold: 0.72,
      knownMatchMargin: 0.12,
      minTemplateSharpness: 24.0,
      processFrameIntervalMs: 38,
      eventPublishIntervalMs: 42000,
      minRealtimeFrameQuality: 0.15,
      minRealtimeFaceAreaRatio: 0.024,
      minRealtimeFacePixels: 42,
      scrfdInputSize: 512,
      scrfdScoreThreshold: 0.45,
      scrfdNmsThreshold: 0.44,
      hnswM: 20,
      hnswEfConstruction: 160,
      hnswEfSearch: 220,
      eyeRegionMinQuality: 0.20,
      noseRegionMinQuality: 0.18,
      mouthRegionMinQuality: 0.18,
      enableRealtimeAutoSharpen: false,
    );
  }

  Future<void> _applyRecognitionPreset(String preset) async {
    RecognitionRuntimeConfig config;
    switch (preset) {
      case 'accuracy':
        config = _presetAccuracyConfig();
        break;
      case 'strict':
        config = _presetStrictConfig();
        break;
      case 'recall':
        config = _presetRecallConfig();
        break;
      case 'low-light':
        config = _presetLowLightConfig();
        break;
      case 'far-distance':
        config = _presetFarDistanceConfig();
        break;
      case 'speed':
        config = _presetSpeedConfig();
        break;
      default:
        config = _presetBalancedConfig();
        break;
    }

    setState(() {
      _selectedRecognitionPreset = preset;
      _setRecognitionControllers(config);
    });

    await RecognitionSettingsRepository.saveConfig(config);
    if (!mounted) return;
    _showSuccessSnackBar(
      _ln(
        'Đã áp dụng preset ${_presetDisplayName(preset)}',
        'Applied preset ${_presetDisplayName(preset)}',
      ),
    );
  }

  String _recognitionPresetForConfig(RecognitionRuntimeConfig config) {
    if (config.toJson() == _presetStrictConfig().toJson()) return 'strict';
    if (config.toJson() == _presetLowLightConfig().toJson()) return 'low-light';
    if (config.toJson() == _presetFarDistanceConfig().toJson()) {
      return 'far-distance';
    }
    if (config.toJson() == _presetBalancedConfig().toJson()) return 'balanced';
    if (config.toJson() == _presetAccuracyConfig().toJson()) return 'accuracy';
    if (config.toJson() == _presetSpeedConfig().toJson()) return 'speed';
    if (config.toJson() == _presetRecallConfig().toJson()) return 'recall';
    return 'custom';
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            _l(context, 'Đặt lại cấu hình mặc định', 'Reset default settings'),
          ),
          content: Text(
            _l(
              context,
              'Điều này sẽ đặt lại tất cả các cài đặt WebRTC về giá trị mặc định. Bạn chắc chắn muốn tiếp tục?',
              'This will reset all WebRTC settings to defaults. Are you sure you want to continue?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_l(context, 'Hủy', 'Cancel')),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                final defaults = WebRTCSettings(
                  id: 'default_webrtc_config',
                  signalingServerUrl: 'wss://signaling.example.com',
                  stunServers:
                      '["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]',
                  turnServers: '["turn:turnserver.example.com:3478"]',
                  turnUsername: '',
                  turnPassword: '',
                );
                await SettingsRepository.saveSettings(defaults);
                await RecognitionSettingsRepository.saveConfig(
                  const RecognitionRuntimeConfig(),
                );
                await ReportSettingsRepository.saveConfig(
                  const ReportExportConfig(),
                );
                if (!mounted) return;
                await _loadSettings();
              },
              child: Text(_l(context, 'Đặt lại', 'Reset')),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _signalingServerController.dispose();
    _stunServersController.dispose();
    _turnServersController.dispose();
    _turnUsernameController.dispose();
    _turnPasswordController.dispose();
    _iceTransportPolicyController.dispose();
    _knownMatchThresholdController.dispose();
    _knownCalibratedThresholdController.dispose();
    _knownMatchMarginController.dispose();
    _minTemplateSharpnessController.dispose();
    _cameraCalibrationDurationMsController.dispose();
    _calibrationLogThrottleMsController.dispose();
    _fallbackSkipLogIntervalMsController.dispose();
    _fallbackCaptureIntervalMsController.dispose();
    _fallbackMaxInputEdgeController.dispose();
    _processFrameIntervalMsController.dispose();
    _faceMeshMaxWorkersController.dispose();
    _detectorInputWidthController.dispose();
    _detectorInputHeightController.dispose();
    _trackKeepAliveMsController.dispose();
    _trackMatchMinScoreController.dispose();
    _bboxSmoothingAlphaController.dispose();
    _annotatedFrameMinIntervalMsController.dispose();
    _eventPublishIntervalMsController.dispose();
    _minRealtimeFrameQualityController.dispose();
    _minRealtimeFaceAreaRatioController.dispose();
    _minRealtimeFacePixelsController.dispose();
    _minEnrollmentFaceAreaRatioController.dispose();
    _maxEnrollmentFaceAreaRatioController.dispose();
    _minEnrollmentFaceAspectRatioController.dispose();
    _maxEnrollmentFaceAspectRatioController.dispose();
    _minEnrollmentFacePixelsController.dispose();
    _scrfdInputSizeController.dispose();
    _scrfdScoreThresholdController.dispose();
    _scrfdNmsThresholdController.dispose();
    _hnswMController.dispose();
    _hnswEfConstructionController.dispose();
    _hnswEfSearchController.dispose();
    _eyeRegionMinQualityController.dispose();
    _noseRegionMinQualityController.dispose();
    _mouthRegionMinQualityController.dispose();
    _autoTuneMaxSharpenAmountController.dispose();
    _reportExportDirectoryController.dispose();
    _reportExportTimeController.dispose();
    _reportApiHostController.dispose();
    _reportApiPortController.dispose();
    _reportFilePrefixController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i18n = AppI18n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('settings.title')), elevation: 0),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.05),
                    theme.colorScheme.surface,
                  ],
                ),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                theme.colorScheme.primaryContainer.withValues(
                                  alpha: 0.92,
                                ),
                                theme.colorScheme.secondaryContainer.withValues(
                                  alpha: 0.82,
                                ),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Wrap(
                            spacing: 14,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 510,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      i18n.t('settings.centerTitle'),
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      i18n.t('settings.centerSubtitle'),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              _buildOverviewChip(
                                context,
                                icon: Icons.shield_outlined,
                                label: i18n.t('settings.overview.preset'),
                                value: _presetDisplayName(
                                  _selectedRecognitionPreset,
                                ),
                              ),
                              _buildOverviewChip(
                                context,
                                icon: Icons.table_chart,
                                label: i18n.t('settings.overview.report'),
                                value: _enableScheduledReportExport
                                    ? i18n.t('status.on')
                                    : i18n.t('status.off'),
                              ),
                              _buildOverviewChip(
                                context,
                                icon: Icons.cloud_outlined,
                                label: i18n.t('settings.overview.api'),
                                value: _enablePublicReportApi
                                    ? i18n.t('status.on')
                                    : i18n.t('status.off'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: _testConnection,
                              icon: const Icon(Icons.cloud_done),
                              label: Text(
                                i18n.t('settings.quick.testConnection'),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const PeopleManagementScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.people_alt),
                              label: Text(i18n.t('settings.quick.people')),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const UserManagementScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.manage_accounts),
                              label: Text(i18n.t('settings.quick.accounts')),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const ImageRecognitionTestScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.image_search),
                              label: Text(i18n.t('settings.quick.imageTest')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _buildSectionCard(
                          context,
                          icon: Icons.videocam,
                          title: _l(
                            context,
                            'Kết nối WebRTC',
                            'WebRTC Connectivity',
                          ),
                          subtitle: _l(
                            context,
                            'Thiết lập máy chủ signaling, STUN/TURN và chính sách truyền tải ICE.',
                            'Configure signaling server, STUN/TURN, and ICE transport policy.',
                          ),
                          child: Column(
                            children: [
                              _buildTextField(
                                controller: _signalingServerController,
                                label: _l(
                                  context,
                                  'URL máy chủ Signaling',
                                  'Signaling server URL',
                                ),
                                hint: 'wss://signaling.example.com',
                                helperText: _l(
                                  context,
                                  'Nhập địa chỉ máy chủ signaling (WebSocket)',
                                  'Enter signaling server address (WebSocket)',
                                ),
                                icon: Icons.link,
                              ),
                              const SizedBox(height: 12),
                              _buildServersField(
                                controller: _stunServersController,
                                label: _l(
                                  context,
                                  'Máy chủ STUN',
                                  'STUN servers',
                                ),
                                hint: 'stun:stun.l.google.com:19302',
                                helperText: _l(
                                  context,
                                  'Mỗi dòng một máy chủ STUN',
                                  'One STUN server per line',
                                ),
                                icon: Icons.dns_outlined,
                              ),
                              const SizedBox(height: 12),
                              _buildServersField(
                                controller: _turnServersController,
                                label: _l(
                                  context,
                                  'Máy chủ TURN',
                                  'TURN servers',
                                ),
                                hint: 'turn:turnserver.example.com:3478',
                                helperText: _l(
                                  context,
                                  'Mỗi dòng một máy chủ TURN',
                                  'One TURN server per line',
                                ),
                                icon: Icons.storage_rounded,
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final compact = constraints.maxWidth < 720;
                                  if (compact) {
                                    return Column(
                                      children: [
                                        _buildTextField(
                                          controller: _turnUsernameController,
                                          label: _l(
                                            context,
                                            'Tên người dùng TURN',
                                            'TURN username',
                                          ),
                                          hint: 'username',
                                          icon: Icons.person_outline,
                                        ),
                                        const SizedBox(height: 12),
                                        _buildTextField(
                                          controller: _turnPasswordController,
                                          label: _l(
                                            context,
                                            'Mật khẩu TURN',
                                            'TURN password',
                                          ),
                                          hint: 'password',
                                          obscureText: true,
                                          icon: Icons.password_rounded,
                                        ),
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: _buildTextField(
                                          controller: _turnUsernameController,
                                          label: _l(
                                            context,
                                            'Tên người dùng TURN',
                                            'TURN username',
                                          ),
                                          hint: 'username',
                                          icon: Icons.person_outline,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildTextField(
                                          controller: _turnPasswordController,
                                          label: _l(
                                            context,
                                            'Mật khẩu TURN',
                                            'TURN password',
                                          ),
                                          hint: 'password',
                                          obscureText: true,
                                          icon: Icons.password_rounded,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildDropdownField(),
                              const SizedBox(height: 10),
                              _buildCheckboxField(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildSectionCard(
                          context,
                          icon: Icons.table_view,
                          title: _l(
                            context,
                            'Báo cáo CSV và API công khai',
                            'CSV Reports and Public API',
                          ),
                          subtitle: _l(
                            context,
                            'Cấu hình lịch xuất báo cáo và dịch vụ API đọc dữ liệu chấm công.',
                            'Configure report schedule and API service for attendance data.',
                          ),
                          child: Column(
                            children: [
                              Material(
                                color: Colors.transparent,
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    _l(
                                      context,
                                      'Bật xuất báo cáo định kỳ',
                                      'Enable scheduled report export',
                                    ),
                                  ),
                                  subtitle: Text(
                                    _l(
                                      context,
                                      'Ứng dụng tự động xuất CSV theo lịch đã cấu hình.',
                                      'App automatically exports CSV based on the configured schedule.',
                                    ),
                                  ),
                                  value: _enableScheduledReportExport,
                                  onChanged: (value) {
                                    setState(() {
                                      _enableScheduledReportExport = value;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTextField(
                                      controller:
                                          _reportExportDirectoryController,
                                      label: _l(
                                        context,
                                        'Thư mục xuất báo cáo',
                                        'Report export directory',
                                      ),
                                      hint: 'C:/reports/attendance',
                                      helperText: _l(
                                        context,
                                        'Dùng cho job định kỳ và API save=true',
                                        'Used for scheduled job and API save=true',
                                      ),
                                      icon: Icons.folder_copy_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonalIcon(
                                    onPressed: _pickReportDirectory,
                                    icon: const Icon(Icons.folder_open),
                                    label: Text(_l(context, 'Chọn', 'Pick')),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final compact = constraints.maxWidth < 720;
                                  if (compact) {
                                    return Column(
                                      children: [
                                        _buildTextField(
                                          controller:
                                              _reportExportTimeController,
                                          label: _l(
                                            context,
                                            'Thời gian chạy định kỳ (HH:mm)',
                                            'Scheduled time (HH:mm)',
                                          ),
                                          hint: '23:55',
                                          helperText: _l(
                                            context,
                                            'Mỗi ngày chạy một lần theo giờ này',
                                            'Runs once daily at this time',
                                          ),
                                          icon: Icons.schedule,
                                        ),
                                        const SizedBox(height: 12),
                                        _buildTextField(
                                          controller:
                                              _reportFilePrefixController,
                                          label: _l(
                                            context,
                                            'Tiền tố tên tệp báo cáo',
                                            'Report file prefix',
                                          ),
                                          hint: 'attendance_report',
                                          icon: Icons.badge_outlined,
                                        ),
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: _buildTextField(
                                          controller:
                                              _reportExportTimeController,
                                          label: _l(
                                            context,
                                            'Thời gian chạy định kỳ (HH:mm)',
                                            'Scheduled time (HH:mm)',
                                          ),
                                          hint: '23:55',
                                          helperText: _l(
                                            context,
                                            'Mỗi ngày chạy một lần theo giờ này',
                                            'Runs once daily at this time',
                                          ),
                                          icon: Icons.schedule,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildTextField(
                                          controller:
                                              _reportFilePrefixController,
                                          label: _l(
                                            context,
                                            'Tiền tố tên tệp báo cáo',
                                            'Report file prefix',
                                          ),
                                          hint: 'attendance_report',
                                          icon: Icons.badge_outlined,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              Material(
                                color: Colors.transparent,
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    _l(
                                      context,
                                      'Bật API xuất báo cáo',
                                      'Enable report export API',
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'GET /api/reports/export?from=2026-07-01&to=2026-07-04&subject=An&type=start',
                                  ),
                                  value: _enablePublicReportApi,
                                  onChanged: (value) {
                                    setState(() {
                                      _enablePublicReportApi = value;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _reportApiHostController,
                                      label: _l(
                                        context,
                                        'Máy chủ API',
                                        'API host',
                                      ),
                                      hint: '0.0.0.0',
                                      icon: Icons.language,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _reportApiPortController,
                                      label: _l(
                                        context,
                                        'Cổng API',
                                        'API port',
                                      ),
                                      hint: '8787',
                                      icon: Icons.settings_ethernet,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildSectionCard(
                          context,
                          icon: Icons.tune,
                          title: _l(
                            context,
                            'Cấu hình nhận diện nâng cao',
                            'Advanced recognition settings',
                          ),
                          subtitle: _l(
                            context,
                            'Toàn bộ tham số nhận diện đã chuyển sang màn kiểm thử ảnh để tránh trùng lặp và dễ hiệu chỉnh theo ngữ cảnh.',
                            'Recognition parameters were moved to the image test screen to avoid duplication and support context-based tuning.',
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _l(
                                  context,
                                  'Mở màn kiểm thử ảnh để chỉnh tham số và áp dụng ngay vào luồng thời gian thực.',
                                  'Open image test screen to adjust parameters and apply them immediately to realtime flow.',
                                ),
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _faceMeshMaxWorkersController,
                                label: _l(
                                  context,
                                  'Số luồng Face Mesh tối đa',
                                  'Maximum Face Mesh workers',
                                ),
                                hint: '2',
                                helperText: _l(
                                  context,
                                  'Khuyến nghị 1-4 tùy CPU. Tăng cao có thể nóng máy và giảm ổn định.',
                                  'Recommended 1-4 based on CPU. Too high may reduce stability.',
                                ),
                                icon: Icons.hub_outlined,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const ImageRecognitionTestScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.image_search),
                                label: Text(i18n.t('settings.quick.imageTest')),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _resetToDefaults,
                                icon: const Icon(Icons.restore),
                                label: Text(i18n.t('settings.reset')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _saveSettings,
                                icon: const Icon(Icons.save),
                                label: Text(i18n.t('settings.save')),
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
    );
  }

  Widget _buildOverviewChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.20),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(20, 0, 0, 0),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? helperText,
    bool obscureText = false,
    IconData icon = Icons.language,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.85),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.58),
          ),
        ),
        prefixIcon: Icon(icon),
      ),
      obscureText: obscureText,
    );
  }

  Widget _buildServersField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String helperText,
    IconData icon = Icons.dns,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.85),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.58),
          ),
        ),
        prefixIcon: Icon(icon),
      ),
      maxLines: 4,
      minLines: 2,
    );
  }

  Widget _buildRecognitionTextField({
    required TextEditingController controller,
    required String label,
    String? parameterKey,
  }) {
    final resolvedKey =
        parameterKey ??
        _recognitionParameterLabels.entries
            .firstWhere(
              (entry) => entry.value == label,
              orElse: () => MapEntry<String, String>('', ''),
            )
            .key;
    final note = _recognitionParameterNotes[resolvedKey];

    return SizedBox(
      width: 230,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: note != null && note.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ParameterHelpButton(label: label, note: note),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildDropdownField() {
    return DropdownButtonFormField<String>(
      initialValue: _iceTransportPolicyController.text.isEmpty
          ? 'all'
          : _iceTransportPolicyController.text,
      decoration: InputDecoration(
        labelText: _l(
          context,
          'Chính sách vận chuyển ICE',
          'ICE transport policy',
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.85),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.58),
          ),
        ),
        prefixIcon: const Icon(Icons.device_hub),
      ),
      items: [
        DropdownMenuItem(
          value: 'all',
          child: Text(_l(context, 'Tất cả (UDP và TCP)', 'All (UDP and TCP)')),
        ),
        DropdownMenuItem(
          value: 'relay',
          child: Text(_l(context, 'Chỉ Relay (TURN)', 'Relay only (TURN)')),
        ),
      ],
      onChanged: (value) {
        if (value != null) {
          _iceTransportPolicyController.text = value;
        }
      },
    );
  }

  Widget _buildCheckboxField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.55),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          title: Text(
            _l(context, 'Kích hoạt xử lý âm thanh', 'Enable audio processing'),
          ),
          subtitle: Text(
            _l(
              context,
              'Bật xử lý âm thanh nâng cao để cải thiện chất lượng',
              'Enable advanced audio processing for better quality',
            ),
          ),
          value: _enableAudioProcessing,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _enableAudioProcessing = value;
              });
            }
          },
          secondary: const Icon(Icons.mic),
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    final signalingUrl = _signalingServerController.text.trim();
    if (signalingUrl.isEmpty) {
      _showErrorSnackBar(
        _l(
          context,
          'Vui lòng nhập URL máy chủ Signaling trước',
          'Please enter Signaling server URL first',
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(
            _l(context, 'Đang kiểm tra kết nối...', 'Testing connection...'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_l(context, 'Vui lòng đợi...', 'Please wait...')),
            ],
          ),
        );
      },
    );

    // Simulate connection test
    await Future<void>.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    Navigator.pop(context);

    // Show result
    _showSuccessSnackBar(
      _l(
        context,
        'Cấu hình máy chủ WebRTC hợp lệ',
        'WebRTC server configuration is valid',
      ),
    );
  }

  Future<void> _pickReportDirectory() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: _l(
        context,
        'Chọn thư mục xuất báo cáo CSV',
        'Select CSV export directory',
      ),
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) return;
    if (!mounted) return;
    setState(() {
      _reportExportDirectoryController.text = selectedPath.trim();
    });
  }
}

class ParameterHelpButton extends StatefulWidget {
  const ParameterHelpButton({
    super.key,
    required this.label,
    required this.note,
  });

  final String label;
  final String note;

  @override
  State<ParameterHelpButton> createState() => _ParameterHelpButtonState();
}

class _ParameterHelpButtonState extends State<ParameterHelpButton> {
  static _ParameterHelpButtonState? _activeState;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  Timer? _hideTimer;
  bool _hoveringButton = false;
  bool _hoveringPanel = false;

  bool get _isVisible => _overlayEntry != null;

  void _showPanel() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!mounted || _overlayEntry != null) return;
    if (_activeState != null && _activeState != this) {
      _activeState!._hidePanel();
    }

    final overlay = Overlay.of(context, rootOverlay: true);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        return Positioned.fill(
          child: IgnorePointer(
            ignoring: false,
            child: Stack(
              children: [
                CompositedTransformFollower(
                  link: _layerLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.centerRight,
                  followerAnchor: Alignment.centerLeft,
                  offset: const Offset(10, -2),
                  child: MouseRegion(
                    onEnter: (_) {
                      _hideTimer?.cancel();
                      _hideTimer = null;
                      _hoveringPanel = true;
                    },
                    onExit: (_) {
                      _hoveringPanel = false;
                      _scheduleHidePanel();
                    },
                    child: Material(
                      color: Colors.transparent,
                      elevation: 6,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 260),
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.surface,
                              theme.colorScheme.surfaceContainerHigh,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.outline.withValues(
                              alpha: 0.20,
                            ),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromARGB(28, 0, 0, 0),
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 14,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    widget.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.note,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.25,
                                fontSize: 11.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
    _activeState = this;
    setState(() {});
  }

  void _hidePanel() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_overlayEntry?.mounted ?? false) {
      _overlayEntry?.remove();
    }
    _overlayEntry = null;
    if (_activeState == this) {
      _activeState = null;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _maybeHidePanel() {
    if (_hoveringButton || _hoveringPanel) {
      return;
    }
    _hidePanel();
  }

  void _scheduleHidePanel() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 80), _maybeHidePanel);
  }

  void _handleEnter(_) {
    _hideTimer?.cancel();
    _hideTimer = null;
    _hoveringButton = true;
    _showPanel();
  }

  void _handleExit(_) {
    _hoveringButton = false;
    _scheduleHidePanel();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_overlayEntry?.mounted ?? false) {
      _overlayEntry?.remove();
    }
    _overlayEntry = null;
    if (_activeState == this) {
      _activeState = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _isVisible;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: _handleEnter,
        onExit: _handleExit,
        cursor: SystemMouseCursors.help,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: visible
                ? theme.colorScheme.primary.withValues(alpha: 0.16)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: visible
                  ? theme.colorScheme.primary.withValues(alpha: 0.46)
                  : theme.colorScheme.outline.withValues(alpha: 0.16),
              width: 0.9,
            ),
          ),
          child: Icon(
            Icons.question_mark_rounded,
            size: 12,
            color: visible
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
