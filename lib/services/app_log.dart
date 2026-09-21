import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error;

  String get label => name.toUpperCase().padRight(7);
}

/// Writes diagnostics to a file so a failure can be explained after the fact.
///
/// The user never reads this — they get a plain sentence, and the exception,
/// its stack trace and the surrounding context land here instead. It is also
/// the file a support packet will carry, so everything written goes through
/// [redact] first.
///
/// Logging is best effort by design: a log line that cannot be written is
/// dropped rather than turned into a second failure on top of the first.
abstract interface class AppLog {
  /// Replaces secrets before anything is written. Set by whoever knows what is
  /// sensitive — the controller knows the Steam API key, a log does not.
  set redact(String Function(String value)? value);

  void debug(String message, {String? category});

  void info(String message, {String? category});

  void warning(
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  });

  void error(
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  });

  /// The whole log, newest file last, for a support packet. Empty when there
  /// is nothing to report.
  Future<String> read();

  /// Waits for every queued line to reach the file.
  Future<void> flush();
}

/// Discards everything. The default, so tests and any code constructed before
/// the log file exists never touch the filesystem.
class SilentAppLog implements AppLog {
  const SilentAppLog();

  @override
  set redact(String Function(String value)? value) {}

  @override
  void debug(String message, {String? category}) {}

  @override
  void info(String message, {String? category}) {}

  @override
  void warning(
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  void error(
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  Future<String> read() async => '';

  @override
  Future<void> flush() async {}
}

/// The log for code that cannot be handed one.
///
/// The providers are `const` value objects constructed inside `const` provider
/// lists, so there is nowhere to inject a log. Everything else takes one as a
/// constructor argument. Set once at startup; stays silent in tests.
AppLog diagnosticLog = const SilentAppLog();

class FileAppLog implements AppLog {
  FileAppLog({
    required this.filePath,
    this.maxBytes = 2 * 1024 * 1024,
    this.retainedFiles = 2,
    this.minimumLevel = LogLevel.debug,
    this.mirrorToConsole = kDebugMode,
  });

  final String filePath;

  /// The size at which the log rotates.
  final int maxBytes;

  /// How many rotated files to keep beside the current one.
  final int retainedFiles;

  final LogLevel minimumLevel;
  final bool mirrorToConsole;

  @override
  String Function(String value)? redact;

  Future<void> _queue = Future.value();
  bool _rotationChecked = false;

  @override
  void debug(String message, {String? category}) =>
      _write(LogLevel.debug, message, category: category);

  @override
  void info(String message, {String? category}) =>
      _write(LogLevel.info, message, category: category);

  @override
  void warning(
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  }) => _write(
    LogLevel.warning,
    message,
    category: category,
    error: error,
    stackTrace: stackTrace,
  );

  @override
  void error(
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  }) => _write(
    LogLevel.error,
    message,
    category: category,
    error: error,
    stackTrace: stackTrace,
  );

  void _write(
    LogLevel level,
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minimumLevel.index) {
      return;
    }
    final entry = _format(
      level,
      message,
      category: category,
      error: error,
      stackTrace: stackTrace,
    );
    if (mirrorToConsole) {
      debugPrint(entry.trimRight());
    }
    // Every append is chained onto the previous one, so entries cannot
    // interleave and a rotation cannot run underneath a write.
    _queue = _queue.then((_) => _append(entry)).catchError((_) {});
  }

  String _format(
    LogLevel level,
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer()
      ..write(DateTime.now().toUtc().toIso8601String())
      ..write(' ')
      ..write(level.label)
      ..write(' ')
      ..write(category == null ? '' : '[$category] ')
      ..writeln(message);
    if (error != null) {
      // Most exceptions already lead with their type; do not say it twice.
      final text = '$error';
      final type = '${error.runtimeType}';
      buffer.writeln(text.startsWith(type) ? '    $text' : '    $type: $text');
    }
    if (stackTrace != null) {
      for (final line in stackTrace.toString().trimRight().split('\n')) {
        buffer.writeln('    $line');
      }
    }
    final entry = buffer.toString();
    return redact?.call(entry) ?? entry;
  }

  Future<void> _append(String entry) async {
    final file = File(filePath);
    if (!_rotationChecked) {
      await file.parent.create(recursive: true);
      _rotationChecked = true;
    }
    await file.writeAsString(entry, mode: FileMode.append, flush: true);
    if (await file.length() > maxBytes) {
      await _rotate(file);
    }
  }

  /// Drops the oldest file, shifts the rest along and starts a new current
  /// one, so at most [retainedFiles] rotated files sit beside it.
  Future<void> _rotate(File file) async {
    final oldest = File('$filePath.${retainedFiles + 1}');
    if (await oldest.exists()) {
      await oldest.delete();
    }
    for (var index = retainedFiles; index >= 2; index--) {
      final source = File('$filePath.$index');
      if (await source.exists()) {
        await source.rename('$filePath.${index + 1}');
      }
    }
    await file.rename('$filePath.2');
  }

  @override
  Future<String> read() async {
    await flush();
    final buffer = StringBuffer();
    for (var index = retainedFiles + 1; index >= 1; index--) {
      final file = index == 1 ? File(filePath) : File('$filePath.$index');
      if (await file.exists()) {
        buffer.write(await file.readAsString());
      }
    }
    return buffer.toString();
  }

  @override
  Future<void> flush() => _queue;
}
