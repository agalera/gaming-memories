import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class BattleNetInstall {
  const BattleNetInstall({
    required this.uid,
    required this.productCode,
    required this.installPath,
    required this.installed,
    required this.playable,
  });

  final String uid;
  final String productCode;
  final String installPath;
  final bool installed;
  final bool playable;
}

abstract interface class BattleNetCatalog {
  Future<List<BattleNetInstall>> installations({String? rootPath});
}

class ProductDatabaseBattleNetCatalog implements BattleNetCatalog {
  const ProductDatabaseBattleNetCatalog({
    this.operatingSystem,
    this.windowsProgramDataDirectory,
  });

  final String? operatingSystem;
  final String? windowsProgramDataDirectory;

  @override
  Future<List<BattleNetInstall>> installations({String? rootPath}) async {
    for (final path in _databaseCandidates(rootPath)) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      return parseBattleNetProductDatabase(await file.readAsBytes())
          .where(
            (install) =>
                install.installed &&
                install.productCode != 'agent' &&
                install.productCode != 'bna',
          )
          .toList(growable: false);
    }
    return const [];
  }

  List<String> _databaseCandidates(String? rootPath) {
    final root = rootPath?.trim();
    if (root != null && root.isNotEmpty) {
      return [
        p.join(root, 'product.db'),
        p.join(root, 'Agent', 'product.db'),
        p.join(root, 'Battle.net', 'Agent', 'product.db'),
        p.join(
          root,
          'drive_c',
          'ProgramData',
          'Battle.net',
          'Agent',
          'product.db',
        ),
      ];
    }

    final platform = operatingSystem ?? Platform.operatingSystem;
    if (platform == 'macos') {
      return const ['/Users/Shared/Battle.net/Agent/product.db'];
    }
    if (platform == 'windows') {
      final programData =
          windowsProgramDataDirectory ??
          Platform.environment['ProgramData'] ??
          r'C:\ProgramData';
      return [p.join(programData, 'Battle.net', 'Agent', 'product.db')];
    }
    return const [];
  }
}

List<BattleNetInstall> parseBattleNetProductDatabase(List<int> bytes) {
  final reader = _ProtoReader(Uint8List.fromList(bytes));
  final installs = <BattleNetInstall>[];
  while (!reader.isAtEnd) {
    final field = reader.readField();
    if (field.number == 1 && field.value is Uint8List) {
      installs.add(_parseProductInstall(field.value as Uint8List));
    }
  }
  return installs;
}

BattleNetInstall _parseProductInstall(Uint8List bytes) {
  final reader = _ProtoReader(bytes);
  var uid = '';
  var productCode = '';
  var installPath = '';
  var installed = false;
  var playable = false;

  while (!reader.isAtEnd) {
    final field = reader.readField();
    switch (field.number) {
      case 1:
        uid = _stringValue(field.value) ?? uid;
      case 2:
        productCode = _stringValue(field.value) ?? productCode;
      case 3:
        if (field.value case final Uint8List settings) {
          installPath = _parseInstallPath(settings) ?? installPath;
        }
      case 4:
        if (field.value case final Uint8List state) {
          final flags = _parseCachedState(state);
          installed = flags.installed;
          playable = flags.playable;
        }
    }
  }

  return BattleNetInstall(
    uid: uid,
    productCode: productCode,
    installPath: installPath,
    installed: installed,
    playable: playable,
  );
}

String? _parseInstallPath(Uint8List bytes) {
  final reader = _ProtoReader(bytes);
  while (!reader.isAtEnd) {
    final field = reader.readField();
    if (field.number == 1) {
      return _stringValue(field.value);
    }
  }
  return null;
}

({bool installed, bool playable}) _parseCachedState(Uint8List bytes) {
  final reader = _ProtoReader(bytes);
  while (!reader.isAtEnd) {
    final field = reader.readField();
    if (field.number == 1 && field.value is Uint8List) {
      return _parseBaseState(field.value as Uint8List);
    }
  }
  return (installed: false, playable: false);
}

({bool installed, bool playable}) _parseBaseState(Uint8List bytes) {
  final reader = _ProtoReader(bytes);
  var installed = false;
  var playable = false;
  while (!reader.isAtEnd) {
    final field = reader.readField();
    if (field.number == 1 && field.value is int) {
      installed = field.value != 0;
    } else if (field.number == 2 && field.value is int) {
      playable = field.value != 0;
    }
  }
  return (installed: installed, playable: playable);
}

String? _stringValue(Object value) {
  return value is Uint8List ? utf8.decode(value) : null;
}

class _ProtoField {
  const _ProtoField(this.number, this.value);

  final int number;
  final Object value;
}

class _ProtoReader {
  _ProtoReader(this.bytes);

  final Uint8List bytes;
  var offset = 0;

  bool get isAtEnd => offset >= bytes.length;

  _ProtoField readField() {
    final tag = _readVarint();
    final number = tag >> 3;
    final wireType = tag & 7;
    if (number == 0) {
      throw const FormatException('Battle.net product database has field 0.');
    }

    final value = switch (wireType) {
      0 => _readVarint(),
      1 => _readFixed(8),
      2 => _readBytes(_readVarint()),
      5 => _readFixed(4),
      _ => throw FormatException(
        'Battle.net product database uses unsupported wire type $wireType.',
      ),
    };
    return _ProtoField(number, value);
  }

  int _readVarint() {
    var value = 0;
    for (var shift = 0; shift < 64; shift += 7) {
      if (isAtEnd) {
        throw const FormatException('Truncated Battle.net product database.');
      }
      final byte = bytes[offset++];
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return value;
      }
    }
    throw const FormatException('Invalid Battle.net product database varint.');
  }

  Uint8List _readBytes(int length) {
    if (length < 0 || offset + length > bytes.length) {
      throw const FormatException('Truncated Battle.net product database.');
    }
    final value = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return value;
  }

  Uint8List _readFixed(int length) => _readBytes(length);
}
