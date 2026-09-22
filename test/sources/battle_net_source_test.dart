import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/battle_net_games.dart';
import 'package:gaming_memories/sources/battle_net_source.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

void main() {
  late Directory home;
  late Directory output;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('gaming-memories-home-');
    output = await Directory.systemTemp.createTemp('gaming-memories-output-');
  });

  tearDown(() async {
    await home.delete(recursive: true);
    await output.delete(recursive: true);
  });

  /// A source whose macOS defaults live inside the temp home, so the tests
  /// never see what is installed on the machine running them.
  BattleNetSource source() => BattleNetSource(locator: _TestLocator(home.path));

  AppSettings settings({
    bool enabled = true,
    Map<String, SourceSettings> games = const {},
  }) {
    return AppSettings(
      outputPath: output.path,
      battleNet: BattleNetSettings(enabled: enabled, games: games),
    );
  }

  Future<void> writeShot(String path, {DateTime? modified}) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('shot');
    if (modified != null) {
      await file.setLastModified(modified);
    }
  }

  String wowFlavor(String flavor) =>
      p.join(home.path, 'World of Warcraft', flavor, 'Screenshots');

  String documents(List<String> segments) =>
      p.joinAll([home.path, 'Documents', ...segments]);

  test(
    'imports every game that is installed, each into its own album',
    () async {
      await writeShot(
        p.join(wowFlavor('_retail_'), 'WoWScrnShot_092026_112233.jpg'),
      );
      await writeShot(
        p.join(wowFlavor('_classic_'), 'WoWScrnShot_092126_122334.png'),
      );
      await writeShot(
        p.join(documents(['Diablo III', 'Screenshots']), 'd3.jpg'),
        modified: DateTime(2026, 9, 23, 14, 25, 36),
      );
      await writeShot(
        p.join(documents(['StarCraft II', 'Screenshots']), 's2.png'),
        modified: DateTime(2026, 9, 24, 15, 26, 37),
      );
      await writeShot(
        p.join(documents(['Overwatch', 'ScreenShots', 'Overwatch']), 'ow.jpg'),
        modified: DateTime(2026, 9, 25, 16, 27, 38),
      );

      final result = await source().collect(settings());

      expect(result.imported, 5);
      for (final relative in [
        ['World of Warcraft', '2026-09-20_11-22-33.jpg'],
        ['WoW Classic', '2026-09-21_12-23-34.png'],
        ['Diablo III', '2026-09-23_14-25-36.jpg'],
        ['StarCraft II', '2026-09-24_15-26-37.png'],
        ['Overwatch 2', '2026-09-25_16-27-38.jpg'],
      ]) {
        expect(
          File(p.joinAll([output.path, 'PC', ...relative])).existsSync(),
          isTrue,
          reason: relative.join('/'),
        );
      }
    },
  );

  test('converts World of Warcraft TGA captures to PNG', () async {
    final tga = image.Image(width: 2, height: 2)..setPixelRgb(0, 0, 255, 0, 0);
    final file = File(
      p.join(wowFlavor('_retail_'), 'WoWScrnShot_010126_020304.tga'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(image.encodeTga(tga));

    final result = await source().collect(settings());

    expect(result.imported, 1);
    expect(
      File(
        p.join(
          output.path,
          'PC',
          'World of Warcraft',
          '2026-01-01_02-03-04.png',
        ),
      ).existsSync(),
      isTrue,
    );
  });

  test('skips a World of Warcraft file with no date in its name', () async {
    await writeShot(p.join(wowFlavor('_retail_'), 'invalid.jpg'));

    final result = await source().collect(settings());

    expect(result.imported, 0);
    expect(result.skipped, 1);
  });

  test('a game switched off is not imported', () async {
    await writeShot(
      p.join(wowFlavor('_retail_'), 'WoWScrnShot_092026_112233.jpg'),
    );
    await writeShot(
      p.join(documents(['Diablo III', 'Screenshots']), 'd3.jpg'),
      modified: DateTime(2026, 9, 23, 14, 25, 36),
    );

    final result = await source().collect(
      settings(
        games: const {
          'diablo_iii': SourceSettings(
            enabled: false,
            useCustomPath: false,
            sourcePath: '',
          ),
        },
      ),
    );

    expect(result.imported, 1);
    expect(
      Directory(p.join(output.path, 'PC', 'Diablo III')).existsSync(),
      isFalse,
    );
  });

  test('a custom folder overrides the default', () async {
    final custom = Directory(p.join(home.path, 'elsewhere'))
      ..createSync(recursive: true);
    await writeShot(
      p.join(custom.path, 'sc2.png'),
      modified: DateTime(2026, 9, 24, 15, 26, 37),
    );

    final result = await source().collect(
      settings(
        games: {
          'starcraft_ii': SourceSettings(
            enabled: true,
            useCustomPath: true,
            sourcePath: custom.path,
          ),
        },
      ),
    );

    expect(result.imported, 1);
    expect(
      File(p.join(output.path, 'PC', 'StarCraft II', '2026-09-24_15-26-37.png'))
          .existsSync(),
      isTrue,
    );
  });

  test('warns when no game was found', () async {
    final result = await source().collect(settings());

    expect(result.imported, 0);
    expect(result.warning, contains('none of its games were found'));
  });

  test('a disabled source does nothing', () async {
    await writeShot(
      p.join(wowFlavor('_retail_'), 'WoWScrnShot_092026_112233.jpg'),
    );

    final result = await source().collect(settings(enabled: false));

    expect(result.imported, 0);
    expect(result.warning, isNull);
  });

  group('folder requirements', () {
    test('only installed games ask for access', () async {
      Directory(wowFlavor('_retail_')).createSync(recursive: true);

      final requirements = source().folderRequirements(settings());

      expect(requirements, hasLength(1));
      expect(requirements.single.path, wowFlavor('_retail_'));
      expect(
        requirements.single.id,
        BattleNetSource.grantIdForGame('wow_retail'),
      );
      expect(requirements.single.automatic, isTrue);
      expect(requirements.single.description, contains('World of Warcraft'));
    });

    test('every game has its own grant id', () async {
      for (final flavor in ['_retail_', '_classic_', '_classic_era_']) {
        Directory(wowFlavor(flavor)).createSync(recursive: true);
      }

      final requirements = source().folderRequirements(settings());

      expect(requirements, hasLength(3));
      expect(
        requirements.map((requirement) => requirement.id).toSet(),
        hasLength(3),
      );
    });

    test('a custom folder is not automatic', () async {
      final custom = Directory(p.join(home.path, 'custom'))
        ..createSync(recursive: true);

      final requirements = source().folderRequirements(
        settings(
          games: {
            'diablo_iii': SourceSettings(
              enabled: true,
              useCustomPath: true,
              sourcePath: custom.path,
            ),
          },
        ),
      );

      expect(requirements, hasLength(1));
      expect(requirements.single.automatic, isFalse);
      expect(requirements.single.path, custom.path);
    });

    test('a switched-off source requires nothing', () async {
      Directory(wowFlavor('_retail_')).createSync(recursive: true);

      expect(source().folderRequirements(settings(enabled: false)), isEmpty);
    });

    test('the source stores no folder of its own', () {
      final next = source().withFolderPath(settings(), '/somewhere');

      expect(next.battleNet.games, settings().battleNet.games);
    });
  });

  test('lists every game for the settings rows, installed or not', () {
    Directory(wowFlavor('_retail_')).createSync(recursive: true);

    final folders = source().gameFolders(settings());

    expect(folders, hasLength(battleNetGames.length));
    expect(
      folders.firstWhere((folder) => folder.game.id == 'wow_retail').exists,
      isTrue,
    );
    expect(
      folders.firstWhere((folder) => folder.game.id == 'wow_classic').exists,
      isFalse,
    );
    // Diablo IV has no macOS client, so it has no path to show.
    expect(
      folders.firstWhere((folder) => folder.game.id == 'diablo_iv').path,
      isNull,
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

/// Points the macOS install defaults at a temp directory.
class _TestLocator extends BattleNetLocator {
  const _TestLocator(this.root)
    : super(
        operatingSystem: 'macos',
        userHomeDirectory: root,
        allowEnvironmentHome: false,
      );

  final String root;

  @override
  List<String> defaultPathsFor(BattleNetGame game) {
    return [
      for (final path in super.defaultPathsFor(game))
        path.startsWith('/Applications/')
            ? p.join(root, path.substring('/Applications/'.length))
            : path,
    ];
  }
}
