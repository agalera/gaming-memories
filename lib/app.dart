import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'controllers/library_controller.dart';
import 'models/app_settings.dart';
import 'screens/library_shell.dart';

class GamingMemoriesApp extends StatelessWidget {
  const GamingMemoriesApp({required this.controller, super.key});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final light = FTheme.neutral.light.desktop;
        final dark = FTheme.neutral.dark.desktop;
        final mode = switch (controller.settings.themeMode) {
          AppThemeMode.system => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        };

        return MaterialApp(
          title: 'Gaming Memories',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: FLocalizations.localizationsDelegates,
          supportedLocales: FLocalizations.supportedLocales,
          theme: light.toApproximateMaterialTheme(),
          darkTheme: dark.toApproximateMaterialTheme(),
          themeMode: mode,
          builder: (context, child) {
            final theme = Theme.of(context).brightness == Brightness.dark
                ? dark
                : light;
            return FTheme(
              data: theme,
              child: FToaster(child: FTooltipGroup(child: child!)),
            );
          },
          home: LibraryShell(controller: controller),
        );
      },
    );
  }
}
