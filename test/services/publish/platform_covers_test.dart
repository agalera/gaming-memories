import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/publish/bundled_platform_covers.dart';
import 'package:gaming_memories/services/publish/platform_covers.dart';
import 'package:path/path.dart' as p;

/// Serves the bytes a test names, so the covers can be exercised without the
/// real asset bundle.
class FakeCoverBundle extends CachingAssetBundle {
  FakeCoverBundle(this.assets);

  final Map<String, List<int>> assets;
  final loaded = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final bytes = assets[key];
    if (bytes == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  test('every platform in the map names a cover with its extension', () {
    const covers = BundledPlatformCovers();

    expect(covers.nameFor('PC'), 'cover.png');
    expect(covers.nameFor('PlayStation 5'), 'cover.jpg');
    expect(covers.nameFor('Nintendo Switch 2'), 'cover.webp');
    expect(covers.nameFor('Pico-8'), 'cover.webp');
  });

  test('matches a folder name whatever its case or padding', () {
    const covers = BundledPlatformCovers();

    expect(covers.nameFor('playstation 5'), 'cover.jpg');
    expect(covers.nameFor('  Nintendo Switch  '), 'cover.png');
  });

  test('a platform with no bundled cover has none', () {
    const covers = BundledPlatformCovers();

    expect(covers.nameFor('Dreamcast'), isNull);
    expect(covers.nameFor(''), isNull);
    expect(platformCoverAsset('Dreamcast'), isNull);
  });

  test('reads the bundled bytes for a platform', () async {
    final bundle = FakeCoverBundle({
      'assets/covers/platforms/pc.png': utf8.encode('the pc cover'),
    });

    final bytes = await BundledPlatformCovers(bundle: bundle).bytesFor('PC');

    expect(utf8.decode(bytes!), 'the pc cover');
    expect(bundle.loaded, ['assets/covers/platforms/pc.png']);
  });

  test('a cover that cannot be read does not fail the publish', () async {
    final covers = BundledPlatformCovers(bundle: FakeCoverBundle(const {}));

    expect(await covers.bytesFor('PC'), isNull);
  });

  test('the map and the asset folder agree', () {
    // The folder is declared wholesale in pubspec.yaml, so a name in the map
    // with no file behind it would only fail at publish time, and a file no
    // platform points at would ship for nothing.
    final directory = Directory('assets/covers/platforms');
    final onDisk = directory
        .listSync()
        .whereType<File>()
        .map((file) => p.basename(file.path))
        .where((name) => !name.startsWith('.'))
        .toSet();

    expect(platformCoverAssets.values.toSet(), onDisk);
  });

  test('NoPlatformCovers bundles nothing', () async {
    const covers = NoPlatformCovers();

    expect(covers.nameFor('PC'), isNull);
    expect(await covers.bytesFor('PC'), isNull);
  });
}
