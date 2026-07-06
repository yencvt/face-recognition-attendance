import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/face_attendance_repository.dart';
import '../l10n/app_i18n.dart';
import '../services/auth_session_service.dart';
import '../services/camera_stream_service.dart';
import '../services/face_recognition_service.dart';
import '../services/report_export_service.dart';
import 'recognition_zone_editor_dialog.dart';
import 'settings_screen.dart';

class _DiscoveredCamera {
  _DiscoveredCamera({
    required this.name,
    required this.source,
    required this.endpoint,
  });

  final String name;
  final String source;
  final String endpoint;
}

enum _CameraInputMode { local, ip }

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final CameraStreamService _streamService = CameraStreamService.instance;
  final FaceRecognitionService _recognitionService =
      FaceRecognitionService.instance;

  StreamSubscription<CameraStreamSnapshot>? _streamSub;
  StreamSubscription<RecognitionFramePacket>? _frameSub;
  StreamSubscription<FaceRecognitionNotification>? _notiSub;

  CameraStreamSnapshot _snapshot = CameraStreamSnapshot(
    sessions: const [],
    selectedCameraId: '',
  );
  final List<RecognitionEvent> _logs = [];
  final Map<String, Uint8List> _personAvatarById = {};
  List<FaceOverlayBox> _liveOverlays = const [];
  Timer? _summaryRefreshTimer;
  Timer? _previewStatusRefreshTimer;
  final List<_DiscoveredCamera> _discovered = [];
  bool _isScanning = false;
  Uint8List? _liveOverlayPng;
  RecognitionZone? _zone;
  int? _lastFramePacketAtMs;
  int? _lastFrameReceivedAtMs;
  double _frameFps = 0.0;
  double _pipelineTotalFps = 0.0;
  int _pipelineInFlight = 0;
  int _pipelineMaxWorkers = 0;
  int _pipelineConfiguredWorkers = 0;
  bool _pipelineFallbackMode = false;
  bool _pipelineIsolatePreprocessingEnabled = true;
  Map<int, double> _workerFpsBySlot = const <int, double>{};
  bool _showPipelineMetricsBadge = false;

  int _total = 0;
  int _known = 0;
  int _stranger = 0;

  String get _selectedId => _snapshot.selectedCameraId;

  CameraStreamSession get _selected {
    if (_snapshot.sessions.isEmpty) {
      return CameraStreamSession(
        id: 'default',
        name: 'No camera',
        color: Colors.grey,
        source: 'none',
        endpoint: '',
        connectionState: CameraStreamConnectionState.disconnected,
        statusMessage: 'No camera configured',
      );
    }
    return _snapshot.sessions.firstWhere(
      (c) => c.id == _selectedId,
      orElse: () => _snapshot.sessions.first,
    );
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _ensureRecognitionForSelectedSafe({bool forceStart = false}) async {
    try {
      await _ensureRecognitionForSelected(forceStart: forceStart);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Khong khoi dong duoc nhan dien: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _bootstrap() async {
    _snapshot = _streamService.current;
    await _loadZone();
    await _refreshPersonAvatars();
    final sum = await FaceAttendanceRepository.getSummary();
    final events = await FaceAttendanceRepository.getRecentEvents(limit: 40);

    if (!mounted) return;
    setState(() {
      _total = sum['total'] ?? 0;
      _known = sum['known'] ?? 0;
      _stranger = sum['stranger'] ?? 0;
      _logs
        ..clear()
        ..addAll(events);
    });

    // Start recognition after rendering summary/logs so UI stays usable
    // even when camera processor startup fails.
    await _ensureRecognitionForSelectedSafe();

    _summaryRefreshTimer?.cancel();
    _summaryRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_refreshSummary());
    });

    _streamSub = _streamService.stream.listen((snapshot) {
      final previousSelectedId = _snapshot.selectedCameraId;
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
      });
      if (previousSelectedId != snapshot.selectedCameraId) {
        setState(() {
          _liveOverlayPng = null;
          _liveOverlays = const [];
          _pipelineTotalFps = 0.0;
          _pipelineInFlight = 0;
          _pipelineMaxWorkers = 0;
          _pipelineConfiguredWorkers = 0;
          _pipelineFallbackMode = false;
          _pipelineIsolatePreprocessingEnabled = true;
          _workerFpsBySlot = const <int, double>{};
          _showPipelineMetricsBadge = false;
        });
      }
      unawaited(_loadZone());
      unawaited(_ensureRecognitionForSelectedSafe());
    });

    _frameSub = _recognitionService.frameQueue.listen((packet) {
      if (!mounted) return;
      if (packet.cameraId == _selectedId) {
        _lastFrameReceivedAtMs = DateTime.now().millisecondsSinceEpoch;
        final previousFrameAt = _lastFramePacketAtMs;
        _lastFramePacketAtMs = packet.createdAt;
        if (previousFrameAt != null && packet.createdAt > previousFrameAt) {
          final deltaMs = packet.createdAt - previousFrameAt;
          if (deltaMs > 0) {
            final instantFps = 1000 / deltaMs;
            _frameFps = _frameFps == 0
                ? instantFps
                : (_frameFps * 0.85) + (instantFps * 0.15);
          }
        }
        if (packet.annotatedOverlayPng != null) {
          _liveOverlayPng = packet.annotatedOverlayPng;
        }
        _liveOverlays = packet.overlays;
        final metrics = packet.realtimeMetrics;
        if (metrics != null) {
          _pipelineTotalFps = metrics.totalFps;
          _pipelineInFlight = metrics.inFlight;
          _pipelineMaxWorkers = metrics.maxWorkers;
          _pipelineConfiguredWorkers = metrics.configuredMaxWorkers;
          _pipelineFallbackMode = metrics.fallbackMode;
            _pipelineIsolatePreprocessingEnabled =
              metrics.isolatePreprocessingEnabled;
          _workerFpsBySlot = metrics.workerFpsBySlot;
          _showPipelineMetricsBadge = true;
        } else {
          _pipelineTotalFps = 0.0;
          _pipelineInFlight = 0;
          _pipelineMaxWorkers = 0;
          _pipelineConfiguredWorkers = 0;
          _pipelineFallbackMode = false;
          _pipelineIsolatePreprocessingEnabled = true;
          _workerFpsBySlot = const <int, double>{};
          _showPipelineMetricsBadge = false;
        }
        setState(() {});
      }
    });

    _notiSub = _recognitionService.notificationQueue.listen((noti) {
      if (!mounted) return;
      setState(() {
        _logs.insert(0, noti.event);
        if (_logs.length > 60) {
          _logs.removeRange(60, _logs.length);
        }
      });
      unawaited(_refreshSummary());
    });

    _previewStatusRefreshTimer?.cancel();
    _previewStatusRefreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;
        setState(() {});
      },
    );
  }

  Future<void> _refreshSummary() async {
    final sum = await FaceAttendanceRepository.getSummary();
    if (!mounted) return;
    setState(() {
      _total = sum['total'] ?? 0;
      _known = sum['known'] ?? 0;
      _stranger = sum['stranger'] ?? 0;
    });
  }

  Future<void> _refreshPersonAvatars() async {
    final people = await FaceAttendanceRepository.getPeople();
    final next = <String, Uint8List>{};
    for (final person in people) {
      final encoded = person.imageBase64.trim();
      if (encoded.isEmpty) continue;
      try {
        next[person.id] = base64Decode(encoded);
      } catch (_) {
        continue;
      }
    }

    if (!mounted) return;
    setState(() {
      _personAvatarById
        ..clear()
        ..addAll(next);
    });
  }

  bool _isFrameStale() {
    final lastSeen = _lastFrameReceivedAtMs;
    if (lastSeen == null) return true;
    return DateTime.now().millisecondsSinceEpoch - lastSeen > 1400;
  }

  bool _shouldShowPreviewBadge(CameraStreamSession cam) {
    return _recognitionService.isRunning(cam.id) &&
        _liveOverlays.isNotEmpty &&
        !_isFrameStale();
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8.8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildPreviewInfoBadge(
    CameraStreamSession cam,
    String statusText,
    Color statusColor,
  ) {
    if (!_shouldShowPreviewBadge(cam)) {
      return const SizedBox.shrink();
    }

    final running = _recognitionService.isRunning(cam.id);
    final onColor = running ? Colors.lightGreenAccent : Colors.redAccent;
    final statsText = 'T $_total  N $_known  L $_stranger';
    final frameStateText = _formatFrameFps();

    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cam.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.6,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            _statusPill(running ? 'ON' : 'OFF', onColor),
            const SizedBox(width: 8),
            Text(
              frameStateText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 9.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statsText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 9.3,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: statusColor.withValues(alpha: 0.95),
                fontSize: 9.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadZone() async {
    if (_selectedId.isEmpty || _selectedId == 'default') {
      if (!mounted) return;
      setState(() => _zone = null);
      return;
    }

    final z = await FaceAttendanceRepository.getZoneByCameraId(_selectedId);
    if (!mounted) return;
    setState(() => _zone = z);
  }

  bool _shouldMirrorZoneEditor(CameraStreamSession session) {
    final endpoint = session.endpoint.trim().toLowerCase();
    final source = session.source.trim().toLowerCase();
    if (endpoint.contains('facing:user')) return true;
    if (source.contains('front')) return true;
    return false;
  }

  String _formatFrameFps() {
    if (_frameFps <= 0) return '0.0 fps';
    return '${_frameFps.toStringAsFixed(_frameFps >= 10 ? 0 : 1)} fps';
  }

  Widget _buildPipelineMetricsBadge(CameraStreamSession cam) {
    if (!_showPipelineMetricsBadge ||
        !_recognitionService.isRunning(cam.id) ||
        _isFrameStale()) {
      return const SizedBox.shrink();
    }

    final configuredWorkers = _pipelineConfiguredWorkers <= 0
        ? _pipelineMaxWorkers
        : _pipelineConfiguredWorkers;
    final totalText =
        'Total ${_pipelineTotalFps.toStringAsFixed(_pipelineTotalFps >= 10 ? 0 : 1)} fps';
    final modeText = _pipelineFallbackMode ? 'Mode: fallback' : 'Mode: stream';
    final isolateText = _pipelineIsolatePreprocessingEnabled
      ? 'Isolate: on'
      : 'Isolate: off';
    final workersText = 'Workers $_pipelineInFlight/$configuredWorkers';
    final flowText = _pipelineInFlight > 0 ? 'Processing' : 'Idle';
    final workerFpsEntries = _workerFpsBySlot.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    final workerFpsText = workerFpsEntries.isEmpty
        ? 'Worker fps: -'
        : 'Worker fps: ${workerFpsEntries.map((e) => 'W${e.key + 1}:${e.value.toStringAsFixed(e.value >= 10 ? 0 : 1)}').join(' | ')}';

    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              totalText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              modeText,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 9.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isolateText,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 9.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              workersText,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 9.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              workerFpsText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 8.8,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              flowText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 8.9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectCamera(String id) async {
    await _streamService.selectCamera(id);
    _liveOverlayPng = null;
    await _ensureRecognitionForSelected();
  }

  Future<void> _scan(StateSetter setDialogState) async {
    setDialogState(() {
      _isScanning = true;
      _discovered.clear();
    });

    try {
      final cameras = await availableCameras();
      final localDiscovered = cameras.asMap().entries
          .map((entry) {
            final index = entry.key;
            final camera = entry.value;
            final endpoint = switch (camera.lensDirection) {
              CameraLensDirection.front => 'facing:user',
              CameraLensDirection.back => 'facing:environment',
              CameraLensDirection.external => 'facing:external',
            };
            final source = 'local:${camera.lensDirection.name}';
            return _DiscoveredCamera(
              name: _friendlyCameraName(camera, index),
              source: source,
              endpoint: endpoint,
            );
          })
          .toList(growable: false);

      final lanDiscovered = await _scanLanIpCameras();
      final discovered = <_DiscoveredCamera>[
        ...localDiscovered,
        ...lanDiscovered,
      ];

      if (!mounted) return;
      setDialogState(() {
        _isScanning = false;
        _discovered
          ..clear()
          ..addAll(discovered);
      });
    } catch (e) {
      if (!mounted) return;
      setDialogState(() {
        _isScanning = false;
        _discovered.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scan camera that bai: $e')));
    }
  }

  Future<List<_DiscoveredCamera>> _scanLanIpCameras() async {
    final subnetPrefix = await _resolvePrivateSubnetPrefix();
    if (subnetPrefix == null) {
      return const <_DiscoveredCamera>[];
    }

    final hosts = List<String>.generate(80, (index) => '$subnetPrefix.${index + 2}');
    final found = <_DiscoveredCamera>[];
    const chunkSize = 16;

    for (var i = 0; i < hosts.length; i += chunkSize) {
      final chunk = hosts.sublist(i, (i + chunkSize).clamp(0, hosts.length));
      final result = await Future.wait(
        chunk.map(_probeLanCameraHost),
      );
      for (final item in result) {
        if (item != null) {
          found.add(item);
        }
      }
    }

    return found;
  }

  Future<String?> _resolvePrivateSubnetPrefix() async {
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );

    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (addr.isLoopback) continue;
        final raw = addr.address;
        if (!_isPrivateIpv4(raw)) continue;
        final parts = raw.split('.');
        if (parts.length != 4) continue;
        return '${parts[0]}.${parts[1]}.${parts[2]}';
      }
    }
    return null;
  }

  bool _isPrivateIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  Future<_DiscoveredCamera?> _probeLanCameraHost(String host) async {
    final ports = <int>[554, 8554, 8080, 80, 81];

    Future<bool> canConnect(int port) async {
      Socket? socket;
      try {
        socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 220),
        );
        return true;
      } catch (_) {
        return false;
      } finally {
        await socket?.close();
      }
    }

    final opened = <int>[];
    for (final port in ports) {
      if (await canConnect(port)) {
        opened.add(port);
      }
    }

    if (opened.isEmpty) {
      return null;
    }

    String endpoint;
    if (opened.contains(554)) {
      endpoint = 'rtsp://$host:554/stream';
    } else if (opened.contains(8554)) {
      endpoint = 'rtsp://$host:8554/stream';
    } else if (opened.contains(8080)) {
      endpoint = 'http://$host:8080/video';
    } else if (opened.contains(81)) {
      endpoint = 'http://$host:81/stream';
    } else {
      endpoint = 'http://$host/mjpeg';
    }

    return _DiscoveredCamera(
      name: 'Camera IP $host',
      source: 'ip-lan',
      endpoint: endpoint,
    );
  }

  void _autoConfigCamera({
    required TextEditingController nameController,
    required TextEditingController sourceController,
    required TextEditingController endpointController,
    required StateSetter setDialogState,
  }) {
    if (_discovered.isNotEmpty) {
      final first = _discovered.firstWhere(
        (camera) => camera.endpoint == 'facing:user',
        orElse: () => _discovered.first,
      );
      nameController.text = first.name;
      sourceController.text = first.source;
      endpointController.text = first.endpoint;
    } else {
      nameController.text = 'Default camera';
      sourceController.text = 'Auto config';
      endpointController.text = 'facing:user';
    }
    setDialogState(() {});
  }

  String _friendlyCameraName(CameraDescription camera, int index) {
    final raw = camera.name.trim();
    final lower = raw.toLowerCase();
    if (lower.contains('integrated') || lower.contains('built-in') ||
        lower.contains('internal') || lower.contains('laptop')) {
      return 'Camera laptop';
    }
    if (lower.contains('usb')) {
      return 'Camera USB ${index + 1}';
    }
    if (lower.contains('virtual') || lower.contains('obs') ||
        lower.contains('droidcam')) {
      return 'Camera ao ${index + 1}';
    }

    switch (camera.lensDirection) {
      case CameraLensDirection.front:
        return 'Camera laptop';
      case CameraLensDirection.back:
        return 'Camera local ${index + 1}';
      case CameraLensDirection.external:
        return 'Camera ngoai ${index + 1}';
    }
  }

  bool _isValidIpEndpoint(String value) {
    final endpoint = value.trim().toLowerCase();
    return endpoint.startsWith('rtsp://') ||
        endpoint.startsWith('http://') ||
        endpoint.startsWith('https://');
  }

  String _cameraConfigKey({
    required String source,
    required String endpoint,
  }) {
    return '${source.trim().toLowerCase()}|${endpoint.trim().toLowerCase()}';
  }

  bool _isDuplicateCameraConfig({
    required String source,
    required String endpoint,
    String? excludeId,
  }) {
    final incoming = _cameraConfigKey(source: source, endpoint: endpoint);
    for (final session in _snapshot.sessions) {
      if (excludeId != null && session.id == excludeId) continue;
      final existing = _cameraConfigKey(
        source: session.source,
        endpoint: session.endpoint,
      );
      if (incoming == existing) {
        return true;
      }
    }
    return false;
  }

  bool _isLocalSession(CameraStreamSession session) {
    final endpoint = session.endpoint.trim().toLowerCase();
    final source = session.source.trim().toLowerCase();
    return endpoint.startsWith('facing:') || source.startsWith('local:');
  }

  Future<void> _releaseLocalStreamBeforeRecognition(
    CameraStreamSession session,
  ) async {
    if (!_isLocalSession(session)) return;
    if (!session.isConnected) return;
    await _streamService.disconnect(session.id);
  }

  Future<void> _addCameraDialog() async {
    final nameController = TextEditingController();
    final sourceController = TextEditingController(text: 'Manual config');
    final endpointController = TextEditingController();
    var inputMode = _CameraInputMode.local;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Add camera',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _scan(setDialogState),
                        icon: const Icon(Icons.search),
                        label: const Text('Scan devices'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _autoConfigCamera(
                          nameController: nameController,
                          sourceController: sourceController,
                          endpointController: endpointController,
                          setDialogState: setDialogState,
                        ),
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('Auto config'),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<_CameraInputMode>(
                        segments: const [
                          ButtonSegment<_CameraInputMode>(
                            value: _CameraInputMode.local,
                            icon: Icon(Icons.videocam),
                            label: Text('Camera local'),
                          ),
                          ButtonSegment<_CameraInputMode>(
                            value: _CameraInputMode.ip,
                            icon: Icon(Icons.lan),
                            label: Text('Camera IP'),
                          ),
                        ],
                        selected: <_CameraInputMode>{inputMode},
                        onSelectionChanged: (selection) {
                          final selected = selection.first;
                          setDialogState(() {
                            inputMode = selected;
                            if (selected == _CameraInputMode.ip) {
                              sourceController.text = 'ip-camera';
                              if (nameController.text.trim().isEmpty ||
                                  nameController.text.trim() == 'Default camera') {
                                nameController.text = 'Camera IP';
                              }
                            } else if (_discovered.isNotEmpty) {
                              final first = _discovered.first;
                              sourceController.text = first.source;
                              endpointController.text = first.endpoint;
                              if (nameController.text.trim().isEmpty ||
                                  nameController.text.trim() == 'Camera IP') {
                                nameController.text = first.name;
                              }
                            }
                          });
                        },
                      ),
                      if (_isScanning)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (!_isScanning && _discovered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Chua tim thay camera. Bam Scan devices hoac dung Auto config.',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                      if (_discovered.isNotEmpty)
                        SizedBox(
                          height: 160,
                          child: ListView.builder(
                            itemCount: _discovered.length,
                            itemBuilder: (context, i) {
                              final d = _discovered[i];
                              return ListTile(
                                leading: const Icon(Icons.videocam),
                                title: Text(d.name),
                                subtitle: Text('${d.source} • ${d.endpoint}'),
                                trailing: TextButton(
                                  onPressed: () {
                                    if (inputMode == _CameraInputMode.ip) {
                                      return;
                                    }
                                    nameController.text = d.name;
                                    sourceController.text = d.source;
                                    endpointController.text = d.endpoint;
                                    setDialogState(() {});
                                  },
                                  child: const Text('Use'),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Camera name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: sourceController,
                        readOnly: inputMode == _CameraInputMode.ip,
                        decoration: const InputDecoration(
                          labelText: 'Source',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: endpointController,
                        decoration: InputDecoration(
                          labelText: inputMode == _CameraInputMode.ip
                              ? 'IP stream URL (rtsp/http/https)'
                              : 'Endpoint (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(this.context);
                            final name = nameController.text.trim();
                            if (name.isEmpty) return;

                            final endpoint = endpointController.text.trim();
                            final isIpMode = inputMode == _CameraInputMode.ip;
                            final source = isIpMode
                                ? 'ip-camera'
                                : sourceController.text.trim();
                            if (source.isEmpty) return;

                            if (_isDuplicateCameraConfig(
                              source: source,
                              endpoint: endpoint,
                            )) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Camera nay da duoc them. Khong the them trung cau hinh.'),
                                ),
                              );
                              return;
                            }

                            if (isIpMode && !_isValidIpEndpoint(endpoint)) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('URL camera IP khong hop le. Dung rtsp:// hoac http(s)://'),
                                ),
                              );
                              return;
                            }

                            final id = DateTime.now().microsecondsSinceEpoch
                                .toString();
                            final color = Colors.primaries[_snapshot
                                    .sessions
                                    .length %
                                Colors.primaries.length];
                            await _streamService.saveCamera({
                              'id': id,
                              'name': name,
                              'source': source,
                              'endpoint': endpoint,
                              'color': color.toARGB32().toString(),
                              'connection_state': 'disconnected',
                              'status_message': isIpMode
                                  ? 'Da luu cau hinh camera IP'
                                  : 'Da luu cau hinh camera local',
                            });
                            await _streamService.selectCamera(id);
                            if (!isIpMode) {
                              await _ensureRecognitionForSelectedSafe(
                                forceStart: true,
                              );
                            }
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Save and start stream'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    sourceController.dispose();
    endpointController.dispose();
  }

  Future<void> _toggleSelectedConnection() async {
    final selected = _selected;
    if (selected.id == 'default') return;

    if (_recognitionService.isRunning(selected.id)) {
      await _recognitionService.stopProcessor(selected.id);
    } else {
      await _ensureRecognitionForSelected(forceStart: true);
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleCameraRecognition(String cameraId) async {
    if (cameraId == 'default') return;
    if (_recognitionService.isRunning(cameraId)) {
      await _recognitionService.stopProcessor(cameraId);
    } else {
      final session = _snapshot.sessions.firstWhere(
        (s) => s.id == cameraId,
        orElse: () => _selected,
      );
      await _releaseLocalStreamBeforeRecognition(session);
      final selectedIndex = _snapshot.sessions.indexWhere((s) => s.id == cameraId);
      final cameraIndex = selectedIndex >= 0 ? selectedIndex : 0;
      await _recognitionService.ensureProcessorForCamera(
        cameraId,
        preferredDeviceIndex: cameraIndex,
      );
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _editCameraConfigDialog(CameraStreamSession session) async {
    final nameController = TextEditingController(text: session.name);
    final sourceController = TextEditingController(text: session.source);
    final endpointController = TextEditingController(text: session.endpoint);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cap nhat cau hinh camera'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Camera name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sourceController,
                  decoration: const InputDecoration(
                    labelText: 'Source',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: endpointController,
                  decoration: const InputDecoration(
                    labelText: 'Endpoint',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Huy'),
            ),
            FilledButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(this.context);
                final name = nameController.text.trim();
                final source = sourceController.text.trim();
                final endpoint = endpointController.text.trim();
                if (name.isEmpty || source.isEmpty) return;

                if (_isDuplicateCameraConfig(
                  source: source,
                  endpoint: endpoint,
                  excludeId: session.id,
                )) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Da ton tai camera khac co cung source/endpoint.'),
                    ),
                  );
                  return;
                }

                final wasRunning = _recognitionService.isRunning(session.id);
                if (wasRunning) {
                  await _recognitionService.stopProcessor(session.id);
                }

                await _streamService.updateCamera({
                  'id': session.id,
                  'name': name,
                  'source': source,
                  'endpoint': endpoint,
                  'color': session.color.toARGB32().toString(),
                  'connection_state': cameraStreamConnectionStateValue(
                    session.connectionState,
                  ),
                  'status_message': session.statusMessage,
                });

                if (wasRunning) {
                  final updated = _snapshot.sessions.firstWhere(
                    (s) => s.id == session.id,
                    orElse: () => session,
                  );
                  await _releaseLocalStreamBeforeRecognition(updated);
                  await _toggleCameraRecognition(session.id);
                }

                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Luu'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    sourceController.dispose();
    endpointController.dispose();
  }

  Future<void> _deleteCameraWithConfirm(CameraStreamSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Xoa camera'),
          content: Text('Ban co chac muon xoa "${session.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Huy'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Xoa'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (_recognitionService.isRunning(session.id)) {
      await _recognitionService.stopProcessor(session.id);
    }
    await _streamService.deleteCamera(session.id);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _ensureRecognitionForSelected({bool forceStart = false}) async {
    final selected = _selected;
    if (selected.id == 'default') {
      return;
    }
    if (!forceStart && _recognitionService.isRunning(selected.id)) {
      return;
    }

    await _releaseLocalStreamBeforeRecognition(selected);

    final selectedIndex = _snapshot.sessions.indexWhere(
      (s) => s.id == selected.id,
    );
    final cameraIndex = (selectedIndex >= 0 ? selectedIndex : 0);

    await _recognitionService.ensureProcessorForCamera(
      selected.id,
      preferredDeviceIndex: cameraIndex,
    );

    if (!mounted) return;
    setState(() {});
  }

  (String, Color) _cameraStatusView(CameraStreamSession session) {
    final running = _recognitionService.isRunning(session.id);
    if (running) {
      return ('Nhan dien dang bat', Colors.green.shade700);
    }

    if (_isLocalSession(session)) {
      return ('Nhan dien dang tat', Colors.orange.shade700);
    }

    switch (session.connectionState) {
      case CameraStreamConnectionState.connected:
        return ('Stream connected', Colors.green.shade700);
      case CameraStreamConnectionState.connecting:
        return ('Dang ket noi stream', Colors.blue.shade700);
      case CameraStreamConnectionState.failed:
        return ('Ket noi that bai', Colors.red.shade700);
      case CameraStreamConnectionState.disconnected:
        return ('Stream disconnected', Colors.red.shade700);
    }
  }

  Future<void> _openZoneConfig() async {
    final selected = _selected;
    if (selected.id == 'default') return;

    var selectedForPreview = _snapshot.sessions.firstWhere(
      (session) => session.id == selected.id,
      orElse: () => selected,
    );
    var previewController = selected.id == 'default'
        ? null
        : _recognitionService.previewControllerFor(selected.id);
    var hasActivePreview =
        previewController != null && previewController.value.isInitialized;
    hasActivePreview =
        hasActivePreview ||
        (selectedForPreview.renderer != null &&
            selectedForPreview.renderer!.renderVideo);

    final wasRunning = _recognitionService.isRunning(selected.id);
    var previewConnectedTemporarily = false;

    if (!hasActivePreview) {
      if (_isLocalSession(selected)) {
        await _ensureRecognitionForSelected(forceStart: true);
      } else if (!selectedForPreview.isConnected) {
        await _streamService.connect(selected.id);
        previewConnectedTemporarily = true;
      }

      selectedForPreview = _snapshot.sessions.firstWhere(
        (session) => session.id == selected.id,
        orElse: () => selected,
      );
      previewController = selected.id == 'default'
          ? null
          : _recognitionService.previewControllerFor(selected.id);
    }

    if (!mounted) return;

    try {
      final current = _zone ?? RecognitionZone.defaults(cameraId: selected.id);
      final updated = await showDialog<RecognitionZone>(
        context: context,
        builder: (_) => RecognitionZoneEditorDialog(
          zone: current,
          cameraName: selectedForPreview.name,
          renderer: selectedForPreview.renderer,
          cameraController: previewController,
          mirrorHorizontally: _shouldMirrorZoneEditor(selectedForPreview),
        ),
      );

      if (updated == null) return;
      await FaceAttendanceRepository.saveZone(updated);
      _recognitionService.invalidateZoneCache(selected.id);
      await _recognitionService.refreshTemplates();
      if (!mounted) return;
      setState(() => _zone = updated);
    } finally {
      if (previewConnectedTemporarily) {
        await _streamService.disconnect(selected.id);
      }
      if (wasRunning && !_recognitionService.isRunning(selected.id)) {
        await _ensureRecognitionForSelected(forceStart: true);
      }
    }
  }

  Uint8List? _decodeSnapshot(String encoded) {
    if (encoded.trim().isEmpty) return null;
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  Widget _buildLogTile(RecognitionEvent event) {
    final avatar = event.personId == null
        ? null
        : _personAvatarById[event.personId!];
    final snapshot = _decodeSnapshot(event.snapshotBase64);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: avatar != null
          ? CircleAvatar(
              radius: 22,
              backgroundImage: MemoryImage(avatar),
              backgroundColor: Colors.grey.shade200,
            )
          : CircleAvatar(
              radius: 22,
              backgroundColor: event.isStranger
                  ? Colors.orange.shade100
                  : Colors.green.shade100,
              child: Icon(
                event.isStranger ? Icons.person_off : Icons.verified_user,
                size: 18,
              ),
            ),
      title: Text(event.personName),
      subtitle: Text(
        '${event.isStranger ? 'Nguoi la' : 'Do tin cay ${(event.confidence * 100).toStringAsFixed(0)}%'} • '
        '${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(event.createdAt)).format(context)}',
      ),
      trailing: snapshot != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                snapshot,
                width: 66,
                height: 48,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            )
          : Container(
              width: 66,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 18,
                color: Colors.grey.shade600,
              ),
            ),
    );
  }

  Widget _buildRealtimeLogsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            title: const Text('Log realtime (tat ca)'),
            subtitle: Text('So ban ghi: ${_logs.length}'),
            trailing: const Icon(Icons.bolt),
          ),
          const Divider(height: 1),
          Expanded(
            child: _logs.isEmpty
                ? const Center(child: Text('Chua co log realtime.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _logs.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 8),
                    itemBuilder: (context, index) => _buildLogTile(_logs[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLogTile(RecognitionEvent event) {
    final avatar = event.personId == null
        ? null
        : _personAvatarById[event.personId!];
    final snapshot = _decodeSnapshot(event.snapshotBase64);
    final statusText = event.isStranger
        ? 'Nguoi la'
        : 'Tin cay ${(event.confidence * 100).toStringAsFixed(0)}%';
    final timeText = TimeOfDay.fromDateTime(
      DateTime.fromMillisecondsSinceEpoch(event.createdAt),
    ).format(context);

    return ListTile(
      dense: true,
      minLeadingWidth: 0,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      leading: avatar != null
          ? CircleAvatar(
              radius: 14,
              backgroundImage: MemoryImage(avatar),
              backgroundColor: Colors.grey.shade200,
            )
          : CircleAvatar(
              radius: 14,
              backgroundColor: event.isStranger
                  ? Colors.orange.shade100
                  : Colors.green.shade100,
              child: Icon(
                event.isStranger ? Icons.person_off : Icons.verified_user,
                size: 12,
              ),
            ),
      title: Text(
        event.personName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.6, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '$statusText • $timeText',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.2, color: Colors.grey.shade700),
      ),
      trailing: snapshot == null
          ? const SizedBox.shrink()
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                snapshot,
                width: 44,
                height: 32,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
    );
  }

  List<Widget> _buildRealtimeTextLabels(
    BoxConstraints constraints,
    bool mirror,
  ) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    if (width <= 0 || height <= 0) {
      return const [];
    }

    return _liveOverlays.expand((overlay) {
      var ratio = overlay.rectRatio;
      if (mirror) {
        ratio = Rect.fromLTWH(
          (1 - ratio.right).clamp(0.0, 1.0),
          ratio.top,
          ratio.width,
          ratio.height,
        );
      }

      final left = (ratio.left * width).clamp(0.0, width - 1.0);
      final top = (ratio.top * height - 22).clamp(0.0, height - 22.0);
      final isStranger = overlay.event.isStranger;
      final color = isStranger ? Colors.orangeAccent : Colors.lightGreenAccent;
      final label =
          '${overlay.event.personName} ${(overlay.event.confidence * 100).toStringAsFixed(0)}%';
      final debugLabel = overlay.debugLabel;
      final maxLabelWidth = (width * 0.40).clamp(120.0, 260.0);
      final clampedLeft = left.clamp(0.0, (width - maxLabelWidth).clamp(0.0, width));
      final debugTop = (ratio.bottom * height + 4).clamp(0.0, height - 18.0);

      final widgets = <Widget>[
        Positioned(
          left: clampedLeft,
          top: top,
          child: IgnorePointer(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxLabelWidth),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withValues(alpha: 0.75)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ];

      if (debugLabel != null && debugLabel.isNotEmpty) {
        widgets.add(
          Positioned(
            left: clampedLeft,
            top: debugTop,
            child: IgnorePointer(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                child: Text(
                  debugLabel,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.92),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );
      }

      return widgets;
    }).toList(growable: false);
  }

  Widget _preview() {
    final cam = _selected;
    final status = _cameraStatusView(cam);
    final CameraController? previewController = cam.id == 'default'
        ? null
        : _recognitionService.previewControllerFor(cam.id);

    if (previewController != null && previewController.value.isInitialized) {
      final aspectRatio = previewController.value.aspectRatio;
      final shouldMirrorOverlay =
          previewController.description.lensDirection ==
          CameraLensDirection.front;
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(previewController),
                      if (_liveOverlayPng != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Transform(
                              alignment: Alignment.center,
                              transform: shouldMirrorOverlay
                                  ? Matrix4.diagonal3Values(-1.0, 1.0, 1.0)
                                  : Matrix4.identity(),
                              child: Image.memory(
                                _liveOverlayPng!,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.none,
                              ),
                            ),
                          ),
                        ),
                      ..._buildRealtimeTextLabels(
                        constraints,
                        shouldMirrorOverlay,
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _buildPipelineMetricsBadge(cam),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _buildPreviewInfoBadge(cam, status.$1, status.$2),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [cam.color, Colors.black87],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.videocam, color: Colors.white, size: 34),
            const SizedBox(height: 10),
            Text(
              cam.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              status.$1,
              style: TextStyle(color: status.$2.withValues(alpha: 0.95)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _frameSub?.cancel();
    _notiSub?.cancel();
    _summaryRefreshTimer?.cancel();
    _previewStatusRefreshTimer?.cancel();
    unawaited(_recognitionService.stopAllProcessors());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final selected = _selected;
    final wide = MediaQuery.of(context).size.width > 1100;
    final compactTopBar = MediaQuery.of(context).size.width < 1280;
    final auth = AuthSessionService.instance;
    final currentUser = auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          i18n.t('attendance.title'),
        ),
        actions: [
          _buildLanguageSelector(context),
          IconButton(
            onPressed: _addCameraDialog,
            icon: const Icon(Icons.add_link),
            tooltip: i18n.t('attendance.addCamera'),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings),
            tooltip: i18n.t('attendance.systemConfig'),
          ),
          if (currentUser != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: compactTopBar ? 120 : 220,
                    ),
                    child: Text(
                      compactTopBar
                          ? currentUser.username
                          : '${currentUser.username} • ${currentUser.isAdmin ? i18n.t('role.admin') : i18n.t('role.user')}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: auth.isAuthenticated ? auth.logout : null,
            icon: const Icon(Icons.logout),
            tooltip: i18n.t('attendance.logout'),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF4F8FF), Color(0xFFEAF1FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                                  Expanded(flex: 4, child: _preview()),
                                  const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                if (_snapshot.sessions.isNotEmpty)
                                  FilledButton.tonalIcon(
                                    onPressed: _toggleSelectedConnection,
                                    icon: Icon(
                                      _recognitionService.isRunning(selected.id)
                                          ? Icons.pause_circle
                                          : Icons.play_circle,
                                    ),
                                    label: Text(
                                      _recognitionService.isRunning(selected.id)
                                          ? 'Dung nhan dien'
                                          : 'Bat nhan dien',
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                FilledButton.tonalIcon(
                                  onPressed: _openZoneConfig,
                                  icon: const Icon(Icons.tune),
                                  label: const Text('Vung nhan dien'),
                                ),
                                const Spacer(),
                                Text(
                                  _recognitionService.isRunning(selected.id)
                                      ? 'MediaPipe + ArcFace ON'
                                      : 'MediaPipe + ArcFace OFF',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            flex: 3,
                            child: _DailyLogsCard(
                              itemBuilder: _buildCompactLogTile,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 390,
                      child: Column(
                        children: [
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: SizedBox(
                              height: 210,
                              child: ListView.builder(
                                itemCount: _snapshot.sessions.length,
                                itemBuilder: (context, i) {
                                  final c = _snapshot.sessions[i];
                                  final running = _recognitionService.isRunning(c.id);
                                  final status = _cameraStatusView(c);
                                  return ListTile(
                                    selected: c.id == _selectedId,
                                    onTap: () => _selectCamera(c.id),
                                    title: Text(c.name),
                                    subtitle: Text(status.$1, style: TextStyle(color: status.$2)),
                                    leading: CircleAvatar(
                                      backgroundColor: c.color,
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) async {
                                        if (value == 'toggle') {
                                          await _toggleCameraRecognition(c.id);
                                        } else if (value == 'edit') {
                                          await _editCameraConfigDialog(c);
                                        } else if (value == 'delete') {
                                          await _deleteCameraWithConfirm(c);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'toggle',
                                          child: Text(running ? 'Tat nhan dien' : 'Bat nhan dien'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Cap nhat cau hinh'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Xoa camera'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(child: _buildRealtimeLogsCard()),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                      Expanded(flex: 3, child: _preview()),
                      const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_snapshot.sessions.isNotEmpty)
                            FilledButton.tonalIcon(
                              onPressed: _toggleSelectedConnection,
                              icon: Icon(
                                selected.isConnected
                                    ? Icons.link_off
                                    : Icons.link,
                              ),
                              label: Text(
                                selected.isConnected ? 'Disconnect' : 'Connect',
                              ),
                            ),
                          FilledButton.tonalIcon(
                            onPressed: _openZoneConfig,
                            icon: const Icon(Icons.tune),
                            label: const Text('Vung nhan dien'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 2,
                      child: _DailyLogsCard(
                        itemBuilder: _buildCompactLogTile,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(flex: 2, child: _buildRealtimeLogsCard()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector(BuildContext context) {
    final i18n = AppI18n.of(context);
    final current = AppI18nController.localeNotifier.value.languageCode;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Center(
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.55),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromARGB(18, 0, 0, 0),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: current,
              isDense: true,
              itemHeight: kMinInteractiveDimension,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              style: Theme.of(context).textTheme.labelMedium,
              items: [
                DropdownMenuItem(
                  value: 'vi',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🇻🇳'),
                      const SizedBox(width: 6),
                      Text(i18n.t('language.vi')),
                    ],
                  ),
                ),
                DropdownMenuItem(
                  value: 'en',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🇺🇸'),
                      const SizedBox(width: 6),
                      Text(i18n.t('language.en')),
                    ],
                  ),
                ),
              ],
              selectedItemBuilder: (context) => [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🇻🇳'),
                    const SizedBox(width: 4),
                    Text(
                      'VI',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🇺🇸'),
                    const SizedBox(width: 4),
                    Text(
                      'EN',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                AppI18nController.setLocaleCode(value);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyLogsCard extends StatefulWidget {
  const _DailyLogsCard({required this.itemBuilder});

  final Widget Function(RecognitionEvent event) itemBuilder;

  @override
  State<_DailyLogsCard> createState() => _DailyLogsCardState();
}

class _DailyLogsCardState extends State<_DailyLogsCard> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _query = '';
  List<RecognitionEvent> _logs = const [];
  bool _loading = true;
  bool _isExporting = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_loadLogs());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d/$m/$y';
  }

  String _formatRangeLabel() {
    return '${_formatDate(_startDate)} - ${_formatDate(_endDate)}';
  }

  List<RecognitionEvent> get _filteredLogs {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _logs;
    return _logs
        .where((event) => event.personName.toLowerCase().contains(query))
        .toList(growable: false);
  }

  Future<void> _loadLogs() async {
    final logs = await FaceAttendanceRepository.getEventsBetweenDates(
      startDate: _startDate,
      endDate: _endDate,
    );
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked == null) return;

    setState(() {
      _startDate = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _loadLogs();
  }

  Future<void> _exportCsv() async {
    if (_isExporting) return;
    setState(() {
      _isExporting = true;
    });

    try {
      final selectedDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Chon thu muc de xuat CSV theo khoang ngay',
      );
      if (!mounted) return;
      if (selectedDir == null || selectedDir.trim().isEmpty) {
        return;
      }

      final outputPath = await ReportExportService.instance.exportCsvByFilter(
        fromDate: _startDate,
        toDate: _endDate.add(const Duration(days: 1)),
        outputDirectory: selectedDir.trim(),
        fileName:
            'attendance_range_${_startDate.year.toString().padLeft(4, '0')}${_startDate.month.toString().padLeft(2, '0')}${_startDate.day.toString().padLeft(2, '0')}_${_endDate.year.toString().padLeft(4, '0')}${_endDate.month.toString().padLeft(2, '0')}${_endDate.day.toString().padLeft(2, '0')}.csv',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Da xuat CSV: $outputPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Xuat CSV that bai: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _filteredLogs;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            title: const Text('Log cham cong (luu DB)'),
            subtitle: Text(
              'Tu ${_formatRangeLabel()} - ${filteredLogs.length}/${_logs.length} ban ghi',
            ),
            trailing: Wrap(
              spacing: 6,
              children: [
                IconButton(
                  onPressed: _pickRange,
                  tooltip: 'Chon khoang ngay',
                  icon: const Icon(Icons.date_range),
                ),
                IconButton(
                  onPressed: _loadLogs,
                  tooltip: 'Lam moi',
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  onPressed: _isExporting ? null : _exportCsv,
                  tooltip: 'Xuat CSV theo khoang ngay',
                  icon: _isExporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_for_offline),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Tim theo ten nguoi',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          setState(() {
                            _query = '';
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filteredLogs.isEmpty
                    ? const Center(
                        child: Text('Khong co log trong khoang ngay da chon.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        itemCount: filteredLogs.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 3),
                        itemBuilder: (context, index) =>
                            widget.itemBuilder(filteredLogs[index]),
                      ),
          ),
        ],
      ),
    );
  }
}
