import 'dart:ui';

import 'package:flutter_cam/models/recognition_event.dart';

class FaceOverlayBox {
  FaceOverlayBox({
    required this.trackKey,
    required this.rectRatio,
    required this.event,
    this.debugLabel,
  });

  final String trackKey;
  final Rect rectRatio;
  final RecognitionEvent event;
  final String? debugLabel;
}