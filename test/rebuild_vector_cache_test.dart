import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_cam/database/face_attendance_repository.dart';
import 'package:flutter_cam/log/log_service.dart';
import 'package:flutter_cam/services/face_recognition_service.dart';

void main() {
  testWidgets('rebuild all vector cache entries', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LogService().init();

    final service = FaceRecognitionService.instance;

    final peopleBefore = await FaceAttendanceRepository.getPeople();
    final vectorsBefore = await FaceAttendanceRepository.getVectorCacheEntries();
    // ignore: avoid_print
    print('REBUILD_START people=${peopleBefore.length} vectors=${vectorsBefore.length}');

    await service.initialize();
    await service.rebuildVectorsForAllPeople();

    final peopleAfter = await FaceAttendanceRepository.getPeople();
    final vectorsAfter = await FaceAttendanceRepository.getVectorCacheEntries();
    // ignore: avoid_print
    print('REBUILD_DONE people=${peopleAfter.length} vectors=${vectorsAfter.length}');

    for (final person in peopleAfter) {
      final entries = await FaceAttendanceRepository.getVectorCacheEntriesForPerson(
        person.id,
      );
      // ignore: avoid_print
      print('PERSON_VECTORS personId=${person.id} name=${person.name} count=${entries.length}');
    }

    await service.dispose();

    expect(vectorsAfter.length, greaterThanOrEqualTo(0));
  });
}
