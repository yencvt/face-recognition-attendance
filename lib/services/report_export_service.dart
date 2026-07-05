import 'dart:io';

import '../database/face_attendance_repository.dart';
import '../database/report_settings_repository.dart';

class ReportExportService {
  ReportExportService._internal();
  static final ReportExportService instance = ReportExportService._internal();

  Future<String> exportDailyCsv({
    required DateTime day,
    String? outputDirectory,
  }) async {
    final from = DateTime(day.year, day.month, day.day);
    final to = from.add(const Duration(days: 1));
    final fileName =
        'attendance_day_${_compactDate(from)}_${_compactDateTime(DateTime.now())}.csv';
    return exportCsvByFilter(
      fromDate: from,
      toDate: to,
      eventType: 'all',
      outputDirectory: outputDirectory,
      fileName: fileName,
    );
  }

  Future<String> exportCsvByFilter({
    DateTime? fromDate,
    DateTime? toDate,
    String? subject,
    String eventType = 'all',
    String? outputDirectory,
    String? fileName,
  }) async {
    final now = DateTime.now();
    final from = fromDate ?? DateTime(now.year, now.month, now.day);
    final to = toDate ?? from.add(const Duration(days: 1));

    final rows = await FaceAttendanceRepository.getEventsForReport(
      from: from,
      to: to,
      subject: subject,
      eventType: eventType,
    );

    final csv = buildCsvContent(rows);
    final outputDir = await _resolveOutputDirectory(outputDirectory);
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final name = (fileName == null || fileName.trim().isEmpty)
        ? 'attendance_${_compactDateTime(now)}.csv'
        : fileName.trim();
    final file = File('${outputDir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(csv, flush: true);
    return file.path;
  }

  Future<String> buildCsvByFilter({
    DateTime? fromDate,
    DateTime? toDate,
    String? subject,
    String eventType = 'all',
  }) async {
    final now = DateTime.now();
    final from = fromDate ?? DateTime(now.year, now.month, now.day);
    final to = toDate ?? from.add(const Duration(days: 1));

    final rows = await FaceAttendanceRepository.getEventsForReport(
      from: from,
      to: to,
      subject: subject,
      eventType: eventType,
    );
    return buildCsvContent(rows);
  }

  String buildCsvContent(List<ReportEventRow> rows) {
    final buffer = StringBuffer();
    buffer.writeln(
      'event_id,person_id,person_name,camera_id,confidence,is_stranger,event_type,event_day,created_at_iso,created_at_ms',
    );

    for (final row in rows) {
      final event = row.event;
      final iso = DateTime.fromMillisecondsSinceEpoch(event.createdAt).toIso8601String();
      buffer.writeln(
        [
          event.id,
          event.personId ?? '',
          event.personName,
          event.cameraId ?? '',
          event.confidence.toStringAsFixed(6),
          event.isStranger ? '1' : '0',
          row.eventType,
          row.dayKey,
          iso,
          event.createdAt.toString(),
        ].map(_csvEscape).join(','),
      );
    }

    return buffer.toString();
  }

  Future<Directory> _resolveOutputDirectory(String? outputDirectory) async {
    final fromArgument = outputDirectory?.trim() ?? '';
    if (fromArgument.isNotEmpty) {
      return Directory(fromArgument);
    }

    final config = await ReportSettingsRepository.getOrCreateDefaultConfig();
    if (config.scheduledExportDirectory.trim().isNotEmpty) {
      return Directory(config.scheduledExportDirectory.trim());
    }

    return Directory('${Directory.current.path}${Platform.pathSeparator}reports');
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    if (escaped.contains(',') || escaped.contains('"') || escaped.contains('\n')) {
      return '"$escaped"';
    }
    return escaped;
  }

  String _compactDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  String _compactDateTime(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    final ss = date.second.toString().padLeft(2, '0');
    return '$y$m${d}_$hh$mm$ss';
  }
}
