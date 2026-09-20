import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'controllers/library_controller.dart';
import 'providers/diablo_iv_provider.dart';
import 'providers/guild_wars_2_provider.dart';
import 'providers/hytale_provider.dart';
import 'providers/minecraft_provider.dart';
import 'providers/playstation_4_provider.dart';
import 'providers/playstation_5_provider.dart';
import 'providers/steam_provider.dart';
import 'services/config_store.dart';
import 'services/file_cache.dart';
import 'services/folder_access_service.dart';
import 'services/library_scanner.dart';
import 'services/provider_paths.dart';
import 'services/steam_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final supportDirectory = await getApplicationSupportDirectory();
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
    folderAccess: folderAccess,
    providerPaths: providerPaths,
    providers: [
      const DiabloIVProvider(),
      const GuildWars2Provider(),
      HytaleProvider(providerPaths: providerPaths),
      MinecraftProvider(providerPaths: providerPaths),
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
