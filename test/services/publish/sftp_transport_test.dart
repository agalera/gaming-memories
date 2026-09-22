import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/publish/publish_credentials.dart';
import 'package:gaming_memories/services/publish/publish_plan.dart';
import 'package:gaming_memories/services/publish/publish_transport.dart';
import 'package:gaming_memories/services/publish/sftp_transport.dart';

PublishFile planned(
  String remotePath, {
  int size = 10,
  int modifiedSeconds = 1000,
}) {
  return PublishFile(
    remotePath: remotePath,
    localPath: '/local/$remotePath',
    root: PublishSourceRoot.library,
    size: size,
    modified: DateTime.fromMillisecondsSinceEpoch(modifiedSeconds * 1000),
  );
}

RemoteEntry present(
  String path, {
  int size = 10,
  int modifiedSeconds = 1000,
  bool isDirectory = false,
}) {
  return RemoteEntry(
    path: path,
    isDirectory: isDirectory,
    size: size,
    modifiedSeconds: modifiedSeconds,
  );
}

void main() {
  test('skips a file whose size and time already match', () {
    final diff = diffAgainstRemote(
      plan: PublishPlan(files: [planned('a.png')], directories: const []),
      remote: [present('a.png')],
      deleteRemoved: true,
    );

    expect(diff.uploads, isEmpty);
    expect(diff.skipped.single.remotePath, 'a.png');
  });

  test('uploads a file whose size or time differs', () {
    final diff = diffAgainstRemote(
      plan: PublishPlan(
        files: [planned('a.png'), planned('b.png')],
        directories: const [],
      ),
      remote: [
        present('a.png', size: 9),
        present('b.png', modifiedSeconds: 999),
      ],
      deleteRemoved: true,
    );

    expect(diff.uploads.map((file) => file.remotePath), ['a.png', 'b.png']);
    expect(diff.uploadBytes, 20);
  });

  test('uploads a file the remote does not have at all', () {
    final diff = diffAgainstRemote(
      plan: PublishPlan(files: [planned('a.png')], directories: const []),
      remote: const [],
      deleteRemoved: true,
    );

    expect(diff.uploads.single.remotePath, 'a.png');
  });

  test('creates only the folders the remote is missing', () {
    final diff = diffAgainstRemote(
      plan: const PublishPlan(files: [], directories: ['Steam', 'Steam/Hades']),
      remote: [present('Steam', isDirectory: true)],
      deleteRemoved: true,
    );

    expect(diff.directories, ['Steam/Hades']);
  });

  test('removes what the plan does not hold, deepest first', () {
    final diff = diffAgainstRemote(
      plan: PublishPlan(
        files: [planned('Steam/Hades/a.png')],
        directories: const ['Steam', 'Steam/Hades'],
      ),
      remote: [
        present('Steam', isDirectory: true),
        present('Steam/Hades', isDirectory: true),
        present('Steam/Hades/a.png'),
        present('Steam/Gone', isDirectory: true),
        present('Steam/Gone/old.png'),
        present('stray.txt'),
      ],
      deleteRemoved: true,
    );

    expect(diff.staleFiles, ['Steam/Gone/old.png', 'stray.txt']);
    expect(diff.staleDirectories, ['Steam/Gone']);
  });

  test('mirroring off leaves everything on the remote', () {
    final diff = diffAgainstRemote(
      plan: PublishPlan(files: [planned('a.png')], directories: const []),
      remote: [present('a.png'), present('gone.png')],
      deleteRemoved: false,
    );

    expect(diff.staleFiles, isEmpty);
    expect(diff.staleDirectories, isEmpty);
  });

  group('parseMode', () {
    test('reads an octal mode', () {
      expect(SftpTransport.parseMode('644', fallback: 0), 0x1a4);
      expect(SftpTransport.parseMode('755', fallback: 0), 0x1ed);
      expect(SftpTransport.parseMode('0644', fallback: 0), 0x1a4);
    });

    test('falls back rather than leaving a file unreadable', () {
      expect(SftpTransport.parseMode('', fallback: 0x1a4), 0x1a4);
      expect(SftpTransport.parseMode('rwx', fallback: 0x1a4), 0x1a4);
      expect(SftpTransport.parseMode('999', fallback: 0x1a4), 0x1a4);
    });
  });

  group('isEncryptedKey', () {
    test('sees an OpenSSH key sealed with a cipher', () {
      expect(isEncryptedKey(_openSshKey('aes256-ctr')), isTrue);
    });

    test('sees an unprotected OpenSSH key', () {
      expect(isEncryptedKey(_openSshKey('none')), isFalse);
    });

    test('treats something that is not a key as plain', () {
      expect(isEncryptedKey('not a key at all'), isFalse);
      expect(isEncryptedKey(''), isFalse);
    });
  });
  group('stopping', () {
    test('a cancellation runs its listeners once, and only once', () {
      final cancellation = PublishCancellation();
      var calls = 0;

      cancellation.onCancel(() => calls++);
      cancellation
        ..cancel()
        ..cancel();

      expect(calls, 1);
      expect(cancellation.isCancelled, isTrue);
    });

    test('a listener added after the stop runs straight away', () {
      final cancellation = PublishCancellation()..cancel();
      var called = false;

      cancellation.onCancel(() => called = true);

      expect(called, isTrue);
    });

    test('a listener that is removed does not run', () {
      final cancellation = PublishCancellation();
      var called = false;
      void listener() => called = true;

      cancellation
        ..onCancel(listener)
        ..removeListener(listener)
        ..cancel();

      expect(called, isFalse);
    });

    test('throwIfCancelled only throws once stopped', () {
      final cancellation = PublishCancellation();

      expect(cancellation.throwIfCancelled, returnsNormally);

      cancellation.cancel();

      expect(cancellation.throwIfCancelled, throwsA(isA<PublishStopped>()));
    });

    test('an outcome says whether it was stopped', () {
      const finished = PublishOutcome(
        uploaded: 3,
        skipped: 1,
        deleted: 0,
        bytes: 10,
      );
      const stopped = PublishOutcome(
        uploaded: 3,
        skipped: 1,
        deleted: 0,
        bytes: 10,
        stopped: true,
      );

      expect(finished.stopped, isFalse);
      expect(stopped.stopped, isTrue);
      expect(stopped.describe(), '3 uploaded · 1 unchanged');
    });
  });
}

/// A minimal `openssh-key-v1` body, which is what the encryption check reads:
/// the magic, the cipher name, the KDF and its options, then the keys. The key
/// material itself is never decoded, so a placeholder is enough.
String _openSshKey(String cipher) {
  final encrypted = cipher != 'none';
  final body = <int>[
    ...ascii.encode('openssh-key-v1'),
    0,
    ..._sshString(ascii.encode(cipher)),
    ..._sshString(ascii.encode(encrypted ? 'bcrypt' : 'none')),
    ..._sshString(
      encrypted
          ? [..._sshString(List.filled(16, 7)), ..._uint32(16)]
          : const [],
    ),
    ..._uint32(1),
    ..._sshString(List.filled(32, 1)),
    ..._sshString(List.filled(64, 2)),
  ];

  final encoded = base64.encode(body);
  final lines = [
    for (var index = 0; index < encoded.length; index += 70)
      encoded.substring(
        index,
        index + 70 > encoded.length ? encoded.length : index + 70,
      ),
  ];

  return [
    '-----BEGIN OPENSSH PRIVATE KEY-----',
    ...lines,
    '-----END OPENSSH PRIVATE KEY-----',
    '',
  ].join('\n');
}

List<int> _uint32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

List<int> _sshString(List<int> body) => [..._uint32(body.length), ...body];
