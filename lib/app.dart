import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'controllers/library_controller.dart';
import 'screens/library_shell.dart';

class GamingMemoriesApp extends StatelessWidget {
  const GamingMemoriesApp({required this.controller, super.key});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = FTheme.neutral.dark.desktop;

    return MaterialApp(
      title: 'Gaming Memories',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      theme: theme.toApproximateMaterialTheme(),
      builder: (context, child) => FTheme(
        data: theme,
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
      home: LibraryShell(controller: controller),
    );
  }
}
