import 'dart:collection';
import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String source; // "daemon", "ws", "http", "task", "app"
  final String message;

  LogEntry({
    required this.level,
    required this.source,
    required this.message,
  }) : timestamp = DateTime.now();

  String get formatted {
    final t = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final lvl = level.name.toUpperCase().padRight(5);
    return '[$t] $lvl [$source] $message';
  }
}

/// Singleton in-memory log buffer for the app.
/// Keeps the last [maxEntries] log lines so developers can debug issues
/// from the Config > View Logs screen.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const int maxEntries = 500;
  final _entries = Queue<LogEntry>();

  List<LogEntry> get entries => _entries.toList();

  String get text => _entries.map((e) => e.formatted).join('\n');

  int get length => _entries.length;

  void _add(LogLevel level, String source, String message) {
    final entry = LogEntry(level: level, source: source, message: message);
    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    // Also forward to debugPrint for adb logcat
    debugPrint(entry.formatted);
  }

  void debug(String source, String message) => _add(LogLevel.debug, source, message);
  void info(String source, String message) => _add(LogLevel.info, source, message);
  void warn(String source, String message) => _add(LogLevel.warn, source, message);
  void error(String source, String message) => _add(LogLevel.error, source, message);

  void clear() => _entries.clear();
}
