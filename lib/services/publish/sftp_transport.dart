import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../models/app_settings.dart';
import 'known_hosts.dart';
import 'publish_credentials.dart';
import 'publish_plan.dart';
import 'publish_transport.dart';

/// What the remote holds right now, as the diff needs to see it.
class RemoteEntry {
  const RemoteEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modifiedSeconds,
  });

  final String path;
  final bool isDirectory;
  final int size;
  final int modifiedSeconds;
}

/// What an upload has to do to turn the remote into the plan.
class SftpDiff {
  const SftpDiff({
    required this.uploads,
    required this.skipped,
    required this.directories,
    required this.staleFiles,
    required this.staleDirectories,
  });

  final List<PublishFile> uploads;
  final List<PublishFile> skipped;

  /// Remote directories to create, parents first.
  final List<String> directories;

  /// Remote paths the plan does not cover, deepest first.
  final List<String> staleFiles;
  final List<String> staleDirectories;

  int get uploadBytes => uploads.fold(0, (sum, file) => sum + file.size);
}

/// Decides what to send without talking to a server, so the rule is testable
/// on its own. A file matches when its size and its whole-second modification
/// time both match, which is the comparison rsync makes by default.
SftpDiff diffAgainstRemote({
  required PublishPlan plan,
  required List<RemoteEntry> remote,
  required bool deleteRemoved,
}) {
  final remoteFiles = <String, RemoteEntry>{
    for (final entry in remote)
      if (!entry.isDirectory) entry.path: entry,
  };
  final remoteDirectories = <String>{
    for (final entry in remote)
      if (entry.isDirectory) entry.path,
  };

  final uploads = <PublishFile>[];
  final skipped = <PublishFile>[];
  for (final file in plan.files) {
    final existing = remoteFiles[file.remotePath];
    final unchanged =
        existing != null &&
        existing.size == file.size &&
        existing.modifiedSeconds ==
            file.modified.millisecondsSinceEpoch ~/ 1000;
    (unchanged ? skipped : uploads).add(file);
  }

  final directories = [
    for (final directory in plan.directories)
      if (!remoteDirectories.contains(directory)) directory,
  ];

  final keptPaths = plan.remotePaths;
  final keptDirectories = plan.directories.toSet();
  final staleFiles = deleteRemoved
      ? (remoteFiles.keys.where((path) => !keptPaths.contains(path)).toList()
          ..sort(_deepestFirst))
      : <String>[];
  final staleDirectories = deleteRemoved
      ? (remoteDirectories
            .where((path) => !keptDirectories.contains(path))
            .toList()
          ..sort(_deepestFirst))
      : <String>[];

  return SftpDiff(
    uploads: uploads,
    skipped: skipped,
    directories: directories,
    staleFiles: staleFiles,
    staleDirectories: staleDirectories,
  );
}

int _deepestFirst(String left, String right) {
  final depth = right.split('/').length.compareTo(left.split('/').length);
  return depth == 0 ? left.compareTo(right) : depth;
}

/// Uploads over SSH with no external program, which is what makes publishing
/// work on a machine without rsync and on Windows.
class SftpTransport implements PublishTransport {
  const SftpTransport({
    this.credentials = const PublishCredentialResolver(),
    this.hostKeys,
  });

  final PublishCredentialResolver credentials;

  /// Decides whether the host is the one it was last time. Left null, the
  /// server's key is accepted unchecked, which dartssh2 does by default and
  /// which no publish should rely on.
  final HostKeyVerifier? hostKeys;

  @override
  String get name => 'SFTP';

