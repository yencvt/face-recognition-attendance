import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../database/report_settings_repository.dart';
import '../log/log_service.dart';
import 'report_export_service.dart';

class ReportAutomationService {
  ReportAutomationService._internal();
  static final ReportAutomationService instance =
      ReportAutomationService._internal();

  final LogService _log = LogService();
  final ReportExportService _exportService = ReportExportService.instance;

  Timer? _schedulerTimer;
  HttpServer? _server;
  ReportExportConfig _config = const ReportExportConfig();
  String? _lastScheduledRunDay;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _config = await ReportSettingsRepository.getOrCreateDefaultConfig();
    _lastScheduledRunDay = await ReportSettingsRepository.getLastScheduledRunDay();

    ReportSettingsRepository.changes.listen((config) {
      _config = config;
      unawaited(_applyRuntimeConfig());
    });

    await _applyRuntimeConfig();

    _schedulerTimer?.cancel();
    _schedulerTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_checkAndRunScheduledExport());
    });
    await _checkAndRunScheduledExport();
  }

  Future<void> _applyRuntimeConfig() async {
    if (!_config.apiEnabled) {
      await _stopServer();
      return;
    }

    final current = _server;
    if (current != null &&
        current.port == _config.apiPort &&
        current.address.address == _config.apiHost) {
      return;
    }

    await _restartServer();
  }

  Future<void> _restartServer() async {
    await _stopServer();
    try {
      final host = _config.apiHost.trim().isEmpty ? '0.0.0.0' : _config.apiHost.trim();
      final port = _config.apiPort;
      final server = await HttpServer.bind(host, port, shared: true);
      _server = server;
      server.listen(_handleRequest, onError: (Object error, StackTrace stack) {
        _log.error('Report API request error: $error');
      });
      _log.info('Report API started at http://$host:$port');
    } catch (e) {
      _log.error('Cannot start Report API: $e');
    }
  }

  Future<void> _stopServer() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
      _log.info('Report API stopped');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/health') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'status': 'ok'}));
        await request.response.close();
        return;
      }

      if (path != '/api/reports/export') {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not found');
        await request.response.close();
        return;
      }

      if (request.method.toUpperCase() != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        request.response.write('Only GET is allowed');
        await request.response.close();
        return;
      }

      final qp = request.uri.queryParameters;
      final from = _parseDateOrNull(qp['from']);
      final to = _parseDateOrNull(qp['to']);
      final subject = qp['subject'];
      final type = (qp['type'] ?? 'all').trim().toLowerCase();
      final save = (qp['save'] ?? '').trim().toLowerCase();
      final saveToFile = save == '1' || save == 'true' || save == 'yes';

      final csv = await _exportService.buildCsvByFilter(
        fromDate: from,
        toDate: _normalizeToEndExclusive(to),
        subject: subject,
        eventType: type,
      );

      String? savedPath;
      if (saveToFile) {
        savedPath = await _exportService.exportCsvByFilter(
          fromDate: from,
          toDate: _normalizeToEndExclusive(to),
          subject: subject,
          eventType: type,
          outputDirectory: _config.scheduledExportDirectory.trim().isEmpty
              ? null
              : _config.scheduledExportDirectory.trim(),
          fileName: _buildApiFileName(type),
        );
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType('text', 'csv', charset: 'utf-8');
      request.response.headers.set(
        'content-disposition',
        'attachment; filename="${_buildApiFileName(type)}"',
      );
      if (savedPath != null) {
        request.response.headers.set('x-report-saved-path', savedPath);
      }
      request.response.write(csv);
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Export error: $e');
      await request.response.close();
      _log.error('Report API export failed: $e');
    }
  }

  Future<void> _checkAndRunScheduledExport() async {
    if (!_config.scheduledExportEnabled) return;
    if (_config.scheduledExportDirectory.trim().isEmpty) return;

    final parsed = _parseHourMinute(_config.scheduledExportTime);
    if (parsed == null) return;

    final now = DateTime.now();
    if (now.hour != parsed.$1 || now.minute != parsed.$2) {
      return;
    }

    final dayKey = _dayKey(now);
    if (_lastScheduledRunDay == dayKey) {
      return;
    }

    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(const Duration(days: 1));

    final path = await _exportService.exportCsvByFilter(
      fromDate: from,
      toDate: to,
      eventType: 'all',
      outputDirectory: _config.scheduledExportDirectory,
      fileName: _buildScheduledFileName(now),
    );

    _lastScheduledRunDay = dayKey;
    await ReportSettingsRepository.saveLastScheduledRunDay(dayKey);
    _log.info('Scheduled report exported: $path');
  }

  DateTime? _parseDateOrNull(String? input) {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) return null;

    final date = DateTime.tryParse(raw);
    if (date != null) {
      return date;
    }

    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  DateTime? _normalizeToEndExclusive(DateTime? to) {
    if (to == null) return null;
    if (to.hour == 0 && to.minute == 0 && to.second == 0 && to.millisecond == 0) {
      return to.add(const Duration(days: 1));
    }
    return to;
  }

  (int, int)? _parseHourMinute(String input) {
    final parts = input.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return (h, m);
  }

  String _buildApiFileName(String type) {
    final now = DateTime.now();
    final normalizedType = type.isEmpty ? 'all' : type;
    return '${_config.filePrefix}_${normalizedType}_${_compactDateTime(now)}.csv';
  }

  String _buildScheduledFileName(DateTime now) {
    return '${_config.filePrefix}_scheduled_${_compactDateTime(now)}.csv';
  }

  String _dayKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _compactDateTime(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    final ss = date.second.toString().padLeft(2, '0');
    return '${y}${m}${d}_${hh}${mm}${ss}';
  }
}
