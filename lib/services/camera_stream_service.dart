import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../database/app_database.dart';

enum CameraStreamConnectionState { disconnected, connecting, connected, failed }

CameraStreamConnectionState parseCameraStreamConnectionState(String? value) {
  switch (value) {
    case 'connected':
      return CameraStreamConnectionState.connected;
    case 'connecting':
      return CameraStreamConnectionState.connecting;
    case 'failed':
      return CameraStreamConnectionState.failed;
    default:
      return CameraStreamConnectionState.disconnected;
  }
}

String cameraStreamConnectionStateValue(CameraStreamConnectionState state) {
  switch (state) {
    case CameraStreamConnectionState.connected:
      return 'connected';
    case CameraStreamConnectionState.connecting:
      return 'connecting';
    case CameraStreamConnectionState.failed:
      return 'failed';
    case CameraStreamConnectionState.disconnected:
      return 'disconnected';
  }
}

class CameraStreamSession {
  CameraStreamSession({
    required this.id,
    required this.name,
    required this.color,
    required this.source,
    required this.endpoint,
    required this.connectionState,
    required this.statusMessage,
    this.autoStart = false,
    this.mediaStream,
    this.renderer,
  });

  final String id;
  String name;
  Color color;
  String source;
  String endpoint;
  CameraStreamConnectionState connectionState;
  String statusMessage;
  bool autoStart;
  MediaStream? mediaStream;
  RTCVideoRenderer? renderer;

  bool get isConnected => connectionState == CameraStreamConnectionState.connected;
}

class CameraStreamSnapshot {
  CameraStreamSnapshot({required this.sessions, required this.selectedCameraId});

  final List<CameraStreamSession> sessions;
  final String selectedCameraId;
}

class CameraStreamService {
  CameraStreamService._();

  static final CameraStreamService instance = CameraStreamService._();

  final Map<String, CameraStreamSession> _sessionsById = {};
  final StreamController<CameraStreamSnapshot> _controller = StreamController<CameraStreamSnapshot>.broadcast();

  bool _initialized = false;
  String _selectedCameraId = '';

  Stream<CameraStreamSnapshot> get stream => _controller.stream;

