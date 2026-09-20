import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/providers/battle_net_provider.dart';
import 'package:gaming_memories/services/battle_net_catalog.dart';
import 'package:gaming_memories/services/provider_paths.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

void main() {
  late Directory source;
  late Directory output;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('gaming-memories-bnet-');
    output = await Directory.systemTemp.createTemp('gaming-memories-output-');
  });

  tearDown(() async {
    await source.delete(recursive: true);
    await output.delete(recursive: true);
  });

  AppSettings settings({
    bool enabled = true,
    bool useCustomPath = true,
    String? sourcePath,
  }) {
    return AppSettings(
      outputPath: output.path,
      battleNet: ProviderSettings(
        enabled: enabled,
        useCustomPath: useCustomPath,
        sourcePath: sourcePath ?? source.path,
      ),
    );
  }

  test('fans Diablo IV and World of Warcraft into their own albums', () async {
    final wow = Directory(
      p.join(source.path, 'World of Warcraft', '_retail_', 'Screenshots'),
    )..createSync(recursive: true);
    final diablo = Directory(p.join(source.path, 'Pictures', 'Diablo IV'))
      ..createSync(recursive: true);
    await File(p.join(wow.path, 'WoWScrnShot_092026_112233.jpg'))
        .writeAsString('wow jpg');
    final tga = image.Image(width: 2, height: 2)..setPixelRgb(0, 0, 255, 0, 0);
    await File(p.join(wow.path, 'WoWScrnShot_092126_122334.tga'))
        .writeAsBytes(image.encodeTga(tga));
    await File(p.join(wow.path, 'invalid.jpg')).writeAsString('invalid');
    final diabloShot = File(p.join(diablo.path, 'diablo.png'));
    await diabloShot.writeAsString('diablo');
    await diabloShot.setLastModified(DateTime(2026, 9, 22, 13, 24, 35));

    final result = await const BattleNetProvider().collect(settings());

    expect(result.imported, 3);
    expect(result.skipped, 1);
    expect(
      File(
        p.join(
          output.path,
          'PC',
          'World of Warcraft',
          '2026-09-20_11-22-33.jpg',
        ),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(
          output.path,
          'PC',
          'World of Warcraft',
          '2026-09-21_12-23-34.png',
        ),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(output.path, 'PC', 'Diablo IV', '2026-09-22_13-24-35.png'))
          .existsSync(),
      isTrue,
    );
  });

  test(
    'discovers installed games from the catalog in automatic mode',
    () async {
      final wowInstall = Directory(p.join(source.path, 'World of Warcraft'));
      final wow = Directory(p.join(wowInstall.path, '_retail_', 'Screenshots'))
        ..createSync(recursive: true);
      final diablo = Directory(p.join(source.path, 'Diablo screenshots'))
        ..createSync();
      await File(p.join(wow.path, 'WoWScrnShot_092026_112233.png'))
          .writeAsString('wow');
      final diabloShot = File(p.join(diablo.path, 'diablo.jpg'));
      await diabloShot.writeAsString('diablo');
      await diabloShot.setLastModified(DateTime(2026, 9, 23, 1, 2, 3));

      final result = await BattleNetProvider(
        catalog: _FakeCatalog([
          BattleNetInstall(
            uid: 'wow',
            productCode: 'WoW',
            installPath: wowInstall.path,
            installed: true,
            playable: true,
          ),
          const BattleNetInstall(
            uid: 'fenris',
            productCode: 'Fen',
            installPath: '/unused',
            installed: true,
            playable: true,
          ),
        ]),
        providerPaths: _TestBattleNetPaths(diablo.path),
      ).collect(settings(useCustomPath: false, sourcePath: ''));

      expect(result.imported, 2);
      expect(
        File(
          p.join(
            output.path,
            'PC',
            'World of Warcraft',
            '2026-09-20_11-22-33.png',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(output.path, 'PC', 'Diablo IV', '2026-09-23_01-02-03.jpg'))
            .existsSync(),
        isTrue,
      );
    },
  );

  test('warns when automatic discovery finds no supported games', () async {
    final result = await const BattleNetProvider(
      catalog: _FakeCatalog([]),
      providerPaths: _TestBattleNetPaths(null),
    ).collect(settings(useCustomPath: false, sourcePath: ''));

    expect(result.imported, 0);
    expect(
      result.warning,
      'Battle.net was skipped because no Diablo IV or World of Warcraft screenshot folders were found.',
    );
  });

  test('parses World of Warcraft dates with the Go two-digit year pivot', () {
    expect(
      parseWorldOfWarcraftScreenshotDate('WoWScrnShot_123168_235959.jpeg'),
      DateTime(2068, 12, 31, 23, 59, 59),
    );
    expect(
      parseWorldOfWarcraftScreenshotDate('WoWScrnShot_010169_000000.png'),
      DateTime(1969),
    );
    expect(
      parseWorldOfWarcraftScreenshotDate('WoWScrnShot_023126_000000.jpg'),
      isNull,
    );
    expect(parseWorldOfWarcraftScreenshotDate('invalid.jpg'), isNull);
  });
}

class _FakeCatalog implements BattleNetCatalog {
  const _FakeCatalog(this.installs);

  final List<BattleNetInstall> installs;

  @override
  Future<List<BattleNetInstall>> installations({String? rootPath}) async =>
      installs;
}

class _TestBattleNetPaths extends ProviderPathResolver {
  const _TestBattleNetPaths(this.diabloPath);

  final String? diabloPath;

  @override
  List<String> battleNetRootCandidates() => const [];

  @override
  List<String> diabloIVScreenshots() => [?diabloPath];
}
