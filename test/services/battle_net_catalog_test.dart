import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/battle_net_catalog.dart';
import 'package:path/path.dart' as p;

void main() {
  test('parses installed products from the Battle.net protobuf database', () {
    final bytes = _productDatabase([
      _productInstall(
        uid: 'wow',
        productCode: 'WoW',
        installPath: '/Applications/World of Warcraft',
        installed: true,
        playable: true,
      ),
      _productInstall(
        uid: 'fenris',
        productCode: 'Fen',
        installPath: r'C:\Games\Diablo IV',
        installed: true,
        playable: false,
      ),
    ]);

    final installs = parseBattleNetProductDatabase(bytes);

    expect(installs, hasLength(2));
    expect(installs.first.uid, 'wow');
    expect(installs.first.productCode, 'WoW');
    expect(installs.first.installPath, '/Applications/World of Warcraft');
    expect(installs.first.installed, isTrue);
    expect(installs.first.playable, isTrue);
    expect(installs.last.uid, 'fenris');
    expect(installs.last.installPath, r'C:\Games\Diablo IV');
    expect(installs.last.playable, isFalse);
  });

  test('catalog filters launcher and uninstalled entries', () async {
    final root = await Directory.systemTemp.createTemp('gaming-memories-bnet-');
    addTearDown(() => root.delete(recursive: true));
    await File(p.join(root.path, 'product.db')).writeAsBytes(
      _productDatabase([
        _productInstall(
          uid: 'agent',
          productCode: 'agent',
          installPath: '/agent',
          installed: true,
          playable: true,
        ),
        _productInstall(
          uid: 'wow',
          productCode: 'WoW',
          installPath: '/wow',
          installed: false,
          playable: false,
        ),
        _productInstall(
          uid: 'fenris',
          productCode: 'Fen',
          installPath: '/diablo',
          installed: true,
          playable: true,
        ),
      ]),
    );

    final installs = await const ProductDatabaseBattleNetCatalog()
        .installations(rootPath: root.path);

    expect(installs.map((install) => install.uid), ['fenris']);
  });

  test('rejects a truncated protobuf database', () {
    expect(
      () => parseBattleNetProductDatabase([0x0a, 0x05, 0x01]),
      throwsFormatException,
    );
  });
}

List<int> _productDatabase(List<List<int>> installs) {
  return [for (final install in installs) ..._bytesField(1, install)];
}

List<int> _productInstall({
  required String uid,
  required String productCode,
  required String installPath,
  required bool installed,
  required bool playable,
}) {
  final settings = _stringField(1, installPath);
  final baseState = [
    ..._varintField(1, installed ? 1 : 0),
    ..._varintField(2, playable ? 1 : 0),
    ..._stringField(7, '1.0.0'),
  ];
  final cachedState = _bytesField(1, baseState);
  return [
    ..._stringField(1, uid),
    ..._stringField(2, productCode),
    ..._bytesField(3, settings),
    ..._bytesField(4, cachedState),
  ];
}

List<int> _stringField(int number, String value) =>
    _bytesField(number, value.codeUnits);

List<int> _bytesField(int number, List<int> value) => [
  ..._varint((number << 3) | 2),
  ..._varint(value.length),
  ...value,
];

List<int> _varintField(int number, int value) => [
  ..._varint(number << 3),
  ..._varint(value),
];

List<int> _varint(int value) {
  final bytes = <int>[];
  var remaining = value;
  do {
    var byte = remaining & 0x7f;
    remaining >>= 7;
    if (remaining != 0) {
      byte |= 0x80;
    }
    bytes.add(byte);
  } while (remaining != 0);
  return bytes;
}
