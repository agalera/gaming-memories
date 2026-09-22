import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/publish/ssh_agent_client.dart';
import 'package:path/path.dart' as p;

/// A stand-in agent speaking the real wire protocol over a real unix socket,
/// so the client is tested end to end without ssh-agent.
class FakeAgentServer {
  FakeAgentServer(this._socket);

  final ServerSocket _socket;
  final requests = <int>[];

  /// The identities it answers with: a key blob and its comment.
  var identities = <({List<int> blob, String comment})>[];

  /// What a sign request comes back with, and the flags the last one carried.
  List<int> signature = const [];
  int? lastSignFlags;
  List<int>? lastSignedBlob;

  static Future<FakeAgentServer> start(String path) async {
    final socket = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final server = FakeAgentServer(socket);
    unawaited(server._serve());
    return server;
  }

  String get path => (_socket.address).address;

  Future<void> close() => _socket.close();

  Future<void> _serve() async {
    await for (final connection in _socket) {
      unawaited(_handle(connection));
    }
  }

  Future<void> _handle(Socket connection) async {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in connection) {
      buffer.add(chunk);
      final bytes = buffer.toBytes();
      if (bytes.length < 4) {
        continue;
      }
      final length = ByteData.sublistView(bytes).getUint32(0);
      if (bytes.length < 4 + length) {
        buffer
          ..clear()
          ..add(bytes);
        continue;
      }

      final payload = Uint8List.sublistView(bytes, 4, 4 + length);
      requests.add(payload[0]);
      connection.add(_reply(payload));
      await connection.flush();
      buffer.clear();
    }
  }

  Uint8List _reply(Uint8List payload) {
    switch (payload[0]) {
      case 11: // request identities
        final body = BytesBuilder()
          ..addByte(12)
          ..add(_uint32(identities.length));
        for (final identity in identities) {
          body
            ..add(_string(identity.blob))
            ..add(_string(identity.comment.codeUnits));
        }
        return _frame(body.takeBytes());
      case 13: // sign request
        var offset = 1;
        (List<int>, int) readString(int at) {
          final size = ByteData.sublistView(payload).getUint32(at);
          return (
            Uint8List.sublistView(payload, at + 4, at + 4 + size),
            at + 4 + size,
          );
        }

        final (blob, afterBlob) = readString(offset);
        final (_, afterData) = readString(afterBlob);
        lastSignedBlob = blob;
        lastSignFlags = ByteData.sublistView(payload).getUint32(afterData);
        offset = afterData;
        return _frame(
          (BytesBuilder()
                ..addByte(14)
                ..add(_string(signature)))
              .takeBytes(),
        );
      default:
        return _frame(Uint8List.fromList([5])); // failure
    }
  }

  static Uint8List _frame(List<int> body) =>
      Uint8List.fromList([..._uint32(body.length), ...body]);

  static List<int> _uint32(int value) => [
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ];

  static List<int> _string(List<int> body) => [
    ..._uint32(body.length),
    ...body,
  ];
}

/// An `ssh-ed25519` public key blob: the type string, then the key itself.
List<int> ed25519Blob() => [
  ...FakeAgentServer._string('ssh-ed25519'.codeUnits),
  ...FakeAgentServer._string(List.filled(32, 9)),
];

/// An `ssh-rsa` blob, whose signature algorithm has to be upgraded.
List<int> rsaBlob() => [
  ...FakeAgentServer._string('ssh-rsa'.codeUnits),
  ...FakeAgentServer._string([1, 0, 1]),
  ...FakeAgentServer._string(List.filled(64, 3)),
];

void main() {
  late Directory root;
  late String socketPath;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ssh-agent');
    // A unix socket path is short by necessity, so it goes at the root of the
    // temporary folder rather than under a nested one.
    socketPath = p.join(root.path, 'agent.sock');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('no agent means no identities, and no failure', () async {
    expect(await SshAgentClient(socketPath: '').identities(), isEmpty);
    expect(SshAgentClient(socketPath: '').isAvailable, isFalse);
  });

  test('a socket that is not there is not a failure either', () async {
    final client = SshAgentClient(socketPath: p.join(root.path, 'missing'));

    expect(client.isAvailable, isTrue);
    expect(await client.identities(), isEmpty);
  });

  test('reads the identities the agent holds', () async {
    final server = await FakeAgentServer.start(socketPath)
      ..identities = [
        (blob: ed25519Blob(), comment: 'me@laptop'),
        (blob: rsaBlob(), comment: 'deploy@ci'),
      ];
    addTearDown(server.close);

    final identities = await SshAgentClient(socketPath: socketPath)
        .identities();

    expect(identities, hasLength(2));
    expect(identities.first.type, 'ssh-ed25519');
    expect(identities.first.comment, 'me@laptop');
    // An RSA key must sign with SHA-2; ssh-rsa means SHA-1, which OpenSSH
    // 8.8 and newer refuse.
    expect(identities.last.type, 'rsa-sha2-256');
    expect(server.requests, [11]);
  });

  test('an identity from the agent is probed before it signs', () async {
    final server = await FakeAgentServer.start(socketPath)
      ..identities = [(blob: ed25519Blob(), comment: 'me@laptop')];
    addTearDown(server.close);

    final identities = await SshAgentClient(socketPath: socketPath)
        .identities();

    // Otherwise a hardware token would prompt for a key the server would
    // have rejected anyway.
    expect(identities.single.shouldProbe, isTrue);
  });

  test('asks the agent to sign, and hands back what it returns', () async {
    final server = await FakeAgentServer.start(socketPath)
      ..identities = [(blob: ed25519Blob(), comment: 'me@laptop')]
      ..signature = List.filled(64, 7);
    addTearDown(server.close);

    final identity = (await SshAgentClient(
      socketPath: socketPath,
    ).identities()).single;
    final signature = await identity.sign(Uint8List.fromList([1, 2, 3]));

    expect(signature.encode(), List.filled(64, 7));
    expect(server.lastSignedBlob, ed25519Blob());
    expect(server.lastSignFlags, 0);
    expect(server.requests, [11, 13]);
  });

  test('an RSA key is asked for a SHA-2 signature', () async {
    final server = await FakeAgentServer.start(socketPath)
      ..identities = [(blob: rsaBlob(), comment: 'deploy@ci')]
      ..signature = List.filled(8, 1);
    addTearDown(server.close);

    final identity = (await SshAgentClient(
      socketPath: socketPath,
    ).identities()).single;
    await identity.sign(Uint8List.fromList([1, 2, 3]));

    expect(server.lastSignFlags, 2); // SSH_AGENT_RSA_SHA2_256
  });

  test('an agent holding nothing gives nothing', () async {
    final server = await FakeAgentServer.start(socketPath);
    addTearDown(server.close);

    expect(await SshAgentClient(socketPath: socketPath).identities(), isEmpty);
  });

  test('SSH_AUTH_SOCK is where it looks by default', () {
    final fromEnvironment = SshAgentClient().resolvedSocketPath;

    expect(fromEnvironment, Platform.environment['SSH_AUTH_SOCK']);
  });
}
