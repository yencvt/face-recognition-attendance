import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_cam/database/face_attendance_repository.dart';
import 'package:flutter_cam/log/log_service.dart';
import 'package:flutter_cam/services/face_recognition_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await LogService().init();

  final service = FaceRecognitionService.instance;

  try {
    final peopleBefore = await FaceAttendanceRepository.getPeople();
    final vectorsBefore = await FaceAttendanceRepository.getVectorCacheEntries();

    print('REBUILD_START people=${peopleBefore.length} vectors=${vectorsBefore.length}');

    await service.initialize();
    await service.rebuildVectorsForAllPeople();

    final peopleAfter = await FaceAttendanceRepository.getPeople();
    final vectorsAfter = await FaceAttendanceRepository.getVectorCacheEntries();

    print('REBUILD_DONE people=${peopleAfter.length} vectors=${vectorsAfter.length}');

    for (final person in peopleAfter) {
      final entries = await FaceAttendanceRepository.getVectorCacheEntriesForPerson(
        person.id,
      );
      print(
        'PERSON_VECTORS personId=${person.id} name=${person.name} count=${entries.length}',
      );
    }
  } catch (e, st) {
    print('REBUILD_ERROR $e');
    print(st.toString().split('\n').take(5).join('\n'));
    exitCode = 1;
  } finally {
    await service.dispose();
  }

  exit(exitCode);
}
