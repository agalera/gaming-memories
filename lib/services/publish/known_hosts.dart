import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// One host key someone already decided to trust.
class KnownHostKey {
  const KnownHostKey({required this.type, required this.fingerprint});

  /// As `ssh-ed25519` or `ssh-rsa`.
  final String type;

  /// OpenSSH style, as `SHA256:<base64>` without padding — the same string
  /// dartssh2 hands a host key verifier.
  final String fingerprint;

  @override
  bool operator ==(Object other) =>
      other is KnownHostKey &&
      other.type == type &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(type, fingerprint);

  Map<String, Object?> toJson() => {'type': type, 'fingerprint': fingerprint};

  factory KnownHostKey.fromJson(Map<String, Object?> json) => KnownHostKey(
    type: json['type'] as String? ?? '',
    fingerprint: json['fingerprint'] as String? ?? '',
  );
}

/// Reads the keys OpenSSH already knows for a host.
///
/// Only read: a publish never edits `known_hosts`, because that file is the
/// user's and rsync's own `accept-new` already maintains it.
class KnownHosts {
  const KnownHosts(this._entries);

  final List<_KnownHostEntry> _entries;

  static const empty = KnownHosts([]);

  /// Reads every file given, skipping the ones that are not there. `/dev/null`
  /// is a normal value for `UserKnownHostsFile` and simply holds nothing.
  static Future<KnownHosts> load(Iterable<String> paths) async {
    final entries = <_KnownHostEntry>[];
    for (final path in paths) {
      final file = File(path);
      try {
        if (!await file.exists()) {
          continue;
        }
        for (final line in (await file.readAsString()).split('\n')) {
          final entry = _KnownHostEntry.parse(line);
          if (entry != null) {
            entries.add(entry);
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    return KnownHosts(entries);
  }

  /// The default file, for a home directory that has one.
  static List<String> defaultPaths(String? homeDirectory) {
    final home = homeDirectory;
    if (home == null || home.trim().isEmpty) {
      return const [];
    }
    return [p.join(home, '.ssh', 'known_hosts')];
  }

  /// Every key recorded for [host], including the `[host]:port` form a
  /// non-default port is stored under.
  List<KnownHostKey> keysFor(String host, {int port = 22}) {
    final names = {host, if (port != 22) '[$host]:$port'};
    final keys = <KnownHostKey>[];
    for (final entry in _entries) {
      if (entry.revoked) {
        continue;
      }
      if (names.any(entry.matches)) {
        keys.add(entry.key);
      }
    }
    return keys;
  }
}

/// The hosts this app accepted on first use.
///
/// `known_hosts` records the key itself, which a verifier that is only handed
/// a fingerprint cannot reconstruct, so what was trusted is kept here instead
/// of writing something half-formed into the user's file.
class HostKeyStore {
  const HostKeyStore({required this.filePath});

  final String filePath;

  Future<Map<String, List<KnownHostKey>>> _read() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return {};
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, Object?>) {
        return {};
      }
      return {
        for (final entry in value.entries)
          if (entry.value is List)
            entry.key: [
              for (final key in entry.value! as List)
                if (key is Map)
                  KnownHostKey.fromJson(
                    key.map((k, v) => MapEntry(k.toString(), v)),
                  ),
            ],
      };
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  Future<List<KnownHostKey>> keysFor(String host, {int port = 22}) async =>
      (await _read())[_id(host, port)] ?? const [];

  Future<void> remember(String host, int port, KnownHostKey key) async {
    final all = await _read();
    final existing = all[_id(host, port)] ?? const <KnownHostKey>[];
    if (existing.contains(key)) {
      return;
    }
    all[_id(host, port)] = [...existing, key];

    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        for (final entry in all.entries)
          entry.key: [for (final key in entry.value) key.toJson()],
      }),
      flush: true,
    );
  }

  static String _id(String host, int port) => '$host:$port';
}

/// What a verification decided, so the caller can say why it refused.
enum HostKeyVerdict {
  /// The key is one this host is already known by.
  known,

  /// The host was not known, and has now been trusted.
  trusted,

  /// The host is known by a different key. Refused.
  changed,
}

