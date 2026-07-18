import 'package:flutter_cam/models/face_template.dart' as face_template;

class HnswNode {
  HnswNode({required this.template, required this.level})
    : neighborsByLevelFull = List<Set<int>>.generate(level + 1, (_) => <int>{}),
      neighborsByLevelEyes = List<Set<int>>.generate(level + 1, (_) => <int>{}),
      neighborsByLevelNose = List<Set<int>>.generate(level + 1, (_) => <int>{}),
      neighborsByLevelMouth = List<Set<int>>.generate(level + 1, (_) => <int>{});

  final face_template.FaceTemplate template;
  final int level;

  // graph cho từng loại vector
  final List<Set<int>> neighborsByLevelFull;
  final List<Set<int>> neighborsByLevelEyes;
  final List<Set<int>> neighborsByLevelNose;
  final List<Set<int>> neighborsByLevelMouth;
}