import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/app_settings.dart';
import 'publish_plan.dart';
import 'publish_transport.dart';

/// What `rsync --version` says about the program on PATH.
class RsyncVersion {
  const RsyncVersion({
    required this.major,
    required this.minor,
    required this.isOpenRsync,
  });

  final int major;
  final int minor;

  /// Apple ships openrsync, which answers to the same name and accepts the
  /// flags below without doing what they say: `--delete-excluded` transfers
  /// nothing extra and deletes nothing, protect filters are ignored, and
  /// `--chmod` is rejected outright. A publish through it would silently
  /// leave stale files on the remote, so it is never used.
  final bool isOpenRsync;

  /// The filter rules and `--chmod` the two passes rely on arrived in rsync 3.
  bool get isUsable => !isOpenRsync && major >= 3;

  static RsyncVersion? parse(String output) {
    final firstLine = const LineSplitter()
        .convert(output)
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) {
      return null;
    }

    final isOpenRsync = output.toLowerCase().contains('openrsync');
    final match = RegExp(r'version\s+(\d+)\.(\d+)').firstMatch(output);
    if (match == null) {
      return RsyncVersion(major: 0, minor: 0, isOpenRsync: isOpenRsync);
    }

    return RsyncVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      isOpenRsync: isOpenRsync,
    );
  }
}

/// One rsync invocation, and which of the two local roots it sends.
class RsyncPass {
  const RsyncPass({
    required this.label,
    required this.root,
    required this.arguments,
  });

  /// What the progress line calls this pass.
  final String label;
  final PublishSourceRoot root;
  final List<String> arguments;
}

/// Runs a program and hands back what it printed. Swapped out in tests so the
/// argument building can be checked without a server.
abstract interface class ProcessRunner {
  Future<ProcessResult> run(String executable, List<String> arguments);

  Future<Process> start(String executable, List<String> arguments);
}

class NativeProcessRunner implements ProcessRunner {
  const NativeProcessRunner();

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) =>
      Process.run(executable, arguments);

  @override
  Future<Process> start(String executable, List<String> arguments) =>
      Process.start(executable, arguments);
}

/// Uploads with rsync, which is faster than SFTP on a large library because it
/// compares the whole tree in one round trip.
///
/// The remote merges two local roots, so it takes two passes. The captures go
/// first and mirror: they delete what the library no longer holds, including
/// an album that has just been excluded. The rendered pages follow, so a page
/// never arrives before the media it links to — a visitor reading the site
/// during a publish sees the previous pages, which still point at files that
/// are there, rather than new ones pointing at files still on their way.
///
/// The captures pass is told to protect each page already on the host that the
/// second pass is about to rewrite. A blanket `P index.html` would also
/// protect the page of an album that is gone, which would strand that page and
/// keep its folder alive on the remote forever.
class RsyncTransport implements PublishTransport {
  const RsyncTransport({this.runner = const NativeProcessRunner()});

  final ProcessRunner runner;

  @override
  String get name => 'rsync';

  /// Names never sent to the remote: the app's own caches, the platform
  /// leftovers that are none of a web server's business, and any page already
  /// sitting in the library.
  ///
  /// A library that was once a gallery built by something else still holds
  /// that tool's `index.html` files. The captures pass would copy them over
  /// the pages the first pass just wrote, because a protect rule only stops a
  /// file being deleted, not being overwritten by one the sender has.
  static const excludedPatterns = [
    '.DS_Store',
    'Thumbs.db',
    'index.html',
    '*.metadata.json',
    '*.thumb.jpg.frame.jpg',
    '*.tmp',
  ];

  /// Whether this machine has an rsync that can do the job.
  Future<RsyncVersion?> probe() async {
    try {
      final result = await runner.run('rsync', ['--version']);
      if (result.exitCode != 0) {
        return null;
      }
      return RsyncVersion.parse('${result.stdout}');
    } on ProcessException {
      return null;
    }
  }

  /// The rules that keep the pages the first pass wrote. rsync reads the
  /// pattern as a glob, so a wildcard character in an album name is escaped;
  /// left as it is, `Hades [GOTY]` would match nothing and the album's page
  /// would be deleted the moment the second pass ran.
  static String protectRules(Iterable<String> pagePaths) {
    final rules = pagePaths.map((path) => 'P /${_escapeGlob(path)}').toList()
      ..sort();
    return '${rules.join('\n')}\n';
  }

