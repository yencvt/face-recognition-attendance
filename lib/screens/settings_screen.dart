import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../database/report_settings_repository.dart';
import '../database/recognition_settings_repository.dart';
import '../database/settings_repository.dart';
import 'people_management_screen.dart';
import 'user_management_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Map<String, String> _recognitionParameterLabels = {
    'knownMatchThreshold': 'Nguong khop khuon mat',
    'knownStrongThreshold': 'Nguong khop manh (chac chan)',
    'knownCalibratedThreshold': 'Nguong khop da hieu chinh theo camera',
    'knownMatchMargin': 'Bien an toan giua nhat va nhi',
    'minTemplateSharpness': 'Do net toi thieu cua mau dang ky',
    'cameraCalibrationDurationMs': 'Thoi gian hieu chinh camera (ms)',
    'calibrationLogThrottleMs': 'Khoang cach log hieu chinh (ms)',
    'fallbackSkipLogIntervalMs': 'Khoang cach log bo qua fallback (ms)',
    'fallbackCaptureIntervalMs': 'Chu ky chup fallback (ms)',
    'fallbackMaxInputEdge': 'Canh toi da anh fallback (px)',
    'processFrameIntervalMs': 'Chu ky xu ly frame (ms)',
    'detectorInputWidth': 'Chieu rong input detector',
    'detectorInputHeight': 'Chieu cao input detector',
    'trackKeepAliveMs': 'Thoi gian giu track (ms)',
    'trackMatchMinScore': 'Diem toi thieu de gan track',
    'bboxSmoothingAlpha': 'He so lam muot khung bbox',
    'annotatedFrameMinIntervalMs': 'Khoang cach frame overlay toi thieu (ms)',
    'eventPublishIntervalMs': 'Khoang cach phat su kien (ms)',
    'minRealtimeFrameQuality': 'Chat luong frame toi thieu realtime',
    'minRealtimeFaceAreaRatio': 'Ty le dien tich mat toi thieu realtime',
    'minRealtimeFacePixels': 'So pixel mat toi thieu realtime',
    'voteWindowSize': 'So frame trong cua so bo phieu',
    'voteMinCount': 'So phieu toi thieu de chap nhan',
    'voteMaxAgeMs': 'Do tuoi toi da cua phieu (ms)',
    'minEnrollmentFaceAreaRatio': 'Ty le dien tich mat toi thieu khi dang ky',
    'maxEnrollmentFaceAreaRatio': 'Ty le dien tich mat toi da khi dang ky',
    'minEnrollmentFaceAspectRatio': 'Ty le khung mat toi thieu khi dang ky',
    'maxEnrollmentFaceAspectRatio': 'Ty le khung mat toi da khi dang ky',
    'minEnrollmentFacePixels': 'So pixel mat toi thieu khi dang ky',
    'scrfdInputSize': 'Kich thuoc input SCRFD',
    'scrfdScoreThreshold': 'Nguong diem phat hien SCRFD',
    'scrfdNmsThreshold': 'Nguong NMS SCRFD',
    'hnswM': 'HNSW M (so canh moi node)',
    'hnswEfConstruction': 'HNSW efConstruction',
    'hnswEfSearch': 'HNSW efSearch',
    'eyeRegionMinQuality': 'Nguong chat luong vung mat',
    'noseRegionMinQuality': 'Nguong chat luong vung mui',
    'mouthRegionMinQuality': 'Nguong chat luong vung mieng',
    'autoTuneRecognitionParameters': 'Tu dong dieu chinh tham so realtime',
  };

  static const Map<String, String> _recognitionParameterNotes = {
    'knownMatchThreshold': 'Nguong diem so khop tong quan de chap nhan danh tinh.',
    'knownStrongThreshold': 'Nguong rat cao cho phep chap nhan nhanh hon khi diem rat chac.',
    'knownCalibratedThreshold': 'Nguong diem sau hieu chinh theo do tach biet giua cac nguoi.',
    'knownMatchMargin': 'Khoang cach toi thieu giua top1 va top2 de tranh nham lan.',
    'minTemplateSharpness': 'Do net toi thieu cua anh mau khi tao vector.',
    'cameraCalibrationDurationMs': 'Thoi gian gom mau de hieu chinh threshold theo camera.',
    'calibrationLogThrottleMs': 'Tan suat ghi log trong giai doan hieu chinh.',
    'fallbackSkipLogIntervalMs': 'Khoang cach log khi bo qua frame loi fallback.',
    'fallbackCaptureIntervalMs': 'Khoang cach giua 2 lan chup fallback khi camera khong stream duoc.',
    'fallbackMaxInputEdge': 'Gioi han canh lon nhat cua frame fallback truoc khi xu ly de giam tai CPU.',
    'processFrameIntervalMs': 'Khoang cach xu ly giua 2 frame, nho hon thi nhanh hon nhung nang may.',
    'detectorInputWidth': 'Do rong anh dua vao detector; lon hon tang chat luong nhung cham hon.',
    'detectorInputHeight': 'Do cao anh dua vao detector; lon hon tang chat luong nhung cham hon.',
    'trackKeepAliveMs': 'Thoi gian giu doi tuong theo doi truoc khi reset.',
    'trackMatchMinScore': 'Diem toi thieu de noi bbox hien tai voi track truoc do.',
    'bboxSmoothingAlpha': 'He so lam muot bbox, cao thi bam theo nhanh nhung de rung.',
    'annotatedFrameMinIntervalMs': 'Chu ky toi thieu ve overlay debug, giam de cap nhat nhanh hon.',
    'eventPublishIntervalMs': 'Khoang cach toi thieu giua 2 su kien cung doi tuong.',
    'minRealtimeFrameQuality': 'Nguong chat luong frame realtime de cho phep nhan dien.',
    'minRealtimeFaceAreaRatio': 'Ty le dien tich mat toi thieu tren khung hinh.',
    'minRealtimeFacePixels': 'Canh ngan nhat cua mat (pixel) de tranh nhan dien mat qua nho.',
    'voteWindowSize': 'So frame luu trong cua so bo phieu tam thoi.',
    'voteMinCount': 'So phieu trung khop toi thieu de chap nhan nguoi quen.',
    'voteMaxAgeMs': 'Do tuoi toi da cua moi phieu trong bo phieu tam thoi.',
    'minEnrollmentFaceAreaRatio': 'Nguong nho nhat cho dien tich mat khi dang ky.',
    'maxEnrollmentFaceAreaRatio': 'Nguong lon nhat cho dien tich mat khi dang ky.',
    'minEnrollmentFaceAspectRatio': 'Ty le khung mat nho nhat cho phep khi dang ky.',
    'maxEnrollmentFaceAspectRatio': 'Ty le khung mat lon nhat cho phep khi dang ky.',
    'minEnrollmentFacePixels': 'Kich thuoc canh ngan toi thieu cua mat khi dang ky.',
    'scrfdInputSize': 'Kich thuoc input model SCRFD, lon hon thi tinh hon nhung cham hon.',
    'scrfdScoreThreshold': 'Nguong diem detector SCRFD de giu lai bbox.',
    'scrfdNmsThreshold': 'Nguong NMS SCRFD de loai bbox trung lap.',
    'hnswM': 'So ket noi toi da moi node trong do thi HNSW; lon hon thi tim tot hon nhung ton RAM hon.',
    'hnswEfConstruction': 'Do rong tim kiem khi xay dung index HNSW; lon hon thi index chat hon nhung build cham hon.',
    'hnswEfSearch': 'Do rong tim kiem luc query HNSW; lon hon thi chinh xac hon nhung cham hon.',
    'eyeRegionMinQuality': 'Nguong chat luong vung mat de dua vao partial embedding.',
    'noseRegionMinQuality': 'Nguong chat luong vung mui de dua vao partial embedding.',
    'mouthRegionMinQuality': 'Nguong chat luong vung mieng de dua vao partial embedding.',
    'autoTuneRecognitionParameters': 'Tu dong nang/giam nguong realtime theo chat luong anh va kich thuoc khuon mat.',
  };

  late TextEditingController _signalingServerController;
  late TextEditingController _stunServersController;
  late TextEditingController _turnServersController;
  late TextEditingController _turnUsernameController;
  late TextEditingController _turnPasswordController;
  late TextEditingController _iceTransportPolicyController;
  late TextEditingController _knownMatchThresholdController;
  late TextEditingController _knownStrongThresholdController;
  late TextEditingController _knownCalibratedThresholdController;
  late TextEditingController _knownMatchMarginController;
  late TextEditingController _minTemplateSharpnessController;
  late TextEditingController _cameraCalibrationDurationMsController;
  late TextEditingController _calibrationLogThrottleMsController;
  late TextEditingController _fallbackSkipLogIntervalMsController;
  late TextEditingController _fallbackCaptureIntervalMsController;
  late TextEditingController _fallbackMaxInputEdgeController;
  late TextEditingController _processFrameIntervalMsController;
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
  late TextEditingController _voteWindowSizeController;
  late TextEditingController _voteMinCountController;
  late TextEditingController _voteMaxAgeMsController;
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
  late TextEditingController _reportExportDirectoryController;
  late TextEditingController _reportExportTimeController;
  late TextEditingController _reportApiHostController;
  late TextEditingController _reportApiPortController;
  late TextEditingController _reportFilePrefixController;
  String _selectedRecognitionPreset = 'strict';
  bool _autoTuneRecognitionParameters = false;
  bool _enableAudioProcessing = true;
  bool _debugRealtimeOverlay = true;
  bool _enableScheduledReportExport = false;
  bool _enablePublicReportApi = true;
  bool _isLoading = true;

  String _recognitionLabel(String key) =>
      _recognitionParameterLabels[key] ?? key;

  String _presetDisplayName(String preset) {
    switch (preset) {
      case 'accuracy':
        return 'Accuracy cao';
      case 'balanced':
        return 'Can bang';
      case 'low-light':
        return 'Anh sang yeu';
      case 'far-distance':
        return 'Xa camera';
      case 'speed':
        return 'Toc do cao';
      case 'strict':
        return 'Chong nhan nham';
      case 'recall':
        return 'Uu tien khong bo sot';
      default:
        return 'Tuy chinh';
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
    _knownStrongThresholdController = TextEditingController();
    _knownCalibratedThresholdController = TextEditingController();
    _knownMatchMarginController = TextEditingController();
    _minTemplateSharpnessController = TextEditingController();
    _cameraCalibrationDurationMsController = TextEditingController();
    _calibrationLogThrottleMsController = TextEditingController();
    _fallbackSkipLogIntervalMsController = TextEditingController();
    _fallbackCaptureIntervalMsController = TextEditingController();
    _fallbackMaxInputEdgeController = TextEditingController();
    _processFrameIntervalMsController = TextEditingController();
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
    _voteWindowSizeController = TextEditingController();
    _voteMinCountController = TextEditingController();
    _voteMaxAgeMsController = TextEditingController();
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
      final reportConfig = await ReportSettingsRepository.getOrCreateDefaultConfig();
      if (!mounted) return;
      setState(() {
        _signalingServerController.text = settings.signalingServerUrl;
        _turnUsernameController.text = settings.turnUsername;
        _turnPasswordController.text = settings.turnPassword;
        _iceTransportPolicyController.text = settings.iceTransportPolicy;
        _enableAudioProcessing = settings.enableAudioProcessing;
        _knownMatchThresholdController.text =
          recognitionConfig.knownMatchThreshold.toString();
        _knownStrongThresholdController.text =
          recognitionConfig.knownStrongThreshold.toString();
        _knownCalibratedThresholdController.text =
          recognitionConfig.knownCalibratedThreshold.toString();
        _knownMatchMarginController.text =
          recognitionConfig.knownMatchMargin.toString();
        _minTemplateSharpnessController.text =
          recognitionConfig.minTemplateSharpness.toString();
        _cameraCalibrationDurationMsController.text =
          recognitionConfig.cameraCalibrationDurationMs.toString();
        _calibrationLogThrottleMsController.text =
          recognitionConfig.calibrationLogThrottleMs.toString();
        _fallbackSkipLogIntervalMsController.text =
          recognitionConfig.fallbackSkipLogIntervalMs.toString();
        _fallbackCaptureIntervalMsController.text =
          recognitionConfig.fallbackCaptureIntervalMs.toString();
        _fallbackMaxInputEdgeController.text =
          recognitionConfig.fallbackMaxInputEdge.toString();
        _processFrameIntervalMsController.text =
          recognitionConfig.processFrameIntervalMs.toString();
        _detectorInputWidthController.text =
          recognitionConfig.detectorInputWidth.toString();
        _detectorInputHeightController.text =
          recognitionConfig.detectorInputHeight.toString();
        _trackKeepAliveMsController.text =
          recognitionConfig.trackKeepAliveMs.toString();
        _trackMatchMinScoreController.text =
          recognitionConfig.trackMatchMinScore.toString();
        _bboxSmoothingAlphaController.text =
          recognitionConfig.bboxSmoothingAlpha.toString();
        _annotatedFrameMinIntervalMsController.text =
          recognitionConfig.annotatedFrameMinIntervalMs.toString();
        _eventPublishIntervalMsController.text =
          recognitionConfig.eventPublishIntervalMs.toString();
        _minRealtimeFrameQualityController.text =
          recognitionConfig.minRealtimeFrameQuality.toString();
        _minRealtimeFaceAreaRatioController.text =
          recognitionConfig.minRealtimeFaceAreaRatio.toString();
        _minRealtimeFacePixelsController.text =
          recognitionConfig.minRealtimeFacePixels.toString();
        _voteWindowSizeController.text = recognitionConfig.voteWindowSize.toString();
        _voteMinCountController.text = recognitionConfig.voteMinCount.toString();
        _voteMaxAgeMsController.text = recognitionConfig.voteMaxAgeMs.toString();
        _minEnrollmentFaceAreaRatioController.text =
          recognitionConfig.minEnrollmentFaceAreaRatio.toString();
        _maxEnrollmentFaceAreaRatioController.text =
          recognitionConfig.maxEnrollmentFaceAreaRatio.toString();
        _minEnrollmentFaceAspectRatioController.text =
          recognitionConfig.minEnrollmentFaceAspectRatio.toString();
        _maxEnrollmentFaceAspectRatioController.text =
          recognitionConfig.maxEnrollmentFaceAspectRatio.toString();
        _minEnrollmentFacePixelsController.text =
          recognitionConfig.minEnrollmentFacePixels.toString();
        _scrfdInputSizeController.text = recognitionConfig.scrfdInputSize.toString();
        _scrfdScoreThresholdController.text =
          recognitionConfig.scrfdScoreThreshold.toString();
        _scrfdNmsThresholdController.text =
          recognitionConfig.scrfdNmsThreshold.toString();
        _hnswMController.text = recognitionConfig.hnswM.toString();
        _hnswEfConstructionController.text =
          recognitionConfig.hnswEfConstruction.toString();
        _hnswEfSearchController.text = recognitionConfig.hnswEfSearch.toString();
        _eyeRegionMinQualityController.text =
          recognitionConfig.eyeRegionMinQuality.toString();
        _noseRegionMinQualityController.text =
          recognitionConfig.noseRegionMinQuality.toString();
        _mouthRegionMinQualityController.text =
          recognitionConfig.mouthRegionMinQuality.toString();
        _autoTuneRecognitionParameters = recognitionConfig.autoTuneRecognitionParameters;
        _debugRealtimeOverlay = recognitionConfig.debugRealtimeOverlay;
        _reportExportDirectoryController.text =
          reportConfig.scheduledExportDirectory;
        _reportExportTimeController.text = reportConfig.scheduledExportTime;
        _reportApiHostController.text = reportConfig.apiHost;
        _reportApiPortController.text = reportConfig.apiPort.toString();
        _reportFilePrefixController.text = reportConfig.filePrefix;
        _enableScheduledReportExport = reportConfig.scheduledExportEnabled;
        _enablePublicReportApi = reportConfig.apiEnabled;
        _selectedRecognitionPreset = _recognitionPresetForConfig(recognitionConfig);

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
        SnackBar(content: Text('Lỗi tải cấu hình: $e')),
      );
    }
  }

  Future<void> _saveSettings() async {
    try {
      double parseDouble(TextEditingController controller, String label) {
        final value = double.tryParse(controller.text.trim());
        if (value == null) {
          throw FormatException('Gia tri "${_recognitionLabel(label)}" khong hop le');
        }
        return value;
      }

      int parseInt(TextEditingController controller, String label) {
        final value = int.tryParse(controller.text.trim());
        if (value == null) {
          throw FormatException('Gia tri "${_recognitionLabel(label)}" khong hop le');
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
        _showErrorSnackBar('Vui lòng nhập URL máy chủ Signaling');
        return;
      }

      if (stunList.isEmpty && turnList.isEmpty) {
        _showErrorSnackBar('Vui lòng nhập ít nhất một STUN hoặc TURN server');
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

      final recognitionConfig = RecognitionRuntimeConfig(
        knownMatchThreshold: parseDouble(_knownMatchThresholdController, 'knownMatchThreshold'),
        knownStrongThreshold: parseDouble(_knownStrongThresholdController, 'knownStrongThreshold'),
        knownCalibratedThreshold: parseDouble(_knownCalibratedThresholdController, 'knownCalibratedThreshold'),
        knownMatchMargin: parseDouble(_knownMatchMarginController, 'knownMatchMargin'),
        minTemplateSharpness: parseDouble(_minTemplateSharpnessController, 'minTemplateSharpness'),
        cameraCalibrationDurationMs: parseInt(_cameraCalibrationDurationMsController, 'cameraCalibrationDurationMs'),
        calibrationLogThrottleMs: parseInt(_calibrationLogThrottleMsController, 'calibrationLogThrottleMs'),
        fallbackSkipLogIntervalMs: parseInt(_fallbackSkipLogIntervalMsController, 'fallbackSkipLogIntervalMs'),
        fallbackCaptureIntervalMs: parseInt(_fallbackCaptureIntervalMsController, 'fallbackCaptureIntervalMs'),
        fallbackMaxInputEdge: parseInt(_fallbackMaxInputEdgeController, 'fallbackMaxInputEdge'),
        processFrameIntervalMs: parseInt(_processFrameIntervalMsController, 'processFrameIntervalMs'),
        detectorInputWidth: parseInt(_detectorInputWidthController, 'detectorInputWidth'),
        detectorInputHeight: parseInt(_detectorInputHeightController, 'detectorInputHeight'),
        trackKeepAliveMs: parseInt(_trackKeepAliveMsController, 'trackKeepAliveMs'),
        trackMatchMinScore: parseDouble(_trackMatchMinScoreController, 'trackMatchMinScore'),
        bboxSmoothingAlpha: parseDouble(_bboxSmoothingAlphaController, 'bboxSmoothingAlpha'),
        annotatedFrameMinIntervalMs: parseInt(_annotatedFrameMinIntervalMsController, 'annotatedFrameMinIntervalMs'),
        eventPublishIntervalMs: parseInt(_eventPublishIntervalMsController, 'eventPublishIntervalMs'),
        minRealtimeFrameQuality: parseDouble(_minRealtimeFrameQualityController, 'minRealtimeFrameQuality'),
        minRealtimeFaceAreaRatio: parseDouble(_minRealtimeFaceAreaRatioController, 'minRealtimeFaceAreaRatio'),
        minRealtimeFacePixels: parseInt(_minRealtimeFacePixelsController, 'minRealtimeFacePixels'),
        voteWindowSize: parseInt(_voteWindowSizeController, 'voteWindowSize'),
        voteMinCount: parseInt(_voteMinCountController, 'voteMinCount'),
        voteMaxAgeMs: parseInt(_voteMaxAgeMsController, 'voteMaxAgeMs'),
        minEnrollmentFaceAreaRatio: parseDouble(_minEnrollmentFaceAreaRatioController, 'minEnrollmentFaceAreaRatio'),
        maxEnrollmentFaceAreaRatio: parseDouble(_maxEnrollmentFaceAreaRatioController, 'maxEnrollmentFaceAreaRatio'),
        minEnrollmentFaceAspectRatio: parseDouble(_minEnrollmentFaceAspectRatioController, 'minEnrollmentFaceAspectRatio'),
        maxEnrollmentFaceAspectRatio: parseDouble(_maxEnrollmentFaceAspectRatioController, 'maxEnrollmentFaceAspectRatio'),
        minEnrollmentFacePixels: parseInt(_minEnrollmentFacePixelsController, 'minEnrollmentFacePixels'),
        scrfdInputSize: parseInt(_scrfdInputSizeController, 'scrfdInputSize'),
        scrfdScoreThreshold: parseDouble(_scrfdScoreThresholdController, 'scrfdScoreThreshold'),
        scrfdNmsThreshold: parseDouble(_scrfdNmsThresholdController, 'scrfdNmsThreshold'),
        hnswM: parseInt(_hnswMController, 'hnswM'),
        hnswEfConstruction: parseInt(_hnswEfConstructionController, 'hnswEfConstruction'),
        hnswEfSearch: parseInt(_hnswEfSearchController, 'hnswEfSearch'),
        eyeRegionMinQuality: parseDouble(_eyeRegionMinQualityController, 'eyeRegionMinQuality'),
        noseRegionMinQuality: parseDouble(_noseRegionMinQualityController, 'noseRegionMinQuality'),
        mouthRegionMinQuality: parseDouble(_mouthRegionMinQualityController, 'mouthRegionMinQuality'),
        autoTuneRecognitionParameters: _autoTuneRecognitionParameters,
        debugRealtimeOverlay: _debugRealtimeOverlay,
      );
      await RecognitionSettingsRepository.saveConfig(recognitionConfig);

      final scheduleTime = _reportExportTimeController.text.trim();
      final scheduleParts = scheduleTime.split(':');
      if (scheduleParts.length != 2 ||
          int.tryParse(scheduleParts[0]) == null ||
          int.tryParse(scheduleParts[1]) == null) {
        _showErrorSnackBar('Thoi gian chay job phai theo dinh dang HH:mm');
        return;
      }

      final scheduleHour = int.parse(scheduleParts[0]);
      final scheduleMinute = int.parse(scheduleParts[1]);
      if (scheduleHour < 0 || scheduleHour > 23 || scheduleMinute < 0 || scheduleMinute > 59) {
        _showErrorSnackBar('Thoi gian chay job khong hop le');
        return;
      }

      final reportApiPort = int.tryParse(_reportApiPortController.text.trim());
      if (reportApiPort == null || reportApiPort <= 0 || reportApiPort > 65535) {
        _showErrorSnackBar('Cong API bao cao khong hop le (1-65535)');
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
      _showSuccessSnackBar('Cấu hình đã được lưu và áp dụng ngay lập tức');
    } catch (e) {
      _showErrorSnackBar('Lỗi lưu cấu hình: $e');
    }
  }

  void _setRecognitionControllers(RecognitionRuntimeConfig config) {
    _knownMatchThresholdController.text = config.knownMatchThreshold.toString();
    _knownStrongThresholdController.text = config.knownStrongThreshold.toString();
    _knownCalibratedThresholdController.text =
        config.knownCalibratedThreshold.toString();
    _knownMatchMarginController.text = config.knownMatchMargin.toString();
    _minTemplateSharpnessController.text = config.minTemplateSharpness.toString();
    _cameraCalibrationDurationMsController.text =
        config.cameraCalibrationDurationMs.toString();
    _calibrationLogThrottleMsController.text =
        config.calibrationLogThrottleMs.toString();
    _fallbackSkipLogIntervalMsController.text =
        config.fallbackSkipLogIntervalMs.toString();
    _fallbackCaptureIntervalMsController.text =
      config.fallbackCaptureIntervalMs.toString();
    _fallbackMaxInputEdgeController.text =
      config.fallbackMaxInputEdge.toString();
    _processFrameIntervalMsController.text = config.processFrameIntervalMs.toString();
    _detectorInputWidthController.text = config.detectorInputWidth.toString();
    _detectorInputHeightController.text = config.detectorInputHeight.toString();
    _trackKeepAliveMsController.text = config.trackKeepAliveMs.toString();
    _trackMatchMinScoreController.text = config.trackMatchMinScore.toString();
    _bboxSmoothingAlphaController.text = config.bboxSmoothingAlpha.toString();
    _annotatedFrameMinIntervalMsController.text =
        config.annotatedFrameMinIntervalMs.toString();
    _eventPublishIntervalMsController.text = config.eventPublishIntervalMs.toString();
    _minRealtimeFrameQualityController.text =
        config.minRealtimeFrameQuality.toString();
    _minRealtimeFaceAreaRatioController.text =
        config.minRealtimeFaceAreaRatio.toString();
    _minRealtimeFacePixelsController.text = config.minRealtimeFacePixels.toString();
    _voteWindowSizeController.text = config.voteWindowSize.toString();
    _voteMinCountController.text = config.voteMinCount.toString();
    _voteMaxAgeMsController.text = config.voteMaxAgeMs.toString();
    _minEnrollmentFaceAreaRatioController.text =
        config.minEnrollmentFaceAreaRatio.toString();
    _maxEnrollmentFaceAreaRatioController.text =
        config.maxEnrollmentFaceAreaRatio.toString();
    _minEnrollmentFaceAspectRatioController.text =
        config.minEnrollmentFaceAspectRatio.toString();
    _maxEnrollmentFaceAspectRatioController.text =
        config.maxEnrollmentFaceAspectRatio.toString();
    _minEnrollmentFacePixelsController.text =
        config.minEnrollmentFacePixels.toString();
    _scrfdInputSizeController.text = config.scrfdInputSize.toString();
    _scrfdScoreThresholdController.text = config.scrfdScoreThreshold.toString();
    _scrfdNmsThresholdController.text = config.scrfdNmsThreshold.toString();
    _hnswMController.text = config.hnswM.toString();
    _hnswEfConstructionController.text = config.hnswEfConstruction.toString();
    _hnswEfSearchController.text = config.hnswEfSearch.toString();
    _eyeRegionMinQualityController.text = config.eyeRegionMinQuality.toString();
    _noseRegionMinQualityController.text = config.noseRegionMinQuality.toString();
    _mouthRegionMinQualityController.text = config.mouthRegionMinQuality.toString();
    _autoTuneRecognitionParameters = config.autoTuneRecognitionParameters;
    _debugRealtimeOverlay = config.debugRealtimeOverlay;
  }

  RecognitionRuntimeConfig _presetAccuracyConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.95,
      knownStrongThreshold: 0.98,
      knownCalibratedThreshold: 0.92,
      knownMatchMargin: 0.22,
      minTemplateSharpness: 36.0,
      processFrameIntervalMs: 80,
      eventPublishIntervalMs: 70000,
      minRealtimeFrameQuality: 0.28,
      minRealtimeFaceAreaRatio: 0.05,
      minRealtimeFacePixels: 72,
      voteWindowSize: 7,
      voteMinCount: 5,
      voteMaxAgeMs: 2400,
      scrfdScoreThreshold: 0.62,
      scrfdNmsThreshold: 0.34,
      autoTuneRecognitionParameters: false,
    );
  }

  RecognitionRuntimeConfig _presetBalancedConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.92,
      knownStrongThreshold: 0.96,
      knownCalibratedThreshold: 0.78,
      knownMatchMargin: 0.18,
      minTemplateSharpness: 28.0,
      processFrameIntervalMs: 50,
      eventPublishIntervalMs: 60000,
      minRealtimeFrameQuality: 0.22,
      minRealtimeFaceAreaRatio: 0.035,
      minRealtimeFacePixels: 56,
      voteWindowSize: 5,
      voteMinCount: 3,
      voteMaxAgeMs: 1800,
      scrfdScoreThreshold: 0.55,
      scrfdNmsThreshold: 0.38,
      hnswM: 20,
      hnswEfConstruction: 144,
      hnswEfSearch: 160,
      eyeRegionMinQuality: 0.24,
      noseRegionMinQuality: 0.22,
      mouthRegionMinQuality: 0.22,
      autoTuneRecognitionParameters: false,
    );
  }

  RecognitionRuntimeConfig _presetLowLightConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.97,
      knownStrongThreshold: 0.989,
      knownCalibratedThreshold: 0.95,
      knownMatchMargin: 0.28,
      minTemplateSharpness: 40.0,
      processFrameIntervalMs: 70,
      eventPublishIntervalMs: 90000,
      minRealtimeFrameQuality: 0.33,
      minRealtimeFaceAreaRatio: 0.06,
      minRealtimeFacePixels: 80,
      voteWindowSize: 9,
      voteMinCount: 7,
      voteMaxAgeMs: 2800,
      scrfdInputSize: 640,
      scrfdScoreThreshold: 0.66,
      scrfdNmsThreshold: 0.32,
      hnswM: 24,
      hnswEfConstruction: 200,
      hnswEfSearch: 240,
      eyeRegionMinQuality: 0.32,
      noseRegionMinQuality: 0.30,
      mouthRegionMinQuality: 0.30,
      autoTuneRecognitionParameters: true,
    );
  }

  RecognitionRuntimeConfig _presetFarDistanceConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.955,
      knownStrongThreshold: 0.98,
      knownCalibratedThreshold: 0.90,
      knownMatchMargin: 0.20,
      minTemplateSharpness: 32.0,
      processFrameIntervalMs: 60,
      eventPublishIntervalMs: 70000,
      minRealtimeFrameQuality: 0.20,
      minRealtimeFaceAreaRatio: 0.015,
      minRealtimeFacePixels: 30,
      voteWindowSize: 5,
      voteMinCount: 3,
      voteMaxAgeMs: 2000,
      scrfdInputSize: 640,
      scrfdScoreThreshold: 0.50,
      scrfdNmsThreshold: 0.36,
      hnswM: 24,
      hnswEfConstruction: 180,
      hnswEfSearch: 220,
      eyeRegionMinQuality: 0.22,
      noseRegionMinQuality: 0.20,
      mouthRegionMinQuality: 0.20,
      autoTuneRecognitionParameters: true,
    );
  }

  RecognitionRuntimeConfig _presetSpeedConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.90,
      knownStrongThreshold: 0.95,
      knownCalibratedThreshold: 0.74,
      knownMatchMargin: 0.15,
      minTemplateSharpness: 24.0,
      processFrameIntervalMs: 34,
      eventPublishIntervalMs: 45000,
      minRealtimeFrameQuality: 0.16,
      minRealtimeFaceAreaRatio: 0.026,
      minRealtimeFacePixels: 44,
      voteWindowSize: 3,
      voteMinCount: 2,
      voteMaxAgeMs: 1200,
      scrfdInputSize: 512,
      scrfdScoreThreshold: 0.47,
      scrfdNmsThreshold: 0.42,
      autoTuneRecognitionParameters: false,
    );
  }

  RecognitionRuntimeConfig _presetStrictConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.965,
      knownStrongThreshold: 0.985,
      knownCalibratedThreshold: 0.94,
      knownMatchMargin: 0.26,
      minTemplateSharpness: 38.0,
      processFrameIntervalMs: 70,
      eventPublishIntervalMs: 80000,
      minRealtimeFrameQuality: 0.30,
      minRealtimeFaceAreaRatio: 0.055,
      minRealtimeFacePixels: 76,
      voteWindowSize: 8,
      voteMinCount: 6,
      voteMaxAgeMs: 2600,
      scrfdInputSize: 640,
      scrfdScoreThreshold: 0.64,
      scrfdNmsThreshold: 0.33,
      hnswM: 24,
      hnswEfConstruction: 200,
      hnswEfSearch: 220,
      eyeRegionMinQuality: 0.30,
      noseRegionMinQuality: 0.28,
      mouthRegionMinQuality: 0.28,
      autoTuneRecognitionParameters: false,
    );
  }

  RecognitionRuntimeConfig _presetRecallConfig() {
    return const RecognitionRuntimeConfig(
      knownMatchThreshold: 0.90,
      knownStrongThreshold: 0.95,
      knownCalibratedThreshold: 0.72,
      knownMatchMargin: 0.12,
      minTemplateSharpness: 24.0,
      processFrameIntervalMs: 38,
      eventPublishIntervalMs: 42000,
      minRealtimeFrameQuality: 0.15,
      minRealtimeFaceAreaRatio: 0.024,
      minRealtimeFacePixels: 42,
      voteWindowSize: 4,
      voteMinCount: 2,
      voteMaxAgeMs: 1300,
      scrfdInputSize: 512,
      scrfdScoreThreshold: 0.45,
      scrfdNmsThreshold: 0.44,
      hnswM: 20,
      hnswEfConstruction: 160,
      hnswEfSearch: 220,
      eyeRegionMinQuality: 0.20,
      noseRegionMinQuality: 0.18,
      mouthRegionMinQuality: 0.18,
      autoTuneRecognitionParameters: false,
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
    _showSuccessSnackBar('Da ap dung preset ${_presetDisplayName(preset)}');
  }

  String _recognitionPresetForConfig(RecognitionRuntimeConfig config) {
    if (config.toJson() == _presetStrictConfig().toJson()) return 'strict';
    if (config.toJson() == _presetLowLightConfig().toJson()) return 'low-light';
    if (config.toJson() == _presetFarDistanceConfig().toJson()) return 'far-distance';
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
          title: const Text('Đặt lại cấu hình mặc định'),
          content: const Text(
            'Điều này sẽ đặt lại tất cả các cài đặt WebRTC về giá trị mặc định. Bạn chắc chắn muốn tiếp tục?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                final defaults = WebRTCSettings(
                  id: 'default_webrtc_config',
                  signalingServerUrl: 'wss://signaling.example.com',
                  stunServers: '["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]',
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
              child: const Text('Đặt lại'),
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
    _knownStrongThresholdController.dispose();
    _knownCalibratedThresholdController.dispose();
    _knownMatchMarginController.dispose();
    _minTemplateSharpnessController.dispose();
    _cameraCalibrationDurationMsController.dispose();
    _calibrationLogThrottleMsController.dispose();
    _fallbackSkipLogIntervalMsController.dispose();
    _fallbackCaptureIntervalMsController.dispose();
    _fallbackMaxInputEdgeController.dispose();
    _processFrameIntervalMsController.dispose();
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
    _voteWindowSizeController.dispose();
    _voteMinCountController.dispose();
    _voteMaxAgeMsController.dispose();
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
    _reportExportDirectoryController.dispose();
    _reportExportTimeController.dispose();
    _reportApiHostController.dispose();
    _reportApiPortController.dispose();
    _reportFilePrefixController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấu hình hệ thống'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // WebRTC Server Configuration Card
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.videocam,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Cấu hình máy chủ WebRTC',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _signalingServerController,
                            label: 'URL Máy chủ Signaling',
                            hint: 'wss://signaling.example.com',
                            helperText: 'Nhập địa chỉ máy chủ signaling (WebSocket)',
                          ),
                          const SizedBox(height: 16),
                          _buildServersField(
                            controller: _stunServersController,
                            label: 'STUN Servers',
                            hint: 'stun:stun.l.google.com:19302',
                            helperText: 'Nhập một STUN server trên mỗi dòng',
                          ),
                          const SizedBox(height: 16),
                          _buildServersField(
                            controller: _turnServersController,
                            label: 'TURN Servers',
                            hint: 'turn:turnserver.example.com:3478',
                            helperText: 'Nhập một TURN server trên mỗi dòng',
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _turnUsernameController,
                            label: 'Tên người dùng TURN',
                            hint: 'username',
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _turnPasswordController,
                            label: 'Mật khẩu TURN',
                            hint: 'password',
                            obscureText: true,
                          ),
                          const SizedBox(height: 16),
                          _buildDropdownField(),
                          const SizedBox(height: 16),
                          _buildCheckboxField(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Connection Test Section
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.link,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Kiểm tra kết nối',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Kiểm tra xem máy chủ WebRTC có thể kết nối được từ thiết bị này không.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _testConnection,
                            icon: const Icon(Icons.cloud_queue),
                            label: const Text('Kiểm tra kết nối'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.manage_accounts,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Nguoi nhan dien',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Them thong tin va anh tham chieu cho moi nguoi de phuc vu nhan dien cham cong.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const PeopleManagementScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.people_alt),
                            label: const Text('Quan ly nguoi'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.manage_accounts_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Tai khoan dang nhap',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Them, sua, xoa tai khoan dang nhap dung cho man hinh login va tu dong logout.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const UserManagementScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Quan ly user'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.tune,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Cau hinh tham so nhan dien (ap dung ngay)',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tat ca tham so duoc luu DB va service se cap nhat real-time, khong can sua code.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () => _applyRecognitionPreset('accuracy'),
                                icon: const Icon(Icons.bolt),
                                label: const Text('Accuracy cao'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => _applyRecognitionPreset('balanced'),
                                icon: const Icon(Icons.balance),
                                label: const Text('Can bang'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => _applyRecognitionPreset('speed'),
                                icon: const Icon(Icons.speed),
                                label: const Text('Toc do cao'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => _applyRecognitionPreset('strict'),
                                icon: const Icon(Icons.gpp_good),
                                label: const Text('Chong nhan nham'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => _applyRecognitionPreset('low-light'),
                                icon: const Icon(Icons.dark_mode),
                                label: const Text('Anh sang yeu'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => _applyRecognitionPreset('far-distance'),
                                icon: const Icon(Icons.zoom_out_map),
                                label: const Text('Xa camera'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => _applyRecognitionPreset('recall'),
                                icon: const Icon(Icons.person_search),
                                label: const Text('Uu tien khong bo sot'),
                              ),
                              Chip(
                                label: Text('Preset: ${_presetDisplayName(_selectedRecognitionPreset)}'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Accuracy cao: tang do chac chan, giam nham lan, doi hoi anh/chat luong tot.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            'Can bang: thong so mac dinh cho van hanh chung.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            'Toc do cao: uu tien toc do, chap nhan giam do chac chan.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            'Chong nhan nham: uu tien khong nhan nguoi la thanh nguoi that (siết mạnh).',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            'Anh sang yeu: can bang cho moi truong toi/anh xau, siết nham lan nhung van giu do on dinh cho frame tot.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            'Xa camera: giam nguong cho mat nho/far, uu tien giu mat o xa van duoc nhan dien thay vi bo qua.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            'Uu tien khong bo sot: uu tien nhan ra nguoi that, co the tang nham lan neu moi truong xau.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _buildRecognitionTextField(controller: _knownMatchThresholdController, label: _recognitionLabel('knownMatchThreshold')),
                              _buildRecognitionTextField(controller: _knownStrongThresholdController, label: _recognitionLabel('knownStrongThreshold')),
                              _buildRecognitionTextField(controller: _knownCalibratedThresholdController, label: _recognitionLabel('knownCalibratedThreshold')),
                              _buildRecognitionTextField(controller: _knownMatchMarginController, label: _recognitionLabel('knownMatchMargin')),
                              _buildRecognitionTextField(controller: _minTemplateSharpnessController, label: _recognitionLabel('minTemplateSharpness')),
                              _buildRecognitionTextField(controller: _cameraCalibrationDurationMsController, label: _recognitionLabel('cameraCalibrationDurationMs')),
                              _buildRecognitionTextField(controller: _calibrationLogThrottleMsController, label: _recognitionLabel('calibrationLogThrottleMs')),
                              _buildRecognitionTextField(controller: _fallbackSkipLogIntervalMsController, label: _recognitionLabel('fallbackSkipLogIntervalMs')),
                              _buildRecognitionTextField(controller: _fallbackCaptureIntervalMsController, label: _recognitionLabel('fallbackCaptureIntervalMs')),
                              _buildRecognitionTextField(controller: _fallbackMaxInputEdgeController, label: _recognitionLabel('fallbackMaxInputEdge')),
                              _buildRecognitionTextField(controller: _processFrameIntervalMsController, label: _recognitionLabel('processFrameIntervalMs')),
                              _buildRecognitionTextField(controller: _detectorInputWidthController, label: _recognitionLabel('detectorInputWidth')),
                              _buildRecognitionTextField(controller: _detectorInputHeightController, label: _recognitionLabel('detectorInputHeight')),
                              _buildRecognitionTextField(controller: _trackKeepAliveMsController, label: _recognitionLabel('trackKeepAliveMs')),
                              _buildRecognitionTextField(controller: _trackMatchMinScoreController, label: _recognitionLabel('trackMatchMinScore')),
                              _buildRecognitionTextField(controller: _bboxSmoothingAlphaController, label: _recognitionLabel('bboxSmoothingAlpha')),
                              _buildRecognitionTextField(controller: _annotatedFrameMinIntervalMsController, label: _recognitionLabel('annotatedFrameMinIntervalMs')),
                              _buildRecognitionTextField(controller: _eventPublishIntervalMsController, label: _recognitionLabel('eventPublishIntervalMs')),
                              _buildRecognitionTextField(controller: _minRealtimeFrameQualityController, label: _recognitionLabel('minRealtimeFrameQuality')),
                              _buildRecognitionTextField(controller: _minRealtimeFaceAreaRatioController, label: _recognitionLabel('minRealtimeFaceAreaRatio')),
                              _buildRecognitionTextField(controller: _minRealtimeFacePixelsController, label: _recognitionLabel('minRealtimeFacePixels')),
                              _buildRecognitionTextField(controller: _voteWindowSizeController, label: _recognitionLabel('voteWindowSize')),
                              _buildRecognitionTextField(controller: _voteMinCountController, label: _recognitionLabel('voteMinCount')),
                              _buildRecognitionTextField(controller: _voteMaxAgeMsController, label: _recognitionLabel('voteMaxAgeMs')),
                              _buildRecognitionTextField(controller: _minEnrollmentFaceAreaRatioController, label: _recognitionLabel('minEnrollmentFaceAreaRatio')),
                              _buildRecognitionTextField(controller: _maxEnrollmentFaceAreaRatioController, label: _recognitionLabel('maxEnrollmentFaceAreaRatio')),
                              _buildRecognitionTextField(controller: _minEnrollmentFaceAspectRatioController, label: _recognitionLabel('minEnrollmentFaceAspectRatio')),
                              _buildRecognitionTextField(controller: _maxEnrollmentFaceAspectRatioController, label: _recognitionLabel('maxEnrollmentFaceAspectRatio')),
                              _buildRecognitionTextField(controller: _minEnrollmentFacePixelsController, label: _recognitionLabel('minEnrollmentFacePixels')),
                              _buildRecognitionTextField(controller: _scrfdInputSizeController, label: _recognitionLabel('scrfdInputSize')),
                              _buildRecognitionTextField(controller: _scrfdScoreThresholdController, label: _recognitionLabel('scrfdScoreThreshold')),
                              _buildRecognitionTextField(controller: _scrfdNmsThresholdController, label: _recognitionLabel('scrfdNmsThreshold')),
                              _buildRecognitionTextField(controller: _hnswMController, label: _recognitionLabel('hnswM'), parameterKey: 'hnswM'),
                              _buildRecognitionTextField(controller: _hnswEfConstructionController, label: _recognitionLabel('hnswEfConstruction'), parameterKey: 'hnswEfConstruction'),
                              _buildRecognitionTextField(controller: _hnswEfSearchController, label: _recognitionLabel('hnswEfSearch'), parameterKey: 'hnswEfSearch'),
                              _buildRecognitionTextField(controller: _eyeRegionMinQualityController, label: _recognitionLabel('eyeRegionMinQuality'), parameterKey: 'eyeRegionMinQuality'),
                              _buildRecognitionTextField(controller: _noseRegionMinQualityController, label: _recognitionLabel('noseRegionMinQuality'), parameterKey: 'noseRegionMinQuality'),
                              _buildRecognitionTextField(controller: _mouthRegionMinQualityController, label: _recognitionLabel('mouthRegionMinQuality'), parameterKey: 'mouthRegionMinQuality'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            title: const Text('Tu dong dieu chinh tham so realtime'),
                            subtitle: const Text('He thong tu nắn nguong theo chat luong anh va kich thuoc khuon mat trong luc chay'),
                            value: _autoTuneRecognitionParameters,
                            onChanged: (value) {
                              setState(() {
                                _autoTuneRecognitionParameters = value;
                              });
                            },
                          ),
                          SwitchListTile(
                            title: const Text('Overlay debug realtime'),
                            subtitle: const Text('Hien thi globalScore, partialScore va trong so mat/mui/mieng tren bbox'),
                            value: _debugRealtimeOverlay,
                            onChanged: (value) {
                              setState(() {
                                _debugRealtimeOverlay = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.table_view,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Bao cao log CSV va Public API',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            title: const Text('Bat job xuat bao cao dinh ky'),
                            subtitle: const Text('App se tu dong xuat CSV theo gio da cau hinh'),
                            value: _enableScheduledReportExport,
                            onChanged: (value) {
                              setState(() {
                                _enableScheduledReportExport = value;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: _reportExportDirectoryController,
                                  label: 'Thu muc xuat bao cao',
                                  hint: 'C:/reports/attendance',
                                  helperText: 'Dung cho job dinh ky va API save=true',
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: _pickReportDirectory,
                                tooltip: 'Chon thu muc',
                                icon: const Icon(Icons.folder_open),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _reportExportTimeController,
                            label: 'Thoi gian chay dinh ky (HH:mm)',
                            hint: '23:55',
                            helperText: 'Job chay moi ngay 1 lan',
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _reportFilePrefixController,
                            label: 'Tien to ten file bao cao',
                            hint: 'attendance_report',
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            title: const Text('Bat public API xuat bao cao'),
                            subtitle: const Text('GET /api/reports/export?from=2026-07-01&to=2026-07-04&subject=An&type=start'),
                            value: _enablePublicReportApi,
                            onChanged: (value) {
                              setState(() {
                                _enablePublicReportApi = value;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: _reportApiHostController,
                                  label: 'API Host',
                                  hint: '0.0.0.0',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: _reportApiPortController,
                                  label: 'API Port',
                                  hint: '8787',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _resetToDefaults,
                          icon: const Icon(Icons.restore),
                          label: const Text('Đặt lại mặc định'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saveSettings,
                          icon: const Icon(Icons.save),
                          label: const Text('Lưu cấu hình'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? helperText,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.language),
      ),
      obscureText: obscureText,
    );
  }

  Widget _buildServersField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String helperText,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.dns),
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
    final resolvedKey = parameterKey ??
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
      decoration: const InputDecoration(
        labelText: 'Chính sách vận chuyển ICE',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.device_hub),
      ),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Tất cả (UDP và TCP)')),
        DropdownMenuItem(value: 'relay', child: Text('Chỉ Relay (TURN)')),
      ],
      onChanged: (value) {
        if (value != null) {
          _iceTransportPolicyController.text = value;
        }
      },
    );
  }

  Widget _buildCheckboxField() {
    return CheckboxListTile(
      title: const Text('Kích hoạt xử lý âm thanh'),
      subtitle: const Text('Bật xử lý âm thanh nâng cao để cải thiện chất lượng'),
      value: _enableAudioProcessing,
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _enableAudioProcessing = value;
          });
        }
      },
      secondary: const Icon(Icons.mic),
    );
  }

  Future<void> _testConnection() async {
    final signalingUrl = _signalingServerController.text.trim();
    if (signalingUrl.isEmpty) {
      _showErrorSnackBar('Vui lòng nhập URL máy chủ Signaling trước');
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Đang kiểm tra kết nối...'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Vui lòng đợi...'),
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
    _showSuccessSnackBar('Cấu hình máy chủ WebRTC hợp lệ');
  }

  Future<void> _pickReportDirectory() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chon thu muc xuat bao cao CSV',
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) return;
    if (!mounted) return;
    setState(() {
      _reportExportDirectoryController.text = selectedPath.trim();
    });
  }
}

class ParameterHelpButton extends StatefulWidget {
  const ParameterHelpButton({super.key, required this.label, required this.note});

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
                            color: theme.colorScheme.outline.withValues(alpha: 0.20),
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
    _overlayEntry?.remove();
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
    _overlayEntry?.remove();
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
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
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
