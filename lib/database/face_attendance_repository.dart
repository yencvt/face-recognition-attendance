import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';

class FacePerson {
  FacePerson({
    required this.id,
    required this.name,
    required this.createdAt,
    this.employeeCode = '',
    this.department = '',
    this.notes = '',
    this.imageBase64 = '',
    this.imageCropBase64 = '',
  });

  final String id;
  final String name;
  final String employeeCode;
  final String department;
  final String notes;
  final String imageBase64;
  final String imageCropBase64;
  final int createdAt;

  factory FacePerson.fromMap(Map<String, dynamic> map) {
    return FacePerson(
      id: map['id'].toString(),
      name: map['name'].toString(),
      employeeCode: map['employee_code']?.toString() ?? '',
      department: map['department']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      imageBase64: map['image_base64']?.toString() ?? '',
      imageCropBase64: map['image_crop_base64']?.toString() ?? '',
      createdAt: (map['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'employee_code': employeeCode,
      'department': department,
      'notes': notes,
      'image_base64': imageBase64,
      'image_crop_base64': imageCropBase64,
      'created_at': createdAt,
    };
  }
}

class FacePersonImage {
  FacePersonImage({
    required this.id,
    required this.personId,
    required this.imageBase64,
    required this.createdAt,
    this.imageCropBase64 = '',
  });

  final String id;
  final String personId;
  final String imageBase64;
  final String imageCropBase64;
  final int createdAt;

  factory FacePersonImage.fromMap(Map<String, dynamic> map) {
    return FacePersonImage(
      id: map['id'].toString(),
      personId: map['person_id'].toString(),
      imageBase64: map['image_base64']?.toString() ?? '',
      imageCropBase64: map['image_crop_base64']?.toString() ?? '',
      createdAt: (map['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'person_id': personId,
      'image_base64': imageBase64,
      'image_crop_base64': imageCropBase64,
      'created_at': createdAt,
    };
  }
}

class FaceVectorCacheEntry {
  FaceVectorCacheEntry({
    required this.sourceId,
    required this.personId,
    required this.sourceType,
    required this.vectorBlob,
    required this.quality,
    required this.createdAt,
    required this.updatedAt,
    this.eyeVectorBlob,
    this.noseVectorBlob,
    this.mouthVectorBlob,
    this.foreheadVectorBlob,
    this.leftEyeVectorBlob,
    this.rightEyeVectorBlob,
    this.leftCheekVectorBlob,
    this.rightCheekVectorBlob,
    this.chinVectorBlob,
  });

  final String sourceId;
  final String personId;
  final String sourceType;
  final Uint8List vectorBlob;
  final Uint8List? eyeVectorBlob;
  final Uint8List? noseVectorBlob;
  final Uint8List? mouthVectorBlob;
  final Uint8List? foreheadVectorBlob;
  final Uint8List? leftEyeVectorBlob;
  final Uint8List? rightEyeVectorBlob;
  final Uint8List? leftCheekVectorBlob;
  final Uint8List? rightCheekVectorBlob;
  final Uint8List? chinVectorBlob;
  final double quality;
  final int createdAt;
  final int updatedAt;

  factory FaceVectorCacheEntry.fromMap(Map<String, dynamic> map) {
    return FaceVectorCacheEntry(
      sourceId: map['source_id'].toString(),
      personId: map['person_id'].toString(),
      sourceType: map['source_type'].toString(),
      vectorBlob: map['vector_blob'] as Uint8List? ?? Uint8List(0),
      eyeVectorBlob: map['eye_vector_blob'] as Uint8List?,
      noseVectorBlob: map['nose_vector_blob'] as Uint8List?,
      mouthVectorBlob: map['mouth_vector_blob'] as Uint8List?,
      foreheadVectorBlob: map['forehead_vector_blob'] as Uint8List?,
      leftEyeVectorBlob: map['left_eye_vector_blob'] as Uint8List?,
      rightEyeVectorBlob: map['right_eye_vector_blob'] as Uint8List?,
      leftCheekVectorBlob: map['left_cheek_vector_blob'] as Uint8List?,
      rightCheekVectorBlob: map['right_cheek_vector_blob'] as Uint8List?,
      chinVectorBlob: map['chin_vector_blob'] as Uint8List?,
      quality: (map['quality'] as num?)?.toDouble() ?? 0.0,
      createdAt: (map['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'source_id': sourceId,
      'person_id': personId,
      'source_type': sourceType,
      'vector_blob': vectorBlob,
      'eye_vector_blob': eyeVectorBlob,
      'nose_vector_blob': noseVectorBlob,
      'mouth_vector_blob': mouthVectorBlob,
      'forehead_vector_blob': foreheadVectorBlob,
      'left_eye_vector_blob': leftEyeVectorBlob,
      'right_eye_vector_blob': rightEyeVectorBlob,
      'left_cheek_vector_blob': leftCheekVectorBlob,
      'right_cheek_vector_blob': rightCheekVectorBlob,
      'chin_vector_blob': chinVectorBlob,
      'quality': quality,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class RecognitionZone {
  RecognitionZone({
    required this.id,
    required this.cameraId,
    required this.label,
    required this.leftRatio,
    required this.topRatio,
    required this.widthRatio,
    required this.heightRatio,
    required this.rotationDegrees,
    required this.enabled,
    required this.updatedAt,
  });

  final String id;
  final String cameraId;
  final String label;
  final double leftRatio;
  final double topRatio;
  final double widthRatio;
  final double heightRatio;
  final double rotationDegrees;
  final bool enabled;
  final int updatedAt;

  factory RecognitionZone.defaults({required String cameraId}) {
    return RecognitionZone(
      id: cameraId,
      cameraId: cameraId,
      label: 'Vung nhan dien',
      leftRatio: 0.18,
      topRatio: 0.18,
      widthRatio: 0.56,
      heightRatio: 0.56,
      rotationDegrees: 0,
      enabled: true,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  RecognitionZone copyWith({
    String? id,
    String? cameraId,
    String? label,
    double? leftRatio,
    double? topRatio,
    double? widthRatio,
    double? heightRatio,
    double? rotationDegrees,
    bool? enabled,
    int? updatedAt,
  }) {
    return RecognitionZone(
      id: id ?? this.id,
      cameraId: cameraId ?? this.cameraId,
      label: label ?? this.label,
      leftRatio: leftRatio ?? this.leftRatio,
      topRatio: topRatio ?? this.topRatio,
      widthRatio: widthRatio ?? this.widthRatio,
      heightRatio: heightRatio ?? this.heightRatio,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      enabled: enabled ?? this.enabled,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory RecognitionZone.fromMap(Map<String, dynamic> map) {
    return RecognitionZone(
      id: map['id'].toString(),
      cameraId: map['camera_id'].toString(),
      label: map['label'].toString(),
      leftRatio: (map['left_ratio'] as num?)?.toDouble() ?? 0.18,
      topRatio: (map['top_ratio'] as num?)?.toDouble() ?? 0.18,
      widthRatio: (map['width_ratio'] as num?)?.toDouble() ?? 0.56,
      heightRatio: (map['height_ratio'] as num?)?.toDouble() ?? 0.56,
      rotationDegrees: (map['rotation_degrees'] as num?)?.toDouble() ?? 0,
      enabled: (map['enabled'] as int?) == 1,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'camera_id': cameraId,
      'label': label,
      'left_ratio': leftRatio,
      'top_ratio': topRatio,
      'width_ratio': widthRatio,
      'height_ratio': heightRatio,
      'rotation_degrees': rotationDegrees,
      'enabled': enabled ? 1 : 0,
      'updated_at': updatedAt,
    };
  }
}

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

class ReportEventRow {
  ReportEventRow({
    required this.event,
    required this.eventType,
    required this.dayKey,
  });

  final RecognitionEvent event;
  final String eventType; // start | end | start_end
  final String dayKey;
}

class FaceAttendanceRepository {
  static const Uuid _uuid = Uuid();
  static const String _facePeopleCacheKey = 'face_people_cache_version';

  static Uint8List encodeVector(List<double> values) {
    final byteData = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      byteData.setFloat32(i * 4, values[i], Endian.little);
    }
    return byteData.buffer.asUint8List();
  }

  static List<double> decodeVector(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return const <double>[];
    if (bytes.lengthInBytes % 4 != 0) return const <double>[];
    final byteData = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    final result = List<double>.filled(bytes.lengthInBytes ~/ 4, 0.0);
    for (var i = 0; i < result.length; i++) {
      result[i] = byteData.getFloat32(i * 4, Endian.little);
    }
    return result;
  }

  static Future<int> getFacePeopleCacheVersion() async {
    final db = await AppDatabase.instance();
    final rows = await db.query('face_cache_state', where: 'key = ?', whereArgs: [_facePeopleCacheKey], limit: 1);
    if (rows.isEmpty) return 0;
    return (rows.first['value'] as num?)?.toInt() ?? 0;
  }

  static Future<void> _bumpFacePeopleCacheVersion({DatabaseExecutor? dbExecutor}) async {
    final db = dbExecutor ?? await AppDatabase.instance();
    final current = await getFacePeopleCacheVersion();
    await db.insert(
      'face_cache_state',
      {'key': _facePeopleCacheKey, 'value': current + 1},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<FacePerson>> getPeople() async {
    final db = await AppDatabase.instance();
    final rows = await db.query('face_people', orderBy: 'created_at DESC');
    return rows.map(FacePerson.fromMap).toList();
  }

  static Future<FacePerson?> getPersonById(String id) async {
    final db = await AppDatabase.instance();
    final rows = await db.query('face_people', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return FacePerson.fromMap(rows.first);
  }

  static Future<void> savePerson(FacePerson person) async {
    final db = await AppDatabase.instance();
    await db.insert('face_people', person.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await _bumpFacePeopleCacheVersion(dbExecutor: db);
  }

  static Future<List<FacePersonImage>> getPersonImages(String personId) async {
    final db = await AppDatabase.instance();
    final rows = await db.query(
      'face_person_images',
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'created_at ASC',
    );
    return rows.map(FacePersonImage.fromMap).toList();
  }

  static Future<List<FaceVectorCacheEntry>> getVectorCacheEntries() async {
    final db = await AppDatabase.instance();
    final rows = await db.query('face_vector_cache', orderBy: 'updated_at DESC');
    return rows.map(FaceVectorCacheEntry.fromMap).toList();
  }

  static Future<List<FaceVectorCacheEntry>> getVectorCacheEntriesForPerson(String personId) async {
    final db = await AppDatabase.instance();
    final rows = await db.query(
      'face_vector_cache',
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(FaceVectorCacheEntry.fromMap).toList();
  }

  static Future<void> replaceVectorCacheForPerson(
    String personId,
    List<FaceVectorCacheEntry> entries,
  ) async {
    final db = await AppDatabase.instance();
    await db.transaction((txn) async {
      await txn.delete('face_vector_cache', where: 'person_id = ?', whereArgs: [personId]);
      for (final entry in entries) {
        await txn.insert(
          'face_vector_cache',
          entry.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    await _bumpFacePeopleCacheVersion(dbExecutor: db);
  }

  static Future<void> deleteVectorCacheForPerson(String personId) async {
    final db = await AppDatabase.instance();
    await db.delete('face_vector_cache', where: 'person_id = ?', whereArgs: [personId]);
    await _bumpFacePeopleCacheVersion(dbExecutor: db);
  }

  static Future<void> replacePersonImages(
    String personId,
    List<String> imageBase64List, {
    List<String>? imageCropBase64List,
  }) async {
    final db = await AppDatabase.instance();
    await db.delete('face_person_images', where: 'person_id = ?', whereArgs: [personId]);
    for (var i = 0; i < imageBase64List.length; i++) {
      final imageBase64 = imageBase64List[i];
      if (imageBase64.trim().isEmpty) continue;
      final imageCropBase64 = imageCropBase64List != null && i < imageCropBase64List.length
          ? imageCropBase64List[i]
          : '';
      await db.insert(
        'face_person_images',
        FacePersonImage(
          id: _uuid.v4(),
          personId: personId,
          imageBase64: imageBase64,
          imageCropBase64: imageCropBase64,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await _bumpFacePeopleCacheVersion(dbExecutor: db);
  }

  static Future<void> deletePerson(String id) async {
    final db = await AppDatabase.instance();
    await db.delete('face_people', where: 'id = ?', whereArgs: [id]);
    await db.delete('face_person_images', where: 'person_id = ?', whereArgs: [id]);
    await db.delete('face_vector_cache', where: 'person_id = ?', whereArgs: [id]);
    await _bumpFacePeopleCacheVersion(dbExecutor: db);
  }

  static Future<RecognitionZone> getZoneByCameraId(String cameraId) async {
    final db = await AppDatabase.instance();
    final rows = await db.query('recognition_zones', where: 'camera_id = ?', whereArgs: [cameraId], limit: 1);
    if (rows.isEmpty) {
      final zone = RecognitionZone.defaults(cameraId: cameraId);
      await saveZone(zone);
      return zone;
    }
    return RecognitionZone.fromMap(rows.first);
  }

  static Future<void> saveZone(RecognitionZone zone) async {
    final db = await AppDatabase.instance();
    await db.insert('recognition_zones', zone.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<RecognitionEvent>> getRecentEvents({int limit = 30}) async {
    final db = await AppDatabase.instance();
    final rows = await db.query('recognition_events', orderBy: 'created_at DESC', limit: limit);
    return rows.map(RecognitionEvent.fromMap).toList();
  }

  static Future<List<RecognitionEvent>> getEventsByDate(DateTime day) async {
    final db = await AppDatabase.instance();
    final dayStart = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final dayEnd = DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch;
    final rows = await db.query(
      'recognition_events',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [dayStart, dayEnd],
      orderBy: 'created_at ASC',
    );
    final grouped = <String, List<RecognitionEvent>>{};
    for (final row in rows) {
      final event = RecognitionEvent.fromMap(row);
      final key = _dailyIdentityKey(event);
      final bucket = grouped.putIfAbsent(key, () => <RecognitionEvent>[]);
      if (bucket.isEmpty) {
        bucket.add(event);
      } else if (bucket.length == 1) {
        if (event.createdAt < bucket.first.createdAt) {
          bucket[0] = event;
        } else if (event.createdAt > bucket.first.createdAt) {
          bucket.add(event);
        }
      } else {
        if (event.createdAt <= bucket.first.createdAt) {
          bucket[0] = event;
        } else if (event.createdAt >= bucket.last.createdAt) {
          bucket[1] = event;
        }
      }
    }

    final collapsed = <RecognitionEvent>[];
    for (final bucket in grouped.values) {
      if (bucket.isEmpty) continue;
      collapsed.add(bucket.first);
      if (bucket.length > 1 && bucket.last.id != bucket.first.id) {
        collapsed.add(bucket.last);
      }
    }
    collapsed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return collapsed;
  }

  static Future<List<RecognitionEvent>> getEventsBetweenDates({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await AppDatabase.instance();
    final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
    final startMs = normalizedStart.millisecondsSinceEpoch;
    final endMs = normalizedEnd.millisecondsSinceEpoch;
    final rows = await db.query(
      'recognition_events',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'created_at ASC',
    );

    final grouped = <String, List<RecognitionEvent>>{};
    for (final row in rows) {
      final event = RecognitionEvent.fromMap(row);
      final key = _dailyIdentityKey(event);
      final bucket = grouped.putIfAbsent(key, () => <RecognitionEvent>[]);
      if (bucket.isEmpty) {
        bucket.add(event);
      } else if (bucket.length == 1) {
        if (event.createdAt < bucket.first.createdAt) {
          bucket[0] = event;
        } else if (event.createdAt > bucket.first.createdAt) {
          bucket.add(event);
        }
      } else {
        if (event.createdAt <= bucket.first.createdAt) {
          bucket[0] = event;
        } else if (event.createdAt >= bucket.last.createdAt) {
          bucket[1] = event;
        }
      }
    }

    final collapsed = <RecognitionEvent>[];
    for (final bucket in grouped.values) {
      if (bucket.isEmpty) continue;
      collapsed.add(bucket.first);
      if (bucket.length > 1 && bucket.last.id != bucket.first.id) {
        collapsed.add(bucket.last);
      }
    }
    collapsed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return collapsed;
  }

  static Future<void> addEvent(RecognitionEvent event) async {
    final db = await AppDatabase.instance();
    await db.transaction((txn) async {
      final day = DateTime.fromMillisecondsSinceEpoch(event.createdAt);
      final dayStart = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
      final dayEnd = DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch;

      final bool hasPersonId = (event.personId ?? '').trim().isNotEmpty;
      final identityWhere = hasPersonId
          ? 'person_id = ?'
          : 'person_id IS NULL AND person_name = ?';
      final identityArgs = hasPersonId
          ? <Object?>[event.personId]
          : <Object?>[event.personName];

      final rows = await txn.query(
        'recognition_events',
        where: '$identityWhere AND created_at >= ? AND created_at < ?',
        whereArgs: [...identityArgs, dayStart, dayEnd],
        orderBy: 'created_at ASC',
      );

      if (rows.length > 2) {
        final firstId = rows.first['id']?.toString() ?? '';
        final lastId = rows.last['id']?.toString() ?? '';
        for (var i = 1; i < rows.length - 1; i++) {
          final id = rows[i]['id']?.toString() ?? '';
          if (id.isEmpty || id == firstId || id == lastId) continue;
          await txn.delete(
            'recognition_events',
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      if (rows.isEmpty) {
        await txn.insert(
          'recognition_events',
          event.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return;
      }

      if (rows.length == 1) {
        final only = RecognitionEvent.fromMap(rows.first);
        if (event.createdAt <= only.createdAt) {
          await txn.update(
            'recognition_events',
            _mergeEvent(event, fixedId: only.id).toMap(),
            where: 'id = ?',
            whereArgs: [only.id],
          );
          return;
        }

        if (event.createdAt > only.createdAt) {
          await txn.insert(
            'recognition_events',
            event.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        return;
      }

      final first = RecognitionEvent.fromMap(rows.first);
      final last = RecognitionEvent.fromMap(rows.last);

      if (event.createdAt <= first.createdAt) {
        await txn.update(
          'recognition_events',
          _mergeEvent(event, fixedId: first.id).toMap(),
          where: 'id = ?',
          whereArgs: [first.id],
        );
        return;
      }

      if (event.createdAt >= last.createdAt) {
        await txn.update(
          'recognition_events',
          _mergeEvent(event, fixedId: last.id).toMap(),
          where: 'id = ?',
          whereArgs: [last.id],
        );
      }
    });
  }

  static RecognitionEvent _mergeEvent(RecognitionEvent event, {required String fixedId}) {
    return RecognitionEvent(
      id: fixedId,
      personId: event.personId,
      personName: event.personName,
      cameraId: event.cameraId,
      confidence: event.confidence,
      isStranger: event.isStranger,
      createdAt: event.createdAt,
      snapshotBase64: event.snapshotBase64,
    );
  }

  static String _dailyIdentityKey(RecognitionEvent event) {
    final personId = (event.personId ?? '').trim();
    if (personId.isNotEmpty) {
      return 'id:$personId';
    }
    return 'name:${event.personName.toLowerCase().trim()}';
  }

  static Future<Map<String, int>> getSummary() async {
    final db = await AppDatabase.instance();
    final totalRaw = await db.rawQuery('SELECT COUNT(*) AS c FROM recognition_events');
    final knownRaw = await db.rawQuery('SELECT COUNT(*) AS c FROM recognition_events WHERE is_stranger = 0');
    final strangerRaw = await db.rawQuery('SELECT COUNT(*) AS c FROM recognition_events WHERE is_stranger = 1');
    return {
      'total': (totalRaw.first['c'] as int?) ?? 0,
      'known': (knownRaw.first['c'] as int?) ?? 0,
      'stranger': (strangerRaw.first['c'] as int?) ?? 0,
    };
  }

  static Future<List<ReportEventRow>> getEventsForReport({
    required DateTime from,
    required DateTime to,
    String? subject,
    String eventType = 'all',
  }) async {
    final db = await AppDatabase.instance();
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    final lowerSubject = (subject ?? '').trim().toLowerCase();

    final whereParts = <String>['created_at >= ?', 'created_at < ?'];
    final whereArgs = <Object?>[fromMs, toMs];

    if (lowerSubject.isNotEmpty) {
      whereParts.add(
        "(LOWER(person_name) LIKE ? OR LOWER(COALESCE(person_id, '')) LIKE ?)",
      );
      final like = '%$lowerSubject%';
      whereArgs.addAll([like, like]);
    }

    final rows = await db.query(
      'recognition_events',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'created_at ASC',
    );

    final grouped = <String, List<RecognitionEvent>>{};
    for (final row in rows) {
      final event = RecognitionEvent.fromMap(row);
      final day = DateTime.fromMillisecondsSinceEpoch(event.createdAt);
      final dayKey = _formatDayKey(day);
      final key = '$dayKey|${_dailyIdentityKey(event)}';
      final bucket = grouped.putIfAbsent(key, () => <RecognitionEvent>[]);
      bucket.add(event);
    }

    final normalizedType = eventType.trim().toLowerCase();
    final result = <ReportEventRow>[];

    for (final entry in grouped.entries) {
      final bucket = entry.value;
      if (bucket.isEmpty) continue;
      final dayKey = entry.key.split('|').first;
      final first = bucket.first;
      final last = bucket.last;

      if (first.id == last.id) {
        if (normalizedType == 'all' ||
            normalizedType == 'start' ||
            normalizedType == 'end') {
          result.add(
            ReportEventRow(event: first, eventType: 'start_end', dayKey: dayKey),
          );
        }
        continue;
      }

      if (normalizedType == 'all' || normalizedType == 'start') {
        result.add(ReportEventRow(event: first, eventType: 'start', dayKey: dayKey));
      }
      if (normalizedType == 'all' || normalizedType == 'end') {
        result.add(ReportEventRow(event: last, eventType: 'end', dayKey: dayKey));
      }
    }

    result.sort((a, b) => b.event.createdAt.compareTo(a.event.createdAt));
    return result;
  }

  static String _formatDayKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static RecognitionEvent buildPersonEvent(FacePerson person, String cameraId) {
    return RecognitionEvent(
      id: _uuid.v4(),
      personId: person.id,
      personName: person.name,
      confidence: 0.93,
      isStranger: false,
      cameraId: cameraId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      snapshotBase64: person.imageBase64,
    );
  }

  static RecognitionEvent buildStrangerEvent(String cameraId) {
    return RecognitionEvent(
      id: _uuid.v4(),
      personName: 'Nguoi la',
      confidence: 0.35,
      isStranger: true,
      cameraId: cameraId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static String encodeImageBytes(List<int> bytes) => base64Encode(bytes);
}
