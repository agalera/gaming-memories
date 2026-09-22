import 'dart:io';

import 'package:path/path.dart' as p;

/// What `~/.ssh/config` says about one host, as far as signing in is
/// concerned.
class SshHostConfig {
  const SshHostConfig({
    this.identityAgent,
    this.identityFiles = const [],
    this.identitiesOnly = false,
    this.userKnownHostsFiles = const [],
  });

  /// The agent socket for this host. `IdentityAgent none` leaves this null
  /// and sets [agentDisabled].
  final String? identityAgent;

  /// The keys the config names for this host, in the order it names them.
  final List<String> identityFiles;

  /// `IdentitiesOnly yes`: the named keys are the whole list, so the usual
  /// `~/.ssh/id_*` files are not added to it.
  final bool identitiesOnly;

  /// `UserKnownHostsFile`, when this host is served by one of its own rather
  /// than by `~/.ssh/known_hosts`.
  final List<String> userKnownHostsFiles;

  bool get isEmpty => identityAgent == null && identityFiles.isEmpty;
}

/// Reads the part of `~/.ssh/config` that decides what a connection signs in
/// with.
///
/// An agent is very often set up with `IdentityAgent` rather than
/// `SSH_AUTH_SOCK` — every 1Password, Secretive or gpg-agent setup does it
/// that way — and a desktop app launched from Finder does not inherit that
/// variable from a shell even when it is set. Without reading the config,
/// publishing over SFTP would not find the key that `ssh` finds.
///
/// `Match` blocks are skipped rather than guessed at: their conditions can
/// depend on things this never knows, and applying one wrongly would offer a
/// key for the wrong host.
class SshConfig {
  const SshConfig(this._blocks);

  final List<_HostBlock> _blocks;

  static const empty = SshConfig([]);

  /// The usual location. A missing or unreadable file reads as empty.
  static Future<SshConfig> load({
    String? path,
    required String? homeDirectory,
  }) async {
    final home = homeDirectory;
    if (home == null || home.trim().isEmpty) {
      return empty;
    }
    final file = File(path ?? p.join(home, '.ssh', 'config'));
    final blocks = <_HostBlock>[];
    await _parseInto(blocks, file, home, const {});
    return SshConfig(blocks);
  }

  /// What the config says for [host], with the first value for each keyword
  /// winning as OpenSSH resolves them.
  SshHostConfig forHost(String host, {String? user}) {
    String? agent;
    var agentDisabled = false;
    bool? identitiesOnly;
    final files = <String>[];
    List<String>? knownHostsFiles;

    for (final block in _blocks) {
      if (!block.matches(host)) {
        continue;
      }
      if (agent == null && !agentDisabled && block.identityAgent != null) {
        final value = block.identityAgent!;
        if (value.toLowerCase() == 'none') {
          agentDisabled = true;
        } else if (value == 'SSH_AUTH_SOCK') {
          agent = Platform.environment['SSH_AUTH_SOCK'];
          if (agent == null || agent.isEmpty) {
            agent = null;
          }
        } else {
          agent = _expand(value, block.home, host: host, user: user);
        }
      }
      identitiesOnly ??= block.identitiesOnly;
      if (knownHostsFiles == null && block.userKnownHostsFiles != null) {
        knownHostsFiles = [
          for (final file in block.userKnownHostsFiles!)
            _expand(file, block.home, host: host, user: user),
        ];
      }

      for (final file in block.identityFiles) {
        final expanded = _expand(file, block.home, host: host, user: user);
        if (!files.contains(expanded)) {
          files.add(expanded);
        }
      }
    }

    return SshHostConfig(
      identityAgent: agent,
      identityFiles: List.unmodifiable(files),
      identitiesOnly: identitiesOnly ?? false,
      userKnownHostsFiles: List.unmodifiable(knownHostsFiles ?? const []),
    );
  }

