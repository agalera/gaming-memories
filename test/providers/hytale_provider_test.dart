import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/providers/hytale_provider.dart';
import 'package:gaming_memories/services/provider_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory source;
  late Directory output;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('gaming-memories-hytale-');
    output = await Directory.systemTemp.createTemp('gaming-memories-output-');
  });

  tearDown(() async {
    await source.delete(recursive: true);
    await output.delete(recursive: true);
  });

  AppSettings settings({
    bool enabled = true,
    bool downloadCovers = false,
    bool useCustomPath = true,
    String? sourcePath,
  }) {
    return AppSettings(
      outputPath: output.path,
      hytale: ProviderSettings(
        enabled: enabled,
        useCustomPath: useCustomPath,
        sourcePath: sourcePath ?? source.path,
        downloadCovers: downloadCovers,
      ),
    );
  }

  test(
    'imports supported root screenshots and writes the bundled cover',
    () async {
      final png = File(p.join(source.path, 'first.PNG'));
      final jpeg = File(p.join(source.path, 'second.jpeg'));
      await png.writeAsString('png screenshot');
      await jpeg.writeAsString('jpeg screenshot');
      await png.setLastModified(DateTime(2026, 8, 1, 10, 11, 12));
      await jpeg.setLastModified(DateTime(2026, 8, 2, 13, 14, 15));
      await File(p.join(source.path, 'notes.txt')).writeAsString('ignored');
      final nested = Directory(p.join(source.path, 'nested'))..createSync();
      await File(p.join(nested.path, 'nested.png')).writeAsString('ignored');

      final result = await HytaleProvider(coverLoader: () async => [1, 2, 3])
          .collect(settings(downloadCovers: true));

      final album = p.join(output.path, 'PC', 'Hytale');
      expect(result.imported, 2);
      expect(result.skipped, 0);
      expect(
        File(p.join(album, '2026-08-01_10-11-12.png')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(album, '2026-08-02_13-14-15.jpeg')).existsSync(),
        isTrue,
      );
      expect(File(p.join(album, 'cover.png')).readAsBytesSync(), [1, 2, 3]);
    },
  );

  test(
    'uses the selected folder while automatic discovery is enabled',
    () async {
      final screenshot = File(p.join(source.path, 'automatic.jpg'));
      await screenshot.writeAsString('automatic screenshot');
      await screenshot.setLastModified(DateTime(2026, 8, 3, 4, 5, 6));

      final result = await HytaleProvider(
        providerPaths: const ProviderPathResolver(
          userHomeDirectory: '/unused',
          allowEnvironmentHome: false,
        ),
        coverLoader: () async => const [],
      ).collect(settings(useCustomPath: false));

      expect(result.imported, 1);
      expect(
        File(p.join(output.path, 'PC', 'Hytale', '2026-08-03_04-05-06.jpg'))
            .existsSync(),
        isTrue,
      );
    },
  );

  test(
    'warns when the automatically discovered installation is missing',
    () async {
      final missing = p.join(source.path, 'missing');
      final result = await HytaleProvider(coverLoader: () async => const [])
          .collect(settings(useCustomPath: false, sourcePath: missing));

      expect(result.imported, 0);
      expect(result.skipped, 0);
      expect(
        result.warning,
        'Hytale was skipped because no installation was found.',
      );
    },
  );

  test('loads the packaged Hytale cover asset', () async {
    await HytaleProvider().collect(settings(downloadCovers: true));

    final bytes = File(p.join(output.path, 'PC', 'Hytale', 'cover.png'))
        .readAsBytesSync();
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  test('does not scan or load the cover while disabled', () async {
    var loadedCover = false;
    final result = await HytaleProvider(
      coverLoader: () async {
        loadedCover = true;
        return const [];
      },
    ).collect(settings(enabled: false, downloadCovers: true));

    expect(result.imported, 0);
    expect(result.skipped, 0);
    expect(loadedCover, isFalse);
  });
}
