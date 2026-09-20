import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/providers/minecraft_provider.dart';
import 'package:gaming_memories/services/provider_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory source;
  late Directory output;

  setUp(() async {
    source = await Directory.systemTemp.createTemp(
      'gaming-memories-minecraft-',
    );
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
      minecraft: ProviderSettings(
        enabled: enabled,
        useCustomPath: useCustomPath,
        sourcePath: sourcePath ?? source.path,
      ),
    );
  }

  test('imports root PNG screenshots into the Minecraft album', () async {
    final first = File(p.join(source.path, 'first.png'));
    final second = File(p.join(source.path, 'second.PNG'));
    await first.writeAsString('first screenshot');
    await second.writeAsString('second screenshot');
    await first.setLastModified(DateTime(2026, 9, 1, 10, 11, 12));
    await second.setLastModified(DateTime(2026, 9, 2, 13, 14, 15));
    await File(p.join(source.path, 'not-a-screenshot.jpg'))
        .writeAsString('ignored');
    final nested = Directory(p.join(source.path, 'nested'))..createSync();
    await File(p.join(nested.path, 'nested.png')).writeAsString('ignored');

    final result = await const MinecraftProvider().collect(settings());

    final album = p.join(output.path, 'PC', 'Minecraft');
    expect(result.imported, 2);
    expect(result.skipped, 0);
    expect(File(p.join(album, '2026-09-01_10-11-12.png')).existsSync(), isTrue);
    expect(File(p.join(album, '2026-09-02_13-14-15.png')).existsSync(), isTrue);
  });

  test('imports launcher and Flatpak automatic folders', () async {
    final launcher = Directory(p.join(source.path, 'launcher'))..createSync();
    final flatpak = Directory(p.join(source.path, 'flatpak'))..createSync();
    final launcherShot = File(p.join(launcher.path, 'launcher.png'));
    final flatpakShot = File(p.join(flatpak.path, 'flatpak.png'));
    await launcherShot.writeAsString('launcher screenshot');
    await flatpakShot.writeAsString('flatpak screenshot');
    await launcherShot.setLastModified(DateTime(2026, 9, 3, 4, 5, 6));
    await flatpakShot.setLastModified(DateTime(2026, 9, 4, 7, 8, 9));

    final result = await MinecraftProvider(
      providerPaths: _TestMinecraftPaths([launcher.path, flatpak.path]),
    ).collect(settings(useCustomPath: false, sourcePath: ''));

    final album = p.join(output.path, 'PC', 'Minecraft');
    expect(result.imported, 2);
    expect(File(p.join(album, '2026-09-03_04-05-06.png')).existsSync(), isTrue);
    expect(File(p.join(album, '2026-09-04_07-08-09.png')).existsSync(), isTrue);
  });

  test('warns when automatic discovery finds no installation', () async {
    final result = await MinecraftProvider(
      providerPaths: _TestMinecraftPaths([
        p.join(source.path, 'missing-launcher'),
        p.join(source.path, 'missing-flatpak'),
      ]),
    ).collect(settings(useCustomPath: false, sourcePath: ''));

    expect(result.imported, 0);
    expect(result.skipped, 0);
    expect(
      result.warning,
      'Minecraft was skipped because no installation was found.',
    );
  });

  test('does not inspect folders while disabled', () async {
    final result = await const MinecraftProvider().collect(
      settings(enabled: false, sourcePath: p.join(source.path, 'missing')),
    );

    expect(result.imported, 0);
    expect(result.skipped, 0);
    expect(result.warning, isNull);
  });
}

class _TestMinecraftPaths extends ProviderPathResolver {
  const _TestMinecraftPaths(this.paths);

  final List<String> paths;

  @override
  List<String> minecraftScreenshots() => paths;
}
