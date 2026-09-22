import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Talks to the SSH agent this session already has, so an automatic publish
/// can use a key the user has unlocked once rather than asking for its
/// passphrase again.
///
/// dartssh2 can forward an agent to a remote host but cannot authenticate
/// against a local one, so the small part of the agent protocol that needs —
/// list the identities, ask one of them to sign — is spoken here.
class SshAgentClient {
  SshAgentClient({this.socketPath});

  /// The agent's socket. Left null, `SSH_AUTH_SOCK` says where it is, which
  /// is how every other SSH program finds it.
  final String? socketPath;

  static const _requestIdentities = 11;
  static const _identitiesAnswer = 12;
  static const _signRequest = 13;
  static const _signResponse = 14;

  /// Signature flags, for keys whose default algorithm a modern server no
  /// longer accepts. An RSA key has to be asked for a SHA-2 signature;
  /// `ssh-rsa` means SHA-1, which OpenSSH 8.8 and newer refuse.
  static const _rsaSha2_256 = 2;

  /// A frame longer than this is not something an agent sends, so it is a
  /// protocol error rather than something to allocate for.
  static const _maxFrame = 256 * 1024;

  String? get resolvedSocketPath =>
      socketPath ?? Platform.environment['SSH_AUTH_SOCK'];

  /// Whether there is an agent to talk to at all.
  bool get isAvailable => (resolvedSocketPath ?? '').isNotEmpty;

  /// The identities the agent holds, ready to sign. Empty when no agent is
  /// running, it holds nothing, or it cannot be reached — none of which is a
  /// failure, because the caller has other ways to authenticate.
  Future<List<SSHIdentity>> identities() async {
    final path = resolvedSocketPath;
    if (path == null || path.isEmpty) {
      return const [];
    }

    final Socket socket;
    try {
      socket = await _connect(path);
    } on SocketException {
      return const [];
    } on FileSystemException {
      return const [];
    }

    try {
      final reply = await _exchange(
        socket,
        Uint8List.fromList([_requestIdentities]),
      );
      return _readIdentities(reply, path);
    } on SshAgentException {
      return const [];
    } on SocketException {
      return const [];
    } finally {
      socket.destroy();
    }
  }

  List<SSHIdentity> _readIdentities(Uint8List reply, String path) {
    final reader = _Reader(reply);
    if (reader.readByte() != _identitiesAnswer) {
      return const [];
    }

    final count = reader.readUint32();
    final identities = <SSHIdentity>[];
    for (var index = 0; index < count; index++) {
      final blob = reader.readString();
      final comment = reader.readString();
      final keyType = SSHHostKey.getType(blob);
      identities.add(
        SSHIdentity.custom(
          // An RSA key signs with SHA-2 or a current server rejects it.
          type: keyType == 'ssh-rsa' ? 'rsa-sha2-256' : keyType,
          publicKey: SSHRawHostKey(blob),
          comment: String.fromCharCodes(comment),
          // The agent may prompt or touch a token to sign, so the server is
          // asked whether it would accept this key before that happens.
          shouldProbe: true,
          signer: (data) => _sign(path, blob, data, keyType),
        ),
      );
    }
    return identities;
  }

  Future<SSHSignature> _sign(
    String path,
    Uint8List blob,
    Uint8List data,
    String keyType,
  ) async {
    final socket = await _connect(path);
    try {
      final request = _Writer()
        ..writeByte(_signRequest)
        ..writeString(blob)
        ..writeString(data)
        ..writeUint32(keyType == 'ssh-rsa' ? _rsaSha2_256 : 0);

      final reply = await _exchange(socket, request.take());
      final reader = _Reader(reply);
      if (reader.readByte() != _signResponse) {
        throw const SshAgentException('The agent refused to sign.');
      }
      return SSHRawSignature(reader.readString());
    } finally {
      socket.destroy();
    }
  }

  Future<Socket> _connect(String path) =>
      Socket.connect(InternetAddress(path, type: InternetAddressType.unix), 0);

  /// Sends one length-prefixed request and reads the one reply it gets back.
  Future<Uint8List> _exchange(Socket socket, Uint8List payload) async {
    final framed = _Writer()
      ..writeUint32(payload.length)
      ..writeBytes(payload);
    socket.add(framed.take());
    await socket.flush();

    final buffer = BytesBuilder(copy: false);
    await for (final chunk in socket) {
      buffer.add(chunk);
      if (buffer.length < 4) {
        continue;
      }
      final bytes = buffer.toBytes();
      final length = _Reader(bytes).readUint32();
      if (length > _maxFrame) {
        throw const SshAgentException('The agent sent an oversized reply.');
      }
      if (bytes.length >= 4 + length) {
        return Uint8List.sublistView(bytes, 4, 4 + length);
      }
      buffer
        ..clear()
        ..add(bytes);
    }

    throw const SshAgentException('The agent closed without replying.');
  }
}

class SshAgentException implements Exception {
  const SshAgentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  var _offset = 0;

  int readByte() {
    _require(1);
    return bytes[_offset++];
  }

  int readUint32() {
    _require(4);
    final value = ByteData.sublistView(bytes).getUint32(_offset);
    _offset += 4;
    return value;
  }

  Uint8List readString() {
    final length = readUint32();
    _require(length);
    final value = Uint8List.sublistView(bytes, _offset, _offset + length);
    _offset += length;
    return value;
  }

  void _require(int count) {
    if (_offset + count > bytes.length) {
      throw const SshAgentException('The agent sent a truncated reply.');
    }
  }
}

class _Writer {
  final _builder = BytesBuilder(copy: false);

  void writeByte(int value) => _builder.addByte(value);

  void writeUint32(int value) {
    final field = ByteData(4)..setUint32(0, value);
    _builder.add(field.buffer.asUint8List());
  }

  void writeBytes(List<int> value) => _builder.add(value);

  void writeString(List<int> value) {
    writeUint32(value.length);
    _builder.add(value);
  }

  Uint8List take() => _builder.takeBytes();
}