  static String _escapeGlob(String value) {
    final escaped = StringBuffer();
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      if (character == r'\' ||
          character == '*' ||
          character == '?' ||
          character == '[') {
        escaped.write(r'\');
      }
      escaped.write(character);
    }
    return escaped.toString();
  }

  /// The two invocations, in order: the captures, then the pages. Built
  /// separately from running them so the flags can be asserted in a test.
  List<RsyncPass> buildArguments({
    required PublishTargetSettings target,
    required String libraryPath,
    required String buildPath,
    required List<String> excluded,
    required String filterPath,
  }) {
    final destination =
        '${target.username}@${target.host}:'
        '${_normalizeRemote(target.remotePath)}/';
    final shared = [
      '-rltz',
      '--chmod=D${target.directoryMode},F${target.fileMode}',
      '-e',
      _sshCommand(target),
    ];

    // No --delete here: the captures pass owns everything this one does not
    // write, and a page for an album that is gone goes with that album.
    final pagesPass = <String>[
      ...shared,
      '${_trimTrailingSlash(buildPath)}/',
      destination,
    ];

    final capturesPass = <String>[
      ...shared,
      if (target.deleteRemoved) ...[
        // Excluded albums and stale caches have to go, and the pages the
        // first pass wrote have to stay.
        '--delete-excluded',
        '--filter=. $filterPath',
      ],
      for (final pattern in excludedPatterns) '--exclude=$pattern',
      for (final album in excluded) '--exclude=/${_trimSlashes(album)}/',
      '${_trimTrailingSlash(libraryPath)}/',
      destination,
    ];

    return [
      RsyncPass(
        label: 'captures',
        root: PublishSourceRoot.library,
        arguments: capturesPass,
      ),
      RsyncPass(
        label: 'pages',
        root: PublishSourceRoot.build,
        arguments: pagesPass,
      ),
    ];
  }

  /// How much of the whole publish each pass carries, by the bytes the plan
  /// holds for its root. Without this the second pass would restart the
  /// percentage at zero.
  static Map<PublishSourceRoot, double> shares(PublishPlan plan) {
    var library = 0;
    var build = 0;
    for (final file in plan.files) {
      switch (file.root) {
        case PublishSourceRoot.library:
          library += file.size;
        case PublishSourceRoot.build:
          build += file.size;
      }
    }

    final total = library + build;
    if (total == 0) {
      return const {
        PublishSourceRoot.library: 0.5,
        PublishSourceRoot.build: 0.5,
      };
    }
    return {
      PublishSourceRoot.library: library / total,
      PublishSourceRoot.build: build / total,
    };
  }

  @override
  Future<PublishOutcome> upload(
    PublishRequest request, {
    PublishProgressCallback? onProgress,
  }) async {
    final version = await probe();
    if (version == null) {
      throw const PublishException('rsync was not found on this machine.');
    }
    if (!version.isUsable) {
      throw PublishException(
        version.isOpenRsync
            ? 'The rsync on this machine is openrsync, which cannot mirror a '
                  'publish safely.'
            : 'rsync ${version.major}.${version.minor} is too old; 3.0 or '
                  'newer is needed.',
      );
    }

    // Beside the build directory rather than inside it, or the rules file
    // would be uploaded with the pages.
    final filter = File(
      '${_trimTrailingSlash(request.buildPath)}.rsync-filter',
    );
    await filter.writeAsString(
      protectRules(
        request.plan.files
            .where((file) => file.root == PublishSourceRoot.build)
            .map((file) => file.remotePath),
      ),
      flush: true,
    );

    try {
      final passes = buildArguments(
        target: request.target,
        libraryPath: request.libraryPath,
        buildPath: request.buildPath,
        excluded: request.plan.excludedAlbums,
        filterPath: filter.path,
      );

      var uploaded = 0;
      var deleted = 0;
      final weights = shares(request.plan);
      var done = 0.0;
      // rsync's own percentage slips backwards while it is still building the
      // file list, because the total it divides by is not known yet. What is
      // shown only ever goes up.
      var highest = 0.0;

      for (final pass in passes) {
        if (request.cancellation.isCancelled) {
          break;
        }
        final share = weights[pass.root] ?? 0.5;
        final offset = done;
        onProgress?.call(
          PublishProgress(
            message: 'Sending the ${pass.label}…',
            value: highest,
          ),
        );
        final counts = await _runPass(
          ['--info=progress2,del,name', ...pass.arguments],
          label: pass.label,
          cancellation: request.cancellation,
          onFraction: (fraction) {
            final overall = offset + fraction * share;
            if (overall > highest) {
              highest = overall;
            }
            onProgress?.call(
              PublishProgress(
                message: 'Sending the ${pass.label}…',
                value: highest,
              ),
            );
          },
        );
        done = offset + share;
        if (done > highest) {
          highest = done;
        }
        uploaded += counts.uploaded;
        deleted += counts.deleted;
      }

      return PublishOutcome(
        uploaded: uploaded,
        skipped: request.plan.files.length - uploaded,
        deleted: deleted,
        bytes: 0,
        stopped: request.cancellation.isCancelled,
      );
    } finally {
      if (await filter.exists()) {
        await filter.delete();
      }
    }
  }