/// Trust on first use: an unknown host is accepted and remembered, and a host
/// whose key later differs is refused.
///
/// The first connection is not verified against anything, so a man in the
/// middle present at that moment would be trusted from then on. That is the
/// same bargain `ssh` makes when someone answers its prompt with `yes`.
class HostKeyVerifier {
  const HostKeyVerifier({
    required this.store,
    this.knownHosts = KnownHosts.empty,
  });

  final HostKeyStore store;
  final KnownHosts knownHosts;

  Future<HostKeyVerdict> verify({
    required String host,
    required int port,
    required String type,
    required String fingerprint,
  }) async {
    final offered = KnownHostKey(type: type, fingerprint: fingerprint);
    final known = [
      ...knownHosts.keysFor(host, port: port),
      ...await store.keysFor(host, port: port),
    ];

    if (known.isEmpty) {
      await store.remember(host, port, offered);
      return HostKeyVerdict.trusted;
    }
    if (known.any((key) => key.fingerprint == offered.fingerprint)) {
      return HostKeyVerdict.known;
    }
    // Some servers offer several key types. A key of a type that is not
    // recorded yet is new rather than changed, so it is trusted and kept.
    if (!known.any((key) => key.type == offered.type)) {
      await store.remember(host, port, offered);
      return HostKeyVerdict.trusted;
    }
    return HostKeyVerdict.changed;
  }
}

class _KnownHostEntry {
  const _KnownHostEntry({
    required this.patterns,
    required this.key,
    required this.revoked,
    this.hashedSalt,
    this.hashedHost,
  });

  final List<String> patterns;
  final KnownHostKey key;
  final bool revoked;

  /// Set instead of [patterns] for a `|1|salt|hash` entry, which is what
  /// `HashKnownHosts yes` writes.
  final List<int>? hashedSalt;
  final List<int>? hashedHost;

  static _KnownHostEntry? parse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      return null;
    }

    var fields = trimmed.split(RegExp(r'\s+'));
    var revoked = false;
    if (fields.first.startsWith('@')) {
      // @revoked withdraws a key; @cert-authority is about signing rather
      // than about this host, so neither can stand in for a known key.
      revoked = true;
      fields = fields.sublist(1);
    }
    if (fields.length < 3) {
      return null;
    }

    final names = fields[0];
    final type = fields[1];
    final blob = fields[2];

    final String fingerprint;
    try {
      fingerprint = fingerprintOf(blob);
    } on FormatException {
      return null;
    }

    final key = KnownHostKey(type: type, fingerprint: fingerprint);
    if (names.startsWith('|1|')) {
      final parts = names.split('|');
      if (parts.length < 4) {
        return null;
      }
      try {
        return _KnownHostEntry(
          patterns: const [],
          key: key,
          revoked: revoked,
          hashedSalt: base64.decode(parts[2]),
          hashedHost: base64.decode(parts[3]),
        );
      } on FormatException {
        return null;
      }
    }

    return _KnownHostEntry(
      patterns: names.split(','),
      key: key,
      revoked: revoked,
    );
  }

  bool matches(String name) {
    final salt = hashedSalt;
    final hashed = hashedHost;
    if (salt != null && hashed != null) {
      final digest = Hmac(sha1, salt).convert(utf8.encode(name)).bytes;
      if (digest.length != hashed.length) {
        return false;
      }
      for (var index = 0; index < digest.length; index++) {
        if (digest[index] != hashed[index]) {
          return false;
        }
      }
      return true;
    }

    for (final pattern in patterns) {
      if (pattern.startsWith('!')) {
        if (_globExpression(pattern.substring(1)).hasMatch(name)) {
          return false;
        }
        continue;
      }
      if (_globExpression(pattern).hasMatch(name)) {
        return true;
      }
    }
    return false;
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

/// The OpenSSH fingerprint of a base64 key blob, in the `SHA256:<base64>`
/// form without padding that a verifier is handed.
String fingerprintOf(String base64Key) {
  final digest = sha256.convert(base64.decode(base64Key));
  return 'SHA256:${base64.encode(digest.bytes).replaceAll('=', '')}';
}
