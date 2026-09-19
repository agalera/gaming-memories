import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'controllers/library_controller.dart';
import 'providers/diablo_iv_provider.dart';
import 'services/config_store.dart';
import 'services/library_scanner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final supportDirectory = await getApplicationSupportDirectory();
  final controller = LibraryController(
    configStore: ConfigStore(
      filePath: p.join(supportDirectory.path, 'gaming-memories.json'),
    ),
    scanner: const LibraryScanner(),
    diabloIVProvider: const DiabloIVProvider(),
  );

  runApp(GamingMemoriesApp(controller: controller));
}
