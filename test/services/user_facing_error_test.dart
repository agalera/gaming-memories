import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/folder_access_service.dart';
import 'package:gaming_memories/services/user_facing_error.dart';

void main() {
  test('never repeats the raw exception', () {
    final failures = <Object>[
      const FileSystemException(
        'Directory listing failed',
        '/Users/tester/Library',
        OSError('Operation not permitted', 1),
      ),
      const FormatException('Unexpected token at offset 12'),
      const SocketException('Connection refused'),
      TimeoutException('Timed out', const Duration(seconds: 5)),
      StateError('Bad state: no element'),
      ArgumentError('Invalid argument: null'),
    ];

    for (final failure in failures) {
      final message = describeFailure(failure, action: 'load the library');

      expect(message, startsWith('Could not load the library.'));
      expect(message, isNot(contains('Exception')));
      expect(message, isNot(contains('errno')));
      expect(message, isNot(contains('OS Error')));
      expect(message, isNot(contains(failure.runtimeType.toString())));
    }
  });

  test('explains what the user can do about a filesystem error', () {
    String describe(int code) => describeFailure(
      FileSystemException('failed', '/somewhere', OSError('boom', code)),
      action: 'open this folder',
    );

    expect(describe(1), contains('not allowed to read'));
    expect(describe(13), contains('not allowed to read'));
    expect(describe(2), contains('no longer there'));
    expect(describe(28), contains('disk is full'));
    expect(describe(30), contains('read-only'));
  });

  test('passes through a message the app wrote for the user', () {
    expect(
      describeFailure(
        const FolderAccessException('denied', 'Choose the folder again.'),
        action: 'save folder access',
      ),
      'Could not save folder access. Choose the folder again.',
    );
    expect(
      describeFailure(
        const FileSystemException('Select a library folder first.'),
        action: 'import screenshots',
      ),
      'Could not import screenshots. Select a library folder first.',
    );
  });

  test('points at the log when there is nothing useful to say', () {
    expect(
      describeFailure(StateError('no element'), action: 'refresh the timeline'),
      'Could not refresh the timeline. The details were written to the log file.',
    );
  });

  test('a platform error message is not shown to the user', () {
    final message = describeFailure(
      const FileSystemException(
        'Cannot open file',
        '/tmp/x',
        OSError('Unknown error', 9999),
      ),
      action: 'open this folder',
    );

    expect(message, isNot(contains('Cannot open file')));
    expect(message, endsWith('The details were written to the log file.'));
  });
}
