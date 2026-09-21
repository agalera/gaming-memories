import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'controllers/library_controller.dart';
import 'providers/battle_net_provider.dart';
import 'providers/guild_wars_2_provider.dart';
import 'providers/hytale_provider.dart';
import 'providers/minecraft_provider.dart';
import 'providers/nintendo_switch_2_provider.dart';
import 'providers/playstation_4_provider.dart';
import 'providers/playstation_5_provider.dart';
import 'providers/steam_provider.dart';
import 'services/app_log.dart';
import 'services/battle_net_games.dart';
import 'services/config_store.dart';
import 'services/file_cache.dart';
import 'services/folder_access_service.dart';
import 'services/library_scanner.dart';
import 'services/provider_paths.dart';
import 'services/steam_client.dart';
import 'services/timeline_cache.dart';

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
  final providerPaths = ProviderPathResolver(
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
    providerPaths: providerPaths,
    providers: [
      BattleNetProvider(
        // Inside the macOS sandbox $HOME is the app container, so the real
        // home has to be handed in the same way ProviderPathResolver gets it.
        locator: BattleNetLocator(
          userHomeDirectory: providerPaths.userHomeDirectory,
          allowEnvironmentHome: providerPaths.allowEnvironmentHome,
        ),
      ),
      const GuildWars2Provider(),
      HytaleProvider(providerPaths: providerPaths),
      MinecraftProvider(providerPaths: providerPaths),
      const NintendoSwitch2Provider(),
      const PlayStation4Provider(),
      const PlayStation5Provider(),
      SteamProvider(
        providerPaths: providerPaths,
        api: SteamClient(
          cache: FileCache(Directory(p.join(supportDirectory.path, 'cache'))),
        ),
      ),
    ],
  );

  runApp(GamingMemoriesApp(controller: controller));
}
