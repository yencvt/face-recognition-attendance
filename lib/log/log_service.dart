import 'dart:io';
import 'package:logger/logger.dart';
// import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  late Logger _logger;
  File? _logFile;
  final int maxLines = 5000;
  final int keepLines = 4500; // số dòng giữ lại khi vượt quá
  String traceId = const Uuid().v4(); // sinh traceId mặc định

  Future<void> init() async {
    _logger = Logger(
      printer: PrettyPrinter(),
    );

    final dir = Directory.current;
    _logFile = File('${dir.path}/app.log');

    // Nếu file quá lớn (>5MB), xóa để tránh đầy
    // if (await _logFile!.exists()) {
    //   final size = await _logFile!.length();
    //   if (size > 5 * 1024 * 1024) {
    //     await _logFile!.delete();
    //   }
    // }
    if (!(await _logFile!.exists())) {
      await _logFile!.create(recursive: true);
    }
  }

  void newTrace() {
    traceId = const Uuid().v4(); // sinh traceId
  }

  void info(String message) => _log("INFO", message, StackTrace.current);
  void error(String message) => _log("ERROR", message, StackTrace.current);
  void debug(String message) => _log("DEBUG", message, StackTrace.current);

  void _log(String level, String message, StackTrace stackTrace) {
    final caller = _getCallerInfo(stackTrace);
    final logLine =
        "[$traceId] [$level] [func:${caller['function']}] [path:${caller['path']}] $message";

    switch (level) {
      case "INFO":
        _logger.i(logLine);
        break;
      case "ERROR":
        _logger.e(logLine);
        break;
      case "DEBUG":
        _logger.d(logLine);
        break;
      default:
        _logger.w(logLine);
    }

    _writeToFile(logLine);
  }

  Map<String, String> _getCallerInfo(StackTrace stackTrace) {
    final trace = stackTrace.toString().split('\n');
    if (trace.length > 1) {
      final line = trace[1].trim();
      // Ví dụ line: "#1      LogService.info (package:flutter_cam/log_service.dart:30:5)"
      final regex = RegExp(r'#\d+\s+([^\s]+)\s+\((.+)\)');
      final match = regex.firstMatch(line);
      if (match != null) {
        final function = match.group(1) ?? '-';
        final path = match.group(2) ?? '-';
        return {'function': function, 'path': path};
      }
    }
    return {'function': '-', 'path': '-'};
  }

  Future<void> _writeToFile(String message) async {
    if (_logFile == null) return;

    final timestamp = DateTime.now().toIso8601String();
    await _logFile!.writeAsString("$timestamp $message\n", mode: FileMode.append);

    // Kiểm tra số dòng
    final lines = await _logFile!.readAsLines();
    if (lines.length > maxLines) {
      // Giữ lại các dòng cuối cùng
      final newContent = lines.sublist(lines.length - keepLines).join("\n");
      await _logFile!.writeAsString(newContent);
    }
  }
}
