import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/app_log.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late String logPath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gaming-memories-log-');
    logPath = p.join(directory.path, 'logs', 'gaming-memories.log');
  });

  tearDown(() => directory.delete(recursive: true));

  FileAppLog createLog({int maxBytes = 2 * 1024 * 1024, int retained = 2}) {
    return FileAppLog(
      filePath: logPath,
      maxBytes: maxBytes,
      retainedFiles: retained,
      mirrorToConsole: false,
    );
  }

  test('writes the level, category, error and stack trace', () async {
    final log = createLog();

    log.error(
      'Provider "Steam" failed.',
      category: 'provider',
      error: const FileSystemException('listing failed', '/tmp/x'),
      stackTrace: StackTrace.fromString('#0 first\n#1 second'),
    );
    await log.flush();

    final contents = await File(logPath).readAsString();
    expect(contents, contains('ERROR'));
    expect(contents, contains('[provider]'));
    expect(contents, contains('Provider "Steam" failed.'));
    expect(contents, contains('FileSystemException'));
    expect(contents, contains('#0 first'));
    expect(contents, contains('#1 second'));
  });

  test('creates the log directory on the first write', () async {
    expect(Directory(p.dirname(logPath)).existsSync(), isFalse);

    final log = createLog()..info('started');
    await log.flush();

    expect(File(logPath).existsSync(), isTrue);
  });

  test('redacts before anything reaches the file', () async {
    final log = createLog()
      ..redact = (value) => value.replaceAll('sekret', '<REDACTED>');

    log.error('Request failed for key=sekret', category: 'steam');
    await log.flush();

    final contents = await File(logPath).readAsString();
    expect(contents, isNot(contains('sekret')));
    expect(contents, contains('<REDACTED>'));
  });

  test('keeps entries in order', () async {
    final log = createLog();

    for (var index = 0; index < 50; index++) {
      log.info('entry $index');
    }
    await log.flush();

    final lines = (await File(logPath).readAsString())
        .trim()
        .split('\n')
        .where((line) => line.contains('entry '))
        .map((line) => int.parse(line.split('entry ').last))
        .toList();
    expect(lines, List.generate(50, (index) => index));
  });

  test('rotates and keeps only the retained files', () async {
    final log = createLog(maxBytes: 256, retained: 2);

    for (var index = 0; index < 200; index++) {
      log.info('entry $index padded with some text to fill the file quickly');
    }
    await log.flush();

    expect(File(logPath).existsSync(), isTrue);
    expect(File('$logPath.2').existsSync(), isTrue);
    expect(File('$logPath.4').existsSync(), isFalse);
  });

  test('reads every retained file oldest first', () async {
    final log = createLog(maxBytes: 256, retained: 2);

    for (var index = 0; index < 200; index++) {
      log.info('entry $index padded with some text to fill the file quickly');
    }
    final contents = await log.read();

    final entries = RegExp(r'entry (\d+)')
        .allMatches(contents)
        .map((match) => int.parse(match.group(1)!))
        .toList();
    expect(entries, isNotEmpty);
    expect(entries, orderedEquals([...entries]..sort()));
    expect(entries.last, 199);
  });

  test('a write failure never escapes', () async {
    // A path whose parent is a file cannot be created.
    final blocker = File(p.join(directory.path, 'blocked'));
    await blocker.writeAsString('not a directory');
    final log = FileAppLog(
      filePath: p.join(blocker.path, 'nested', 'app.log'),
      mirrorToConsole: false,
    );

    log.error('this cannot be written', error: StateError('boom'));

    await expectLater(log.flush(), completes);
  });

  test('honours the minimum level', () async {
    final log = FileAppLog(
      filePath: logPath,
      minimumLevel: LogLevel.warning,
      mirrorToConsole: false,
    )..info('quiet');
    log.warning('loud');
    await log.flush();

    final contents = await File(logPath).readAsString();
    expect(contents, isNot(contains('quiet')));
    expect(contents, contains('loud'));
  });

  test('does not repeat an exception type it already carries', () async {
    final log = createLog();

    log.error('failed', error: const FileSystemException('listing failed'));
    await log.flush();

    final contents = await File(logPath).readAsString();
    expect(contents, contains('FileSystemException: listing failed'));
    expect(
      contents,
      isNot(contains('FileSystemException: FileSystemException')),
    );
  });

  test('the silent log writes nothing', () async {
    const log = SilentAppLog();

    log.error('boom', error: StateError('x'), stackTrace: StackTrace.current);

    expect(await log.read(), isEmpty);
    expect(Directory(directory.path).listSync(), isEmpty);
  });
}
