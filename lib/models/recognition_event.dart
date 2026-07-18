class RecognitionEvent {
  RecognitionEvent({
    required this.id,
    required this.personName,
    required this.confidence,
    required this.isStranger,
    required this.createdAt,
    this.personId,
    this.cameraId,
    this.snapshotBase64 = '',
  });

  final String id;
  final String? personId;
  final String personName;
  final String? cameraId;
  final double confidence;
  final bool isStranger;
  final int createdAt;
  final String snapshotBase64;

  factory RecognitionEvent.fromMap(Map<String, dynamic> map) {
    return RecognitionEvent(
      id: map['id'].toString(),
      personId: map['person_id']?.toString(),
      personName: map['person_name'].toString(),
      cameraId: map['camera_id']?.toString(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      isStranger: (map['is_stranger'] as int?) == 1,
      createdAt: (map['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      snapshotBase64: map['snapshot_base64']?.toString() ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'person_id': personId,
      'person_name': personName,
      'camera_id': cameraId,
      'confidence': confidence,
      'is_stranger': isStranger ? 1 : 0,
      'created_at': createdAt,
      'snapshot_base64': snapshotBase64,
    };
  }
}