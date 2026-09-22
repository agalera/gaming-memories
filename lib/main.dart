import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'controllers/library_controller.dart';
import 'services/app_log.dart';
import 'services/battle_net_games.dart';
import 'services/config_store.dart';
import 'services/file_cache.dart';
import 'services/folder_access_service.dart';
import 'services/library_scanner.dart';
import 'services/source_paths.dart';
import 'services/steam_client.dart';
import 'services/timeline_cache.dart';
import 'sources/battle_net_source.dart';
import 'sources/guild_wars_2_source.dart';
import 'sources/hytale_source.dart';
import 'sources/minecraft_source.dart';
import 'sources/nintendo_switch_2_source.dart';
import 'sources/playstation_4_source.dart';
import 'sources/playstation_5_source.dart';
import 'sources/steam_source.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final supportDirectory = await getApplicationSupportDirectory();
  final log = FileAppLog(
    filePath: p.join(supportDirectory.path, 'logs', 'gaming-memories.log'),
  );
  diagnosticLog = log;
  log.info(
    'Gaming Memories started on ${Platform.operatingSystem} '
    '${Platform.operatingSystemVersion}.',
    category: 'app',
  );
  // Anything Flutter would otherwise print to a console nobody is watching.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.error(
      details.summary.toString(),
      category: 'flutter',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    log.error(
      'Unhandled error.',
      category: 'app',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  };
  final folderAccess = createFolderAccessService();
  final sourcePaths = SourcePathResolver(
    userHomeDirectory: await platformUserHomeDirectory(),
    allowEnvironmentHome: !Platform.isMacOS,
  );
  final controller = LibraryController(
    configStore: ConfigStore(
      filePath: p.join(supportDirectory.path, 'gaming-memories.json'),
    ),
    scanner: const LibraryScanner(),
    timelineCache: TimelineCache(
      filePath: p.join(supportDirectory.path, 'timeline-cache.json'),
    ),
    folderAccess: folderAccess,
    log: log,
    sourcePaths: sourcePaths,
    sources: [
      BattleNetSource(
        // Inside the macOS sandbox $HOME is the app container, so the real
        // home has to be handed in the same way SourcePathResolver gets it.
        locator: BattleNetLocator(
          userHomeDirectory: sourcePaths.userHomeDirectory,
          allowEnvironmentHome: sourcePaths.allowEnvironmentHome,
        ),
      ),
      const GuildWars2Source(),
      HytaleSource(sourcePaths: sourcePaths),
      MinecraftSource(sourcePaths: sourcePaths),
      const NintendoSwitch2Source(),
      const PlayStation4Source(),
      const PlayStation5Source(),
      SteamSource(
        sourcePaths: sourcePaths,
        api: SteamClient(
          cache: FileCache(Directory(p.join(supportDirectory.path, 'cache'))),
        ),
      ),
    ],
  );

  runApp(GamingMemoriesApp(controller: controller));
}