  Future<({int uploaded, int deleted})> _runPass(
    List<String> arguments, {
    required String label,
    required PublishCancellation cancellation,
    void Function(double fraction)? onFraction,
  }) async {
    final Process process;
    try {
      process = await runner.start('rsync', arguments);
    } on ProcessException catch (error) {
      throw PublishException(
        'rsync could not be started.',
        detail: error.message,
      );
    }

    // rsync does the whole pass itself, so stopping means ending the process.
    void stop() => process.kill();
    cancellation.onCancel(stop);

    var uploaded = 0;
    var deleted = 0;
    final errors = StringBuffer();

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final progress = progressOf(line);
          if (progress != null) {
            onFraction?.call(progress);
            return;
          }
          if (line.startsWith('deleting ')) {
            deleted++;
            return;
          }
          if (line.trim().isNotEmpty && !line.endsWith('/')) {
            uploaded++;
          }
        })
        .asFuture<void>();

    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(errors.write)
        .asFuture<void>();

    final exitCode = await process.exitCode;
    cancellation.removeListener(stop);
    await Future.wait([stdoutDone, stderrDone]);

    // A killed rsync exits non-zero, which is what was asked for rather than
    // something to report as a failure.
    if (cancellation.isCancelled) {
      return (uploaded: uploaded, deleted: deleted);
    }

    if (exitCode != 0) {
      throw PublishException(
        'rsync failed while sending the $label.',
        detail: errors.toString().trim(),
      );
    }

    return (uploaded: uploaded, deleted: deleted);
  }

  /// A `--info=progress2` line, which leads with the bytes moved so far and
  /// then the percentage. Anything else rsync prints is a file name, and a
  /// file whose name holds a percent sign must not read as progress.
  static double? progressOf(String line) {
    final match = RegExp(r'^\s*[\d,.]+\s+(\d{1,3})%').firstMatch(line);
    if (match == null) {
      return null;
    }
    return (int.parse(match.group(1)!) / 100).clamp(0.0, 1.0);
  }

  static String _sshCommand(PublishTargetSettings target) {
    final parts = [
      'ssh',
      '-p',
      '${target.port}',
      // The app has no terminal to type a passphrase into, so rsync must fail
      // instead of hanging on a prompt nobody can see.
      '-o',
      'BatchMode=yes',
      // BatchMode alone also refuses a host that is not in known_hosts yet,
      // because ssh cannot ask. accept-new takes the first key on trust the
      // way answering that prompt would, and still refuses one that changed.
      '-o',
      'StrictHostKeyChecking=accept-new',
      // Only a key the user named is passed. Left out, ssh reads the agent,
      // ~/.ssh/config and the default identity files itself, which is what
      // the automatic choice means.
      if (target.credential == PublishCredentialKind.manualKey &&
          target.keyPath.trim().isNotEmpty) ...[
        '-i',
        target.keyPath.trim(),
      ],
    ];
    return parts.join(' ');
  }

  static String _normalizeRemote(String path) =>
      _trimTrailingSlash(path.trim());

  static String _trimTrailingSlash(String value) =>
      value.replaceAll(RegExp(r'/+$'), '');

  static String _trimSlashes(String value) =>
      value.replaceAll(RegExp(r'^/+|/+$'), '');
}