  CameraStreamSnapshot get current => CameraStreamSnapshot(
        sessions: _sessionsById.values.toList(growable: false),
        selectedCameraId: _selectedCameraId,
      );

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await reloadFromDatabase();
    await _connectAutoStartSessions();
    _emit();
  }

  Future<void> reloadFromDatabase() async {
    final rows = await AppDatabase.getCameras();
    final selectedId = await AppDatabase.getSelectedCameraId();

    final incomingIds = <String>{};
    for (final r in rows) {
      final id = r['id'].toString();
      incomingIds.add(id);

      final existing = _sessionsById[id];
      final state = parseCameraStreamConnectionState(r['connection_state']?.toString());
      final session = existing ??
          CameraStreamSession(
            id: id,
            name: r['name'].toString(),
            color: Color(int.parse(r['color'].toString())),
            source: r['source'].toString(),
            endpoint: r['endpoint']?.toString() ?? '',
            connectionState: state,
            statusMessage: r['status_message']?.toString() ?? 'Waiting for connection',
            autoStart: state == CameraStreamConnectionState.connected,
          );

      session.name = r['name'].toString();
      session.color = Color(int.parse(r['color'].toString()));
      session.source = r['source'].toString();
      session.endpoint = r['endpoint']?.toString() ?? '';
      session.autoStart = state == CameraStreamConnectionState.connected || session.autoStart;
      if (!session.isConnected) {
        session.connectionState = state;
      }
      session.statusMessage = r['status_message']?.toString() ?? session.statusMessage;

      _sessionsById[id] = session;
    }

    final removedIds = _sessionsById.keys.where((id) => !incomingIds.contains(id)).toList(growable: false);
    for (final id in removedIds) {
      final removed = _sessionsById.remove(id);
      if (removed != null) {
        await _disposeSessionMedia(removed);
      }
    }

    if (_sessionsById.isEmpty) {
      _selectedCameraId = '';
    } else if (selectedId != null && _sessionsById.containsKey(selectedId)) {
      _selectedCameraId = selectedId;
    } else if (!_sessionsById.containsKey(_selectedCameraId)) {
      _selectedCameraId = _sessionsById.keys.first;
    }

    _emit();
  }

  Future<void> selectCamera(String id) async {
    if (!_sessionsById.containsKey(id)) return;
    _selectedCameraId = id;
    await AppDatabase.saveSelectedCameraId(id);
    _emit();
  }

  Future<void> toggleCamera(String id) async {
    final session = _sessionsById[id];
    if (session == null) return;
    if (session.isConnected) {
      await disconnect(id);
    } else {
      await connect(id, markAutoStart: true);
    }
  }

  Future<void> connect(String id, {bool markAutoStart = false}) async {
    final session = _sessionsById[id];
    if (session == null) return;
    if (session.connectionState == CameraStreamConnectionState.connecting) return;

    session.connectionState = CameraStreamConnectionState.connecting;
    session.statusMessage = 'Connecting via WebRTC';
    _emit();
    await _persistSession(session);

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        throw Exception('Camera permission denied');
      }

      session.renderer ??= RTCVideoRenderer();
      if (session.renderer!.textureId == null) {
        await session.renderer!.initialize();
      }

      final stream = await navigator.mediaDevices.getUserMedia(
        _buildMediaConstraints(session.endpoint),
      );

      session.mediaStream = stream;
      session.renderer!.srcObject = stream;
      session.connectionState = CameraStreamConnectionState.connected;
      session.statusMessage = 'WebRTC stream active';
      if (markAutoStart) {
        session.autoStart = true;
      }

      _emit();
      await _persistSession(session);
    } catch (e) {
      await _disposeSessionMedia(session);
      session.connectionState = CameraStreamConnectionState.failed;
      session.statusMessage = 'Unable to stream: $e';
      _emit();
      await _persistSession(session);
    }
  }

  Future<void> disconnect(String id) async {
    final session = _sessionsById[id];
    if (session == null) return;

    await _disposeSessionMedia(session);
    session.connectionState = CameraStreamConnectionState.disconnected;
    session.statusMessage = 'Disconnected';
    session.autoStart = false;
    _emit();
    await _persistSession(session);
  }

  Future<void> saveCamera(Map<String, dynamic> cameraData) async {
    await AppDatabase.saveCamera(cameraData);
    await reloadFromDatabase();
  }

  Future<void> updateCamera(Map<String, dynamic> cameraData) async {
    await AppDatabase.updateCamera(cameraData);
    await reloadFromDatabase();
  }

  Future<void> deleteCamera(String id) async {
    await disconnect(id);
    await AppDatabase.deleteCamera(id);
    _sessionsById.remove(id);
    if (_selectedCameraId == id) {
      _selectedCameraId = _sessionsById.isNotEmpty ? _sessionsById.keys.first : '';
      if (_selectedCameraId.isNotEmpty) {
        await AppDatabase.saveSelectedCameraId(_selectedCameraId);
      }
    }
    _emit();
  }

  Future<void> _connectAutoStartSessions() async {
    for (final session in _sessionsById.values) {
      if (session.autoStart) {
        await connect(session.id);
      }
    }
  }

  Future<void> _disposeSessionMedia(CameraStreamSession session) async {
    session.mediaStream?.getTracks().forEach((track) => track.stop());
    await session.mediaStream?.dispose();
    session.mediaStream = null;

    if (session.renderer != null) {
      session.renderer!.srcObject = null;
      await session.renderer!.dispose();
      session.renderer = null;
    }
  }

  Future<void> _persistSession(CameraStreamSession session) async {
    await AppDatabase.updateCamera({
      'id': session.id,
      'name': session.name,
      'source': session.source,
      'endpoint': session.endpoint,
      'color': session.color.toARGB32().toString(),
      'connection_state': cameraStreamConnectionStateValue(session.connectionState),
      'status_message': session.statusMessage,
    });
  }

  Map<String, dynamic> _buildMediaConstraints(String endpoint) {
    final trimmed = endpoint.trim();
    if (trimmed.startsWith('facing:')) {
      final facing = trimmed.substring('facing:'.length).trim();
      if (facing.isNotEmpty) {
        return {
          'audio': false,
          'video': {'facingMode': facing},
        };
      }
    }

    if (trimmed.startsWith('source:')) {
      final sourceId = trimmed.substring('source:'.length).trim();
      if (sourceId.isNotEmpty) {
        return {
          'audio': false,
          'video': {
            'optional': [
              {'sourceId': sourceId},
            ],
          },
        };
      }
    }

    return {
      'audio': false,
      'video': {'facingMode': 'user'},
    };
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(
      CameraStreamSnapshot(
        sessions: _sessionsById.values.toList(growable: false),
        selectedCameraId: _selectedCameraId,
      ),
    );
  }

  Future<void> dispose() async {
    for (final session in _sessionsById.values) {
      await _disposeSessionMedia(session);
    }
    _sessionsById.clear();
    await _controller.close();
  }
}