  static Future<void> _parseInto(
    List<_HostBlock> blocks,
    File file,
    String home,
    Set<String> seen,
  ) async {
    final path = file.absolute.path;
    // An Include loop would otherwise read forever.
    if (seen.contains(path) || seen.length > 16) {
      return;
    }
    final visited = {...seen, path};

    final String contents;
    try {
      if (!await file.exists()) {
        return;
      }
      contents = await file.readAsString();
    } on FileSystemException {
      return;
    }

    var current = _HostBlock(patterns: const ['*'], home: home);
    var inMatch = false;
    blocks.add(current);

    for (final line in contents.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      final (keyword, value) = _split(trimmed);
      if (value == null) {
        continue;
      }

      switch (keyword.toLowerCase()) {
        case 'host':
          inMatch = false;
          current = _HostBlock(patterns: _words(value), home: home);
          blocks.add(current);
        case 'match':
          // Everything up to the next Host belongs to a condition this does
          // not evaluate, so none of it is collected.
          inMatch = true;
        case 'include':
          if (inMatch) {
            break;
          }
          for (final pattern in _words(value)) {
            for (final included in _resolveInclude(pattern, home)) {
              await _parseInto(blocks, included, home, visited);
            }
          }
          // The included files end wherever they end; what follows in this
          // file still belongs to the block that was open.
          current = _HostBlock(patterns: current.patterns, home: home);
          blocks.add(current);
        case 'identityagent':
          if (!inMatch) {
            current.identityAgent ??= _unquote(value);
          }
        case 'identityfile':
          if (!inMatch) {
            current.identityFiles.addAll(_words(value));
          }
        case 'identitiesonly':
          if (!inMatch) {
            current.identitiesOnly = _unquote(value).toLowerCase() == 'yes';
          }
        case 'userknownhostsfile':
          if (!inMatch) {
            current.userKnownHostsFiles ??= _words(value);
          }
      }
    }
  }

  /// An Include path is relative to `~/.ssh`, and its last segment may be a
  /// glob.
  static List<File> _resolveInclude(String pattern, String home) {
    var value = _expand(pattern, home);
    if (!p.isAbsolute(value)) {
      value = p.join(home, '.ssh', value);
    }

    final directory = Directory(p.dirname(value));
    final name = p.basename(value);
    if (!name.contains('*') && !name.contains('?')) {
      return [File(value)];
    }
    if (!directory.existsSync()) {
      return const [];
    }

    final matcher = _globExpression(name);
    final files = <File>[];
    for (final entry in directory.listSync()) {
      if (entry is File && matcher.hasMatch(p.basename(entry.path))) {
        files.add(entry);
      }
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  static (String, String?) _split(String line) {
    // `Keyword value`, or `Keyword=value`.
    final separator = RegExp(r'[\s=]+');
    final match = separator.firstMatch(line);
    if (match == null) {
      return (line, null);
    }
    return (line.substring(0, match.start), line.substring(match.end).trim());
  }

  /// Splits a value into words, keeping a quoted one whole. The 1Password
  /// agent socket lives under `Group Containers`, so a quoted path holding
  /// spaces is the normal case rather than an edge one.
  static List<String> _words(String value) {
    final words = <String>[];
    final buffer = StringBuffer();
    var quoted = false;

    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      if (character == '"') {
        quoted = !quoted;
        continue;
      }
      if (!quoted && (character == ' ' || character == '\t')) {
        if (buffer.isNotEmpty) {
          words.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(character);
    }
    if (buffer.isNotEmpty) {
      words.add(buffer.toString());
    }
    return words;
  }

  static String _unquote(String value) {
    final words = _words(value);
    return words.isEmpty ? '' : words.first;
  }

  /// Expands `~` and the tokens OpenSSH substitutes in a path. The value
  /// arrives unquoted, so a path holding spaces stays whole.
  static String _expand(
    String value,
    String home, {
    String? host,
    String? user,
  }) {
    var expanded = value;
    if (expanded.startsWith('~/')) {
      expanded = p.join(home, expanded.substring(2));
    } else if (expanded == '~') {
      expanded = home;
    }
    expanded = expanded.replaceAll('%d', home);
    if (host != null) {
      expanded = expanded.replaceAll('%h', host).replaceAll('%n', host);
    }
    final localUser = user ?? Platform.environment['USER'] ?? '';
    expanded = expanded.replaceAll('%u', localUser);
    if (user != null) {
      expanded = expanded.replaceAll('%r', user);
    }
    return expanded;
  }

  static RegExp _globExpression(String pattern) {
    final expression = StringBuffer('^');
    for (final rune in pattern.runes) {
      final character = String.fromCharCode(rune);
      switch (character) {
        case '*':
          expression.write('.*');
        case '?':
          expression.write('.');
        default:
          expression.write(RegExp.escape(character));
      }
    }
    expression.write(r'$');
    return RegExp(expression.toString());
  }
}

class _HostBlock {
  _HostBlock({required this.patterns, required this.home});

  final List<String> patterns;
  final String home;
  String? identityAgent;
  final List<String> identityFiles = [];
  bool? identitiesOnly;
  List<String>? userKnownHostsFiles;

  /// A block applies when a pattern matches and no negated pattern does.
  bool matches(String host) {
    var matched = false;
    for (final pattern in patterns) {
      if (pattern.startsWith('!')) {
        if (SshConfig._globExpression(pattern.substring(1)).hasMatch(host)) {
          return false;
        }
        continue;
      }
      if (SshConfig._globExpression(pattern).hasMatch(host)) {
        matched = true;
      }
    }
    return matched;
  }
}
