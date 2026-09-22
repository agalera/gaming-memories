import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/battle_net_games.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('gaming-memories-home-');
  });

  tearDown(() => home.delete(recursive: true));

  BattleNetLocator locator({String os = 'macos', String? homePath}) {
    return BattleNetLocator(
      operatingSystem: os,
      userHomeDirectory: homePath ?? home.path,
      allowEnvironmentHome: false,
    );
  }

  BattleNetGame game(String id) => battleNetGameById(id)!;

  test('game ids are unique and stable', () {
    final ids = battleNetGames.map((game) => game.id).toSet();

    expect(ids, hasLength(battleNetGames.length));
    // These are settings keys and grant ids; renaming one orphans both.
    expect(ids, {
      'wow_retail',
      'wow_classic',
      'wow_classic_era',
      'diablo_iv',
      'diablo_iii',
      'starcraft_ii',
      'overwatch_2',
    });
  });

  test('each World of Warcraft flavour has its own album', () {
    expect(game('wow_retail').albumName, 'World of Warcraft');
    expect(game('wow_classic').albumName, 'WoW Classic');
    expect(game('wow_classic_era').albumName, 'WoW Classic Era');
  });

  test('World of Warcraft reads TGA and dates from the file name', () {
    for (final id in ['wow_retail', 'wow_classic', 'wow_classic_era']) {
      expect(game(id).extensions, contains('.tga'));
      expect(game(id).captureDate, BattleNetCaptureDate.fileName);
    }
    expect(game('diablo_iii').captureDate, BattleNetCaptureDate.modified);
    expect(game('diablo_iii').extensions, isNot(contains('.tga')));
  });

  test('resolves the World of Warcraft flavour folders', () {
    expect(locator().defaultPathsFor(game('wow_retail')), [
      '/Applications/World of Warcraft/_retail_/Screenshots',
    ]);
    expect(locator().defaultPathsFor(game('wow_classic_era')), [
      '/Applications/World of Warcraft/_classic_era_/Screenshots',
    ]);
    expect(locator(os: 'windows').defaultPathsFor(game('wow_classic')), [
      p.join(
        r'C:\Program Files (x86)\World of Warcraft',
        '_classic_',
        'Screenshots',
      ),
    ]);
  });

  test(
    'home-based games resolve against the given home, not the environment',
    () {
      expect(locator().defaultPathsFor(game('starcraft_ii')), [
        p.join(home.path, 'Documents', 'StarCraft II', 'Screenshots'),
      ]);
      // Inside the macOS sandbox $HOME is the app container, so a locator with
      // no home must not guess one.
      const sandboxed = BattleNetLocator(
        operatingSystem: 'macos',
        allowEnvironmentHome: false,
      );
      expect(sandboxed.defaultPathsFor(game('starcraft_ii')), isEmpty);
    },
  );

  test('Diablo IV has no macOS client but keeps a Windows path', () {
    expect(locator().defaultPathsFor(game('diablo_iv')), isEmpty);
    expect(
      locator(os: 'windows').defaultPathsFor(game('diablo_iv')),
      hasLength(2),
    );
  });

  test('a platform with no entry resolves to nothing', () {
    expect(locator(os: 'linux').defaultPathsFor(game('wow_retail')), isEmpty);
  });

  group('resolve', () {
    test('reports a default folder that is there', () {
      final screenshots = Directory(
        p.join(home.path, 'Documents', 'Diablo III', 'Screenshots'),
      )..createSync(recursive: true);

      final folder = locator().resolve(game('diablo_iii'));

      expect(folder.path, screenshots.path);
      expect(folder.exists, isTrue);
      expect(folder.isCustom, isFalse);
      expect(folder.isUsable, isTrue);
    });

    test('a missing game keeps its path but is not usable', () {
      final folder = locator().resolve(game('diablo_iii'));

      expect(folder.path, isNotNull);
      expect(folder.exists, isFalse);
      // A game nobody has installed must never ask for a folder grant.
      expect(folder.isUsable, isFalse);
    });

    test('a custom folder wins over the default', () {
      Directory(p.join(home.path, 'Documents', 'Diablo III', 'Screenshots'))
          .createSync(recursive: true);
      final custom = Directory(p.join(home.path, 'elsewhere'))..createSync();

      final folder = locator().resolve(
        game('diablo_iii'),
        customPath: custom.path,
      );

      expect(folder.path, custom.path);
      expect(folder.isCustom, isTrue);
      expect(folder.isUsable, isTrue);
    });

    test('a custom folder is usable even before it exists', () {
      final folder = locator().resolve(
        game('diablo_iii'),
        customPath: p.join(home.path, 'not-yet'),
      );

      expect(folder.exists, isFalse);
      // The user chose it, so the source still asks for access to it and
      // reports the real problem rather than silently skipping the game.
      expect(folder.isUsable, isTrue);
    });

    test('a game with no path on this platform is still listed', () {
      final folder = locator().resolve(game('diablo_iv'));

      expect(folder.path, isNull);
      expect(folder.isUsable, isFalse);
    });

    test('picks the first default folder that exists', () {
      final documents = Directory(
        p.join(home.path, 'Documents', 'Diablo IV', 'Screenshots'),
      )..createSync(recursive: true);

      final folder = locator(os: 'windows').resolve(game('diablo_iv'));

      // Pictures comes first in the table but is not there.
      expect(folder.path, documents.path);
      expect(folder.exists, isTrue);
    });
  });
}
