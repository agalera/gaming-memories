import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/provider_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Steam discovery can use the real home outside a macOS sandbox', () {
    const resolver = ProviderPathResolver(userHomeDirectory: '/Users/alice');

    expect(resolver.steamUserdataCandidates(), [
      p.join(
        '/Users/alice',
        'Library',
        'Application Support',
        'Steam',
        'userdata',
      ),
    ]);
  }, skip: !Platform.isMacOS);

  test('macOS discovery does not fall back to a sandbox container home', () {
    const resolver = ProviderPathResolver(allowEnvironmentHome: false);

    expect(resolver.steamUserdataCandidates(), isEmpty);
    expect(resolver.hytaleScreenshots(), isNull);
    expect(resolver.minecraftScreenshots(), isEmpty);
  }, skip: !Platform.isMacOS);

  test('Hytale discovery uses the real macOS account home', () {
    const resolver = ProviderPathResolver(userHomeDirectory: '/Users/alice');

    expect(
      resolver.hytaleScreenshots(),
      p.join('/Users/alice', 'Pictures', 'Hytale Screenshots'),
    );
  }, skip: !Platform.isMacOS);

  test('Minecraft discovery includes launcher and Flatpak Linux folders', () {
    expect(
      ProviderPaths.minecraftScreenshots(
        operatingSystem: 'linux',
        userHomeDirectory: '/home/alice',
      ),
      [
        p.join('/home/alice', '.minecraft', 'screenshots'),
        p.join(
          '/home/alice',
          '.var',
          'app',
          'com.mojang.Minecraft',
          '.minecraft',
          'screenshots',
        ),
        p.join(
          '/home/alice',
          '.var',
          'app',
          'com.mojang.Minecraft',
          'data',
          'minecraft',
          'screenshots',
        ),
      ],
    );
  });

  test('Minecraft discovery uses the real macOS account home', () {
    expect(
      ProviderPaths.minecraftScreenshots(
        operatingSystem: 'macos',
        userHomeDirectory: '/Users/alice',
      ),
      [
        p.join(
          '/Users/alice',
          'Library',
          'Application Support',
          'minecraft',
          'screenshots',
        ),
      ],
    );
  });

  test('Minecraft discovery uses the Windows roaming data folder', () {
    const appData = r'C:\Users\alice\AppData\Roaming';

    expect(
      ProviderPaths.minecraftScreenshots(
        operatingSystem: 'windows',
        windowsAppDataDirectory: appData,
      ),
      [p.join(appData, '.minecraft', 'screenshots')],
    );
  });
}
