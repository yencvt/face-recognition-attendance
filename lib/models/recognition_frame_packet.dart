import 'dart:typed_data';

import 'package:flutter_cam/models/face_overlay_box.dart';
import 'package:flutter_cam/services/face_recognition_service.dart';

class RecognitionFramePacket {
  RecognitionFramePacket({
    required this.cameraId,
    required this.overlays,
    required this.createdAt,
    this.trackStats,
    this.workerStats,
    this.inputFps = 0,
    this.recognitionFps = 0,
    this.annotatedFrameJpeg,
    this.annotatedOverlayPng,
  });

  final String cameraId;
  final List<FaceOverlayBox> overlays;
  final int createdAt;
  final CameraTrackRuntimeStats? trackStats;
  final CameraWorkerRuntimeStats? workerStats;
  final double inputFps;
  final double recognitionFps;
  final Uint8List? annotatedFrameJpeg;
  final Uint8List? annotatedOverlayPng;
}