import 'package:file_picker/file_picker.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../models/app_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.controller, super.key});

  final LibraryController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _outputController;
  late final TextEditingController _diabloController;
  late final TextEditingController _steamPathController;
  late final TextEditingController _steamUserController;
  late final TextEditingController _steamKeyController;
  late final TextEditingController _steamIgnoredInputController;
  late final TextEditingController _steamCustomIdController;
  late final TextEditingController _steamCustomNameController;
  late final List<String> _steamIgnoredGames;
  late final List<_CustomGame> _steamCustomGames;
  late AppThemeMode _themeMode;
  late bool _diabloEnabled;
  late bool _steamEnabled;
  late bool _steamOnlineGallery;
  late bool _steamDownloadCovers;

  @override
  void initState() {
    super.initState();
    _outputController = TextEditingController(
      text: widget.controller.settings.outputPath,
    );
    _diabloController = TextEditingController(
      text: widget.controller.settings.diabloIV.sourcePath,
    );
    final steam = widget.controller.settings.steam;
    _steamPathController = TextEditingController(text: steam.userdataPath);
    _steamUserController = TextEditingController(text: steam.userId);
    _steamKeyController = TextEditingController(text: steam.apiKey);
    _steamIgnoredInputController = TextEditingController();
    _steamIgnoredGames = steam.ignoredGames.toList();
    _steamCustomIdController = TextEditingController();
    _steamCustomNameController = TextEditingController();
    _steamCustomGames = steam.customGames.entries
        .map((entry) => _CustomGame(entry.key, entry.value))
        .toList();
    _diabloEnabled = widget.controller.settings.diabloIV.enabled;
    _steamEnabled = steam.enabled;
    _steamOnlineGallery = steam.onlineGallery;
    _steamDownloadCovers = steam.downloadCovers;
    _themeMode = widget.controller.settings.themeMode;
  }

  @override
  void dispose() {
    _outputController.dispose();
    _diabloController.dispose();
    _steamPathController.dispose();
    _steamUserController.dispose();
    _steamKeyController.dispose();
    _steamIgnoredInputController.dispose();
    _steamCustomIdController.dispose();
    _steamCustomNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Library and provider setup',
                style: context.theme.typography.body.sm.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
              const SizedBox(height: 22),
              _sectionTitle(context, 'Appearance'),
              const SizedBox(height: 10),
              FCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Color mode',
                        style: context.theme.typography.body.lg.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Use the system mode or choose a fixed app mode.',
                        style: context.theme.typography.body.sm.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ThemeModeSelector(
                        value: _themeMode,
                        onChange: (value) {
                          setState(() => _themeMode = value);
                          widget.controller.previewTheme(value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _sectionTitle(context, 'Library'),
              const SizedBox(height: 10),
              FCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Media library',
                        style: context.theme.typography.body.lg.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Gaming Memories stores albums below this folder.',
                        style: context.theme.typography.body.sm.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _DirectoryField(
                        controller: _outputController,
                        label: 'Library folder',
                        hint: '/path/to/media',
                        onBrowse: () => _chooseDirectory(
                          controller: _outputController,
                          title: 'Choose the media library',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _sectionTitle(context, 'Providers'),
              const SizedBox(height: 10),
              FCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: context.theme.colors.muted,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(FLucideIcons.gamepad2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Diablo IV',
                                  style: context.theme.typography.body.lg
                                      .copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'PC · Screenshots',
                                  style: context.theme.typography.body.sm
                                      .copyWith(
                                        color: context
                                            .theme
                                            .colors
                                            .mutedForeground,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          FSwitch(
                            value: _diabloEnabled,
                            semanticsLabel: 'Enable Diablo IV',
                            onChange: (value) {
                              setState(() => _diabloEnabled = value);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _DirectoryField(
                        controller: _diabloController,
                        label: 'Screenshot folder',
                        hint: 'auto or /path/to/Diablo IV',
                        enabled: _diabloEnabled,
                        onBrowse: () => _chooseDirectory(
                          controller: _diabloController,
                          title: 'Choose the Diablo IV screenshot folder',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'On Windows, leave this field empty to scan both default folders.',
                        style: context.theme.typography.body.xs.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: context.theme.colors.muted,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(FLucideIcons.gamepad2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Steam',
                                  style: context.theme.typography.body.lg
                                      .copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'PC · Local and online screenshots',
                                  style: context.theme.typography.body.sm
                                      .copyWith(
                                        color: context
                                            .theme
                                            .colors
                                            .mutedForeground,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          FSwitch(
                            value: _steamEnabled,
                            semanticsLabel: 'Enable Steam',
                            onChange: (value) {
                              setState(() => _steamEnabled = value);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _DirectoryField(
                        controller: _steamPathController,
                        label: 'Steam folder',
                        hint: 'auto or /path/to/Steam',
                        enabled: _steamEnabled,
                        onBrowse: () => _chooseDirectory(
                          controller: _steamPathController,
                          title: 'Choose the Steam folder',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SwitchSetting(
                        label: 'Download game covers',
                        description: 'Save a cover.jpg file in each album.',
                        value: _steamDownloadCovers,
                        enabled: _steamEnabled,
                        onChange: (value) {
                          setState(() => _steamDownloadCovers = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      _SwitchSetting(
                        label: 'Import online gallery',
                        description: 'Import public screenshots from Steam.',
                        value: _steamOnlineGallery,
                        enabled: _steamEnabled,
                        onChange: (value) {
                          setState(() => _steamOnlineGallery = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            'Steam online credentials',
                            style: context.theme.typography.body.sm.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          FButton.icon(
                            key: const ValueKey('steam-credentials-help'),
                            variant: FButtonVariant.ghost,
                            size: FButtonSizeVariant.xs,
                            semanticsLabel: 'Help with Steam credentials',
                            onPress: _showSteamCredentialHelp,
                            child: const Icon(FLucideIcons.circleHelp),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FTextField(
                              control: FTextFieldControl.managed(
                                controller: _steamUserController,
                              ),
                              label: const Text('Steam user ID'),
                              hint: '7656119…',
                              enabled: _steamEnabled,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FTextField.password(
                              control: FTextFieldControl.managed(
                                controller: _steamKeyController,
                              ),
                              label: const Text('Steam Web API key'),
                              hint: 'Required for game names',
                              enabled: _steamEnabled,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: FTextField(
                              key: const ValueKey('steam-ignored-input'),
                              control: FTextFieldControl.managed(
                                controller: _steamIgnoredInputController,
                              ),
                              label: const Text('Ignored app ID'),
                              hint: '1234',
                              enabled: _steamEnabled,
                              onSubmit: (_) => _addIgnoredGame(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FButton(
                            key: const ValueKey('steam-ignored-add'),
                            variant: FButtonVariant.outline,
                            mainAxisSize: MainAxisSize.min,
                            onPress: _steamEnabled ? _addIgnoredGame : null,
                            prefix: const Icon(FLucideIcons.plus),
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Add one Steam app ID at a time.',
                        style: context.theme.typography.body.xs.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _IgnoredGamesList(
                        games: _steamIgnoredGames,
                        enabled: _steamEnabled,
                        onRemove: _removeIgnoredGame,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: FTextField(
                              key: const ValueKey('steam-custom-id-input'),
                              control: FTextFieldControl.managed(
                                controller: _steamCustomIdController,
                              ),
                              label: const Text('Custom app ID'),
                              hint: '1234',
                              enabled: _steamEnabled,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FTextField(
                              key: const ValueKey('steam-custom-name-input'),
                              control: FTextFieldControl.managed(
                                controller: _steamCustomNameController,
                              ),
                              label: const Text('Custom game name'),
                              hint: 'My Game',
                              enabled: _steamEnabled,
                              onSubmit: (_) => _addCustomGame(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FButton(
                            key: const ValueKey('steam-custom-add'),
                            variant: FButtonVariant.outline,
                            mainAxisSize: MainAxisSize.min,
                            onPress: _steamEnabled ? _addCustomGame : null,
                            prefix: const Icon(FLucideIcons.plus),
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'A custom name replaces the Steam store name.',
                        style: context.theme.typography.body.xs.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CustomGamesList(
                        games: _steamCustomGames,
                        enabled: _steamEnabled,
                        onRemove: _removeCustomGame,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Spacer(),
                  FButton(
                    onPress: widget.controller.isBusy ? null : _save,
                    mainAxisSize: MainAxisSize.min,
                    prefix: const Icon(FLucideIcons.save),
                    child: const Text('Save settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text.toUpperCase(),
      style: context.theme.typography.body.xs.copyWith(
        color: context.theme.colors.mutedForeground,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Future<void> _chooseDirectory({
    required TextEditingController controller,
    required String title,
  }) async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: title,
      initialDirectory: controller.text.trim().isEmpty
          ? null
          : controller.text.trim(),
    );

    if (selected != null && mounted) {
      setState(() => controller.text = selected);
    }
  }

  void _showSteamCredentialHelp() {
    showFDialog<void>(
      context: context,
      builder: (dialogContext, _, animation) => FDialog(
        animation: animation,
        semanticsLabel: 'Steam credential help',
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Steam credentials',
                  style: context.theme.typography.display.sm,
                ),
                const SizedBox(height: 8),
                Text(
                  'Steam uses these values for online screenshots and game information.',
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 20),
                const _CredentialHelpSection(
                  title: 'Steam user ID',
                  body: 'This 17-digit SteamID64 identifies the owner of the online gallery. It is required only for online gallery imports.',
                  steps: 'Open Steam. Select your account name, then select Account details. Copy the Steam ID below your account name.',
                ),
                const SizedBox(height: 18),
                const _CredentialHelpSection(
                  title: 'Steam Web API key',
                  body: 'The API key authorizes requests for game names and published screenshots. Do not share this key.',
                  steps: 'Sign in at the address below. Register a key and accept the Steam Web API terms.',
                  address: 'https://steamcommunity.com/dev/apikey',
                ),
                const SizedBox(height: 12),
                Text(
                  'Gaming Memories stores the key in its local settings file.',
                  style: context.theme.typography.body.xs.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerRight,
                  child: FButton(
                    key: const ValueKey('steam-credentials-help-close'),
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final next = AppSettings(
      outputPath: _outputController.text.trim(),
      themeMode: _themeMode,
      diabloIV: ProviderSettings(
        enabled: _diabloEnabled,
        sourcePath: _diabloController.text.trim(),
      ),
      steam: SteamSettings(
        enabled: _steamEnabled,
        userdataPath: _steamPathController.text.trim(),
        onlineGallery: _steamOnlineGallery,
        userId: _steamUserController.text.trim(),
        apiKey: _steamKeyController.text.trim(),
        downloadCovers: _steamDownloadCovers,
        ignoredGames: List.unmodifiable(_steamIgnoredGames),
        customGames: Map.unmodifiable({
          for (final game in _steamCustomGames) game.appId: game.name,
        }),
      ),
    );
    await widget.controller.saveSettings(next);
  }

  void _addIgnoredGame() {
    final appId = _steamIgnoredInputController.text.trim();
    if (appId.isEmpty || _steamIgnoredGames.contains(appId)) {
      return;
    }

    setState(() {
      _steamIgnoredGames.add(appId);
      _steamIgnoredInputController.clear();
    });
  }

  void _removeIgnoredGame(String appId) {
    setState(() => _steamIgnoredGames.remove(appId));
  }

  void _addCustomGame() {
    final appId = _steamCustomIdController.text.trim();
    final name = _steamCustomNameController.text.trim();
    if (appId.isEmpty || name.isEmpty) {
      return;
    }

    setState(() {
      final index = _steamCustomGames.indexWhere((game) => game.appId == appId);
      final game = _CustomGame(appId, name);
      if (index < 0) {
        _steamCustomGames.add(game);
      } else {
        _steamCustomGames[index] = game;
      }
      _steamCustomIdController.clear();
      _steamCustomNameController.clear();
    });
  }

  void _removeCustomGame(String appId) {
    setState(
      () => _steamCustomGames.removeWhere((game) => game.appId == appId),
    );
  }
}

class _CustomGame {
  const _CustomGame(this.appId, this.name);

  final String appId;
  final String name;
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.value, required this.onChange});

  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final mode in AppThemeMode.values) ...[
          if (mode != AppThemeMode.system) const SizedBox(width: 10),
          Expanded(
            child: FButton(
              key: ValueKey('theme-mode-${mode.name}'),
              variant: value == mode
                  ? FButtonVariant.primary
                  : FButtonVariant.outline,
              onPress: () => onChange(mode),
              prefix: Icon(switch (mode) {
                AppThemeMode.system => FLucideIcons.monitor,
                AppThemeMode.light => FLucideIcons.sun,
                AppThemeMode.dark => FLucideIcons.moon,
              }),
              child: Text(switch (mode) {
                AppThemeMode.system => 'System',
                AppThemeMode.light => 'Light',
                AppThemeMode.dark => 'Dark',
              }),
            ),
          ),
        ],
      ],
    );
  }
}

class _CredentialHelpSection extends StatelessWidget {
  const _CredentialHelpSection({
    required this.title,
    required this.body,
    required this.steps,
    this.address,
  });

  final String title;
  final String body;
  final String steps;
  final String? address;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.theme.typography.body.md.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(body, style: context.theme.typography.body.sm),
        const SizedBox(height: 6),
        Text(steps, style: context.theme.typography.body.sm),
        if (address case final value?) ...[
          const SizedBox(height: 8),
          SelectableText(
            value,
            style: context.theme.typography.body.sm.copyWith(
              color: context.theme.colors.primary,
            ),
          ),
        ],
      ],
    );
  }
}

class _IgnoredGamesList extends StatelessWidget {
  const _IgnoredGamesList({
    required this.games,
    required this.enabled,
    required this.onRemove,
  });

  final List<String> games;
  final bool enabled;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) {
      return Text(
        'No ignored games.',
        style: context.theme.typography.body.sm.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.theme.colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (var index = 0; index < games.length; index++) ...[
            if (index > 0)
              Divider(height: 1, color: context.theme.colors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      games[index],
                      style: context.theme.typography.body.sm,
                    ),
                  ),
                  FButton.icon(
                    key: ValueKey('steam-ignored-remove-${games[index]}'),
                    variant: FButtonVariant.ghost,
                    size: FButtonSizeVariant.sm,
                    semanticsLabel: 'Remove ignored app ID ${games[index]}',
                    onPress: enabled ? () => onRemove(games[index]) : null,
                    child: const Icon(FLucideIcons.x),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomGamesList extends StatelessWidget {
  const _CustomGamesList({
    required this.games,
    required this.enabled,
    required this.onRemove,
  });

  final List<_CustomGame> games;
  final bool enabled;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) {
      return Text(
        'No custom game names.',
        style: context.theme.typography.body.sm.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.theme.colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (var index = 0; index < games.length; index++) ...[
            if (index > 0)
              Divider(height: 1, color: context.theme.colors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      games[index].appId,
                      style: context.theme.typography.body.sm.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      games[index].name,
                      style: context.theme.typography.body.sm,
                    ),
                  ),
                  FButton.icon(
                    key: ValueKey('steam-custom-remove-${games[index].appId}'),
                    variant: FButtonVariant.ghost,
                    size: FButtonSizeVariant.sm,
                    semanticsLabel: 'Remove custom game ${games[index].appId}',
                    onPress: enabled
                        ? () => onRemove(games[index].appId)
                        : null,
                    child: const Icon(FLucideIcons.x),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.label,
    required this.description,
    required this.value,
    required this.enabled,
    required this.onChange,
  });

  final String label;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.theme.typography.body.sm),
              const SizedBox(height: 2),
              Text(
                description,
                style: context.theme.typography.body.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        FSwitch(
          value: value,
          enabled: enabled,
          semanticsLabel: label,
          onChange: onChange,
        ),
      ],
    );
  }
}

class _DirectoryField extends StatelessWidget {
  const _DirectoryField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onBrowse,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback onBrowse;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: FTextField(
            control: FTextFieldControl.managed(controller: controller),
            label: Text(label),
            hint: hint,
            enabled: enabled,
          ),
        ),
        const SizedBox(width: 10),
        FButton(
          variant: FButtonVariant.outline,
          mainAxisSize: MainAxisSize.min,
          onPress: enabled ? onBrowse : null,
          child: const Text('Browse'),
        ),
      ],
    );
  }
}
