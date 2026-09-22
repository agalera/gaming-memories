import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/publish/known_hosts.dart';
import 'package:path/path.dart' as p;

/// A key blob and the fingerprint OpenSSH gives it, so a test can write one
/// into known_hosts and check the other.
({String blob, String fingerprint}) keyBlob(int seed) {
  final blob = base64.encode(List.filled(32, seed));
  return (blob: blob, fingerprint: fingerprintOf(blob));
}

/// The `|1|salt|hash` form `HashKnownHosts yes` writes.
String hashedName(String host, List<int> salt) {
  final digest = Hmac(sha1, salt).convert(utf8.encode(host)).bytes;
  return '|1|${base64.encode(salt)}|${base64.encode(digest)}';
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('known-hosts');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<String> writeKnownHosts(String contents) async {
    final file = File(p.join(root.path, 'known_hosts'));
    await file.writeAsString(contents);
    return file.path;
  }

  HostKeyStore store() =>
      HostKeyStore(filePath: p.join(root.path, 'trusted.json'));

  group('reading known_hosts', () {
    test('a missing file holds nothing', () async {
      final hosts = await KnownHosts.load([p.join(root.path, 'nothing')]);

      expect(hosts.keysFor('example.com'), isEmpty);
    });

    test('finds the key recorded for a host', () async {
      final key = keyBlob(1);
      final path = await writeKnownHosts(
        'example.com ssh-ed25519 ${key.blob}\n',
      );

      final hosts = await KnownHosts.load([path]);

      expect(hosts.keysFor('example.com').single.fingerprint, key.fingerprint);
      expect(hosts.keysFor('example.com').single.type, 'ssh-ed25519');
      expect(hosts.keysFor('other.com'), isEmpty);
    });

    test('reads a host listed among several names', () async {
      final key = keyBlob(2);
      final path = await writeKnownHosts(
        'one.example.com,two.example.com ssh-rsa ${key.blob}\n',
      );

      final hosts = await KnownHosts.load([path]);

      expect(hosts.keysFor('two.example.com'), hasLength(1));
    });

    test('reads a hashed entry', () async {
      final key = keyBlob(3);
      final name = hashedName('example.com', List.filled(20, 9));
      final path = await writeKnownHosts('$name ssh-ed25519 ${key.blob}\n');

      final hosts = await KnownHosts.load([path]);

      expect(hosts.keysFor('example.com').single.fingerprint, key.fingerprint);
      expect(hosts.keysFor('elsewhere.com'), isEmpty);
    });

    test('a non-default port is looked up under [host]:port', () async {
      final key = keyBlob(4);
      final path = await writeKnownHosts(
        '[example.com]:2222 ssh-ed25519 ${key.blob}\n',
      );

      final hosts = await KnownHosts.load([path]);

      expect(hosts.keysFor('example.com', port: 2222), hasLength(1));
      expect(hosts.keysFor('example.com'), isEmpty);
    });

    test('a revoked key does not count as known', () async {
      final key = keyBlob(5);
      final path = await writeKnownHosts(
        '@revoked example.com ssh-ed25519 ${key.blob}\n',
      );

      final hosts = await KnownHosts.load([path]);

      expect(hosts.keysFor('example.com'), isEmpty);
    });

    test('comments, blanks and malformed lines are skipped', () async {
      final key = keyBlob(6);
      final path = await writeKnownHosts('''
# a comment

nonsense
example.com ssh-ed25519 ${key.blob}
example.com ssh-ed25519 !!!not-base64!!!
''');

      final hosts = await KnownHosts.load([path]);

      expect(hosts.keysFor('example.com'), hasLength(1));
    });

    test('several files are read together', () async {
      final first = keyBlob(7);
      final second = keyBlob(8);
      final a = File(p.join(root.path, 'a'));
      final b = File(p.join(root.path, 'b'));
      await a.writeAsString('one.example.com ssh-ed25519 ${first.blob}\n');
      await b.writeAsString('two.example.com ssh-ed25519 ${second.blob}\n');

      final hosts = await KnownHosts.load([a.path, b.path, '/dev/null']);

      expect(hosts.keysFor('one.example.com'), hasLength(1));
      expect(hosts.keysFor('two.example.com'), hasLength(1));
    });
  });

  group('trust on first use', () {
    test('an unknown host is trusted and remembered', () async {
      final key = keyBlob(10);
      final verifier = HostKeyVerifier(store: store());

      expect(
        await verifier.verify(
          host: 'example.com',
          port: 22,
          type: 'ssh-ed25519',
          fingerprint: key.fingerprint,
        ),
        HostKeyVerdict.trusted,
      );

      // Second time it is no longer new.
      expect(
        await verifier.verify(
          host: 'example.com',
          port: 22,
          type: 'ssh-ed25519',
          fingerprint: key.fingerprint,
        ),
        HostKeyVerdict.known,
      );
    });

    test('a key that changed is refused', () async {
      final first = keyBlob(11);
      final second = keyBlob(12);
      final verifier = HostKeyVerifier(store: store());

      await verifier.verify(
        host: 'example.com',
        port: 22,
        type: 'ssh-ed25519',
        fingerprint: first.fingerprint,
      );

      expect(
        await verifier.verify(
          host: 'example.com',
          port: 22,
          type: 'ssh-ed25519',
          fingerprint: second.fingerprint,
        ),
        HostKeyVerdict.changed,
      );
    });

    test('a key ssh already knows is known here too', () async {
      final key = keyBlob(13);
      final path = await writeKnownHosts(
        'example.com ssh-ed25519 ${key.blob}\n',
      );
      final verifier = HostKeyVerifier(
        store: store(),
        knownHosts: await KnownHosts.load([path]),
      );

      expect(
        await verifier.verify(
          host: 'example.com',
          port: 22,
          type: 'ssh-ed25519',
          fingerprint: key.fingerprint,
        ),
        HostKeyVerdict.known,
      );
    });

    test('a key that differs from the one ssh knows is refused', () async {
      final known = keyBlob(14);
      final offered = keyBlob(15);
      final path = await writeKnownHosts(
        'example.com ssh-ed25519 ${known.blob}\n',
      );
      final verifier = HostKeyVerifier(
        store: store(),
        knownHosts: await KnownHosts.load([path]),
      );

      expect(
        await verifier.verify(
          host: 'example.com',
          port: 22,
          type: 'ssh-ed25519',
          fingerprint: offered.fingerprint,
        ),
        HostKeyVerdict.changed,
      );
    });

    test('another key type for a known host is new, not changed', () async {
      final ed25519 = keyBlob(16);
      final rsa = keyBlob(17);
      final path = await writeKnownHosts(
        'example.com ssh-ed25519 ${ed25519.blob}\n',
      );
      final verifier = HostKeyVerifier(
        store: store(),
        knownHosts: await KnownHosts.load([path]),
      );

      // A server offering several key types must not read as an attack.
      expect(
        await verifier.verify(
          host: 'example.com',
          port: 22,
          type: 'ssh-rsa',
          fingerprint: rsa.fingerprint,
        ),
        HostKeyVerdict.trusted,
      );
    });

    test('hosts are remembered apart, by port as well as name', () async {
      final first = keyBlob(18);
      final second = keyBlob(19);
      final verifier = HostKeyVerifier(store: store());

      await verifier.verify(
        host: 'example.com',
        port: 22,
        type: 'ssh-ed25519',
        fingerprint: first.fingerprint,
      );

      expect(
        await verifier.verify(
          host: 'example.com',
          port: 2222,
          type: 'ssh-ed25519',
          fingerprint: second.fingerprint,
        ),
        HostKeyVerdict.trusted,
      );
      expect(
        await verifier.verify(
          host: 'other.com',
          port: 22,
          type: 'ssh-ed25519',
          fingerprint: second.fingerprint,
        ),
        HostKeyVerdict.trusted,
      );
    });

    test('what was trusted survives a restart', () async {
      final key = keyBlob(20);
      await HostKeyVerifier(store: store()).verify(
        host: 'example.com',
        port: 22,
        type: 'ssh-ed25519',
        fingerprint: key.fingerprint,
      );

      // A fresh verifier over the same file, as the next run of the app has.
      expect(
        await HostKeyVerifier(store: store()).verify(
          host: 'example.com',
          port: 22,
          type: 'ssh-ed25519',
          fingerprint: key.fingerprint,
        ),
        HostKeyVerdict.known,
      );
    });

    test('a store file that will not parse starts empty', () async {
      await File(p.join(root.path, 'trusted.json')).writeAsString('not json');
      final key = keyBlob(21);

      expect(
        await HostKeyVerifier(store: store()).verify(
          host: 'example.com',
          port: 22,
          type: 'ssh-ed25519',
          fingerprint: key.fingerprint,
        ),
        HostKeyVerdict.trusted,
      );
    });
  });

  test('the fingerprint matches what OpenSSH reports', () {
    // ssh-keygen -lf prints SHA256:<base64 without padding>.
    final fingerprint = fingerprintOf(base64.encode(utf8.encode('key bytes')));

    expect(fingerprint, startsWith('SHA256:'));
    expect(fingerprint, isNot(contains('=')));
  });
}