  @override
  Future<PublishOutcome> upload(
    PublishRequest request, {
    PublishProgressCallback? onProgress,
  }) async {
    final target = request.target;
    final signIn = await credentials.resolve(target, secret: request.secret);

    onProgress?.call(PublishProgress(message: 'Connecting to ${target.host}…'));

    SSHClient? client;
    SftpClient? sftp;
    try {
      final password = signIn.password;
      HostKeyVerdict? verdict;
      client = SSHClient(
        await SSHSocket.connect(target.host, target.port),
        username: target.username,
        identities: signIn.identities.isEmpty ? null : signIn.identities,
        onPasswordRequest: password == null ? null : () => password,
        onVerifyHostKey: (type, fingerprint) async {
          final verifier = hostKeys;
          if (verifier == null) {
            return true;
          }
          verdict = await verifier.verify(
            host: target.host,
            port: target.port,
            type: type,
            fingerprint: utf8.decode(fingerprint, allowMalformed: true),
          );
          return verdict != HostKeyVerdict.changed;
        },
      );
      sftp = await client.sftp();

      final root = _normalizeRemote(target.remotePath);
      await _ensureDirectory(sftp, root);

      onProgress?.call(const PublishProgress(message: 'Reading the remote…'));
      final remote = await _listRemote(sftp, root);

      final diff = diffAgainstRemote(
        plan: request.plan,
        remote: remote,
        deleteRemoved: target.deleteRemoved,
      );

      final fileMode = parseMode(target.fileMode, fallback: 0x1a4);
      final directoryMode = parseMode(target.directoryMode, fallback: 0x1ed);

      for (final directory in diff.directories) {
        await _ensureDirectory(sftp, '$root/$directory', mode: directoryMode);
      }

      var uploadedBytes = 0;
      var uploaded = 0;
      final totalBytes = diff.uploadBytes;
      for (var index = 0; index < diff.uploads.length; index++) {
        if (request.cancellation.isCancelled) {
          break;
        }
        final file = diff.uploads[index];
        onProgress?.call(
          PublishProgress(
            message:
                'Uploading ${file.remotePath} '
                '(${index + 1}/${diff.uploads.length})',
            value: totalBytes == 0 ? null : uploadedBytes / totalBytes,
          ),
        );
        await _upload(
          sftp,
          '$root/${file.remotePath}',
          file,
          fileMode,
          request.cancellation,
        );
        uploaded++;
        uploadedBytes += file.size;
      }

      // Nothing is removed once a stop is asked for: the uploads that would
      // have replaced them never ran.
      var deleted = 0;
      if (!request.cancellation.isCancelled) {
        for (final path in diff.staleFiles) {
          if (request.cancellation.isCancelled) {
            break;
          }
          onProgress?.call(PublishProgress(message: 'Removing $path'));
          await sftp.remove('$root/$path');
          deleted++;
        }
        for (final path in diff.staleDirectories) {
          if (request.cancellation.isCancelled) {
            break;
          }
          try {
            await sftp.rmdir('$root/$path');
            deleted++;
          } on SftpStatusError {
            // A directory holding something the publish does not know about
            // is left alone rather than failing the whole run.
          }
        }
      }

      return PublishOutcome(
        uploaded: uploaded,
        skipped: diff.skipped.length,
        deleted: deleted,
        bytes: uploadedBytes,
        stopped: request.cancellation.isCancelled,
      );
    } on SSHHostkeyError catch (error) {
      throw PublishException(
        'The host key for ${target.host} is not the one it was last time. '
        'Either the server was rebuilt, or something is pretending to be it. '
        'Nothing was uploaded.',
        detail: error.message,
      );
    } on SSHAuthFailError catch (error) {
      throw PublishException(
        target.credential == PublishCredentialKind.password
            ? 'The server refused the password for ${target.username}.'
            : 'The server refused the key for ${target.username}.',
        detail: error.message,
      );
    } on SSHAuthAbortError catch (error) {
      throw PublishException(
        'The connection to ${target.host} was lost while authenticating.',
        detail: error.message,
      );
    } on SftpStatusError catch (error) {
      throw PublishException(
        'The remote refused an operation.',
        detail: error.message,
      );
    } on SocketException catch (error) {
      throw PublishException(
        'Could not reach ${target.host} on port ${target.port}.',
        detail: error.message,
      );
    } finally {
      sftp?.close();
      client?.close();
    }
  }

  Future<void> _upload(
    SftpClient sftp,
    String remotePath,
    PublishFile file,
    int mode,
    PublishCancellation cancellation,
  ) async {
    final source = File(file.localPath);
    final handle = await sftp.open(
      remotePath,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate |
          SftpFileOpenMode.write,
    );
    try {
      final writer = handle.write(source.openRead().map(Uint8List.fromList));
      // A long clip would otherwise hold a stop up until it finished.
      void abort() => unawaited(writer.abort());
      cancellation.onCancel(abort);
      try {
        await writer.done;
      } finally {
        cancellation.removeListener(abort);
      }
      if (cancellation.isCancelled) {
        return;
      }
      // The mode and the modification time are set after the write, so the
      // next publish can tell this file is already current.
      await handle.setStat(
        SftpFileAttrs(
          mode: SftpFileMode.value(mode),
          accessTime: file.modified.millisecondsSinceEpoch ~/ 1000,
          modifyTime: file.modified.millisecondsSinceEpoch ~/ 1000,
        ),
      );
    } finally {
      await handle.close();
    }
  }

  Future<void> _ensureDirectory(
    SftpClient sftp,
    String path, {
    int? mode,
  }) async {
    try {
      final attrs = await sftp.stat(path);
      if (attrs.mode?.type == SftpFileType.directory) {
        return;
      }
      throw PublishException('$path exists on the remote but is not a folder.');
    } on SftpStatusError {
      // Not there yet, which is the point of this call.
    }

    try {
      await sftp.mkdir(
        path,
        mode == null ? null : SftpFileAttrs(mode: SftpFileMode.value(mode)),
      );
    } on SftpStatusError catch (error) {
      throw PublishException(
        'Could not create $path on the remote.',
        detail: error.message,
      );
    }
  }

  Future<List<RemoteEntry>> _listRemote(SftpClient sftp, String root) async {
    final entries = <RemoteEntry>[];
    final pending = <String>[''];

    while (pending.isNotEmpty) {
      final relative = pending.removeLast();
      final absolute = relative.isEmpty ? root : '$root/$relative';
      final List<SftpName> names;
      try {
        names = await sftp.listdir(absolute);
      } on SftpStatusError {
        continue;
      }

      for (final name in names) {
        if (name.filename == '.' || name.filename == '..') {
          continue;
        }
        final path = relative.isEmpty
            ? name.filename
            : '$relative/${name.filename}';
        final isDirectory = name.attr.mode?.type == SftpFileType.directory;
        entries.add(
          RemoteEntry(
            path: path,
            isDirectory: isDirectory,
            size: name.attr.size ?? 0,
            modifiedSeconds: name.attr.modifyTime ?? 0,
          ),
        );
        if (isDirectory) {
          pending.add(path);
        }
      }
    }

    return entries;
  }

  /// Turns `644` into the bits SFTP takes. A value that is not octal falls
  /// back rather than leaving a file unreadable to a web server.
  static int parseMode(String value, {required int fallback}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !RegExp(r'^[0-7]{3,4}$').hasMatch(trimmed)) {
      return fallback;
    }
    return int.parse(trimmed, radix: 8);
  }

  static String _normalizeRemote(String path) {
    final trimmed = path.trim().replaceAll(RegExp(r'/+$'), '');
    return trimmed.isEmpty ? '/' : trimmed;
  }
}
