import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../models/app_settings.dart';
import '../services/library_scanner.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.controller, super.key});

  final LibraryController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _outputController;
  late final TextEditingController _diabloController;
  late final TextEditingController _guildWars2Controller;
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
  late bool _diabloUseCustomPath;
  late bool _guildWars2Enabled;
  late bool _guildWars2UseCustomPath;
  late bool _steamEnabled;
  late bool _steamUseCustomPath;
  late bool _steamOnlineGallery;
  late bool _steamDownloadCovers;
  String? _outputPathError;
  String? _diabloPathError;
  String? _guildWars2PathError;
  String? _steamPathError;
  Timer? _saveTimer;
  var _draftRevision = 0;
  var _hasPendingChanges = false;
  Future<void> _saveQueue = Future.value();

  @override
  void initState() {
    super.initState();
    _outputController = TextEditingController(
      text: widget.controller.settings.outputPath,
    );
    _diabloController = TextEditingController(
      text: widget.controller.settings.diabloIV.sourcePath,
    );
    _guildWars2Controller = TextEditingController(
      text: widget.controller.settings.guildWars2.sourcePath,
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
    _diabloUseCustomPath = widget.controller.settings.diabloIV.useCustomPath;
    _guildWars2Enabled = widget.controller.settings.guildWars2.enabled;
    _guildWars2UseCustomPath =
        widget.controller.settings.guildWars2.useCustomPath;
    _steamEnabled = steam.enabled;
    _steamUseCustomPath = steam.useCustomPath;
    _steamOnlineGallery = steam.onlineGallery;
    _steamDownloadCovers = steam.downloadCovers;
    _themeMode = widget.controller.settings.themeMode;

    for (final controller in [
      _outputController,
      _diabloController,
      _guildWars2Controller,
      _steamPathController,
      _steamUserController,
      _steamKeyController,
    ]) {
      controller.addListener(_scheduleAutosave);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_validateInitialPaths());
      }
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_hasPendingChanges) {
      final draft = _draftSettings();
      final revision = ++_draftRevision;
      unawaited(_validateAndSave(draft, revision: revision, showErrors: false));
    }
    _outputController.dispose();
    _diabloController.dispose();
    _guildWars2Controller.dispose();
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
                          _scheduleAutosave();
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
                        fieldKey: const ValueKey('library-path-field'),
                        controller: _outputController,
                        label: 'Library folder',
                        hint: '/path/to/media',
                        error: _outputPathError,
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
                              _scheduleAutosave();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      FCheckbox(
                        key: const ValueKey('diablo-custom-path'),
                        label: const Text('Use custom folder'),
                        description: const Text(
                          'Otherwise, the screenshot folder is discovered automatically.',
                        ),
                        value: _diabloUseCustomPath,
                        enabled: _diabloEnabled,
                        onChange: (value) {
                          setState(() {
                            _diabloUseCustomPath = value;
                            if (!value) {
                              _diabloPathError = null;
                            }
                          });
                          _scheduleAutosave(immediate: true);
                        },
                      ),
                      if (_diabloUseCustomPath) ...[
                        const SizedBox(height: 16),
                        _DirectoryField(
                          fieldKey: const ValueKey('diablo-path-field'),
                          controller: _diabloController,
                          label: 'Screenshot folder',
                          hint: '/path/to/Diablo IV',
                          error: _diabloPathError,
                          enabled: _diabloEnabled,
                          onBrowse: () => _chooseDirectory(
                            controller: _diabloController,
                            title: 'Choose the Diablo IV screenshot folder',
                          ),
                        ),
                      ],
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
                                  'Guild Wars 2',
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
                            key: const ValueKey('guild-wars-2-enabled'),
                            value: _guildWars2Enabled,
                            semanticsLabel: 'Enable Guild Wars 2',
                            onChange: (value) {
                              setState(() => _guildWars2Enabled = value);
                              _scheduleAutosave();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      FCheckbox(
                        key: const ValueKey('guild-wars-2-custom-path'),
                        label: const Text('Use custom folder'),
                        description: const Text(
                          'Otherwise, the screenshot folder is discovered automatically.',
                        ),
                        value: _guildWars2UseCustomPath,
                        enabled: _guildWars2Enabled,
                        onChange: (value) {
                          setState(() {
                            _guildWars2UseCustomPath = value;
                            if (!value) {
                              _guildWars2PathError = null;
                            }
                          });
                          _scheduleAutosave(immediate: true);
                        },
                      ),
                      if (_guildWars2UseCustomPath) ...[
                        const SizedBox(height: 16),
                        _DirectoryField(
                          fieldKey: const ValueKey('guild-wars-2-path-field'),
                          controller: _guildWars2Controller,
                          label: 'Screenshot folder',
                          hint: '/path/to/Guild Wars 2/Screens',
                          error: _guildWars2PathError,
                          enabled: _guildWars2Enabled,
                          onBrowse: () => _chooseDirectory(
                            controller: _guildWars2Controller,
                            title: 'Choose the Guild Wars 2 screenshot folder',
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        'Requires ExifTool.',
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
                              _scheduleAutosave();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      FCheckbox(
                        key: const ValueKey('steam-custom-path'),
                        label: const Text('Use custom folder'),
                        description: const Text(
                          'Otherwise, the Steam folder is discovered automatically.',
                        ),
                        value: _steamUseCustomPath,
                        enabled: _steamEnabled,
                        onChange: (value) {
                          setState(() {
                            _steamUseCustomPath = value;
                            if (!value) {
                              _steamPathError = null;
                            }
                          });
                          _scheduleAutosave(immediate: true);
                        },
                      ),
                      if (_steamUseCustomPath) ...[
                        const SizedBox(height: 16),
                        _DirectoryField(
                          fieldKey: const ValueKey('steam-path-field'),
                          controller: _steamPathController,
                          label: 'Steam folder',
                          hint: '/path/to/Steam',
                          error: _steamPathError,
                          enabled: _steamEnabled,
                          onBrowse: () => _chooseDirectory(
                            controller: _steamPathController,
                            title: 'Choose the Steam folder',
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _SwitchSetting(
                        label: 'Download game covers',
                        description: 'Save a cover.jpg file in each album.',
                        value: _steamDownloadCovers,
                        enabled: _steamEnabled,
                        onChange: (value) {
                          setState(() => _steamDownloadCovers = value);
                          _scheduleAutosave();
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
                          _scheduleAutosave();
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
              Text(
                'Changes are validated and saved automatically.',
                key: const ValueKey('settings-autosave-note'),
                style: context.theme.typography.body.sm.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
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

  void _scheduleAutosave({bool immediate = false}) {
    if (!mounted) {
      return;
    }

    _hasPendingChanges = true;
    final revision = ++_draftRevision;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 300),
      () {
        final draft = _draftSettings();
        unawaited(_validateAndSave(draft, revision: revision));
      },
    );
  }

  AppSettings _draftSettings() {
    return AppSettings(
      outputPath: _outputController.text.trim(),
      themeMode: _themeMode,
      diabloIV: ProviderSettings(
        enabled: _diabloEnabled,
        useCustomPath: _diabloUseCustomPath,
        sourcePath: _diabloController.text.trim(),
      ),
      guildWars2: ProviderSettings(
        enabled: _guildWars2Enabled,
        useCustomPath: _guildWars2UseCustomPath,
        sourcePath: _guildWars2Controller.text.trim(),
      ),
      steam: SteamSettings(
        enabled: _steamEnabled,
        useCustomPath: _steamUseCustomPath,
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
  }

  Future<void> _validateInitialPaths() async {
    final revision = _draftRevision;
    final errors = await _validatePaths(_draftSettings());
    if (!mounted || revision != _draftRevision) {
      return;
    }
    _showPathErrors(errors);
  }

  Future<void> _validateAndSave(
    AppSettings draft, {
    required int revision,
    bool showErrors = true,
  }) async {
    final errors = await _validatePaths(draft);
    if (revision != _draftRevision) {
      return;
    }

    _hasPendingChanges = false;
    if (showErrors && mounted) {
      _showPathErrors(errors);
    }

    final saved = widget.controller.settings;
    final safeSettings = AppSettings(
      outputPath: errors.outputPath == null
          ? draft.outputPath
          : saved.outputPath,
      themeMode: draft.themeMode,
      diabloIV: errors.diabloIV == null
          ? draft.diabloIV
          : saved.diabloIV.copyWith(enabled: draft.diabloIV.enabled),
      guildWars2: errors.guildWars2 == null
          ? draft.guildWars2
          : saved.guildWars2.copyWith(enabled: draft.guildWars2.enabled),
      steam: SteamSettings(
        enabled: draft.steam.enabled,
        useCustomPath: errors.steam == null
            ? draft.steam.useCustomPath
            : saved.steam.useCustomPath,
        userdataPath: errors.steam == null
            ? draft.steam.userdataPath
            : saved.steam.userdataPath,
        onlineGallery: draft.steam.onlineGallery,
        userId: draft.steam.userId,
        apiKey: draft.steam.apiKey,
        downloadCovers: draft.steam.downloadCovers,
        ignoredGames: draft.steam.ignoredGames,
        customGames: draft.steam.customGames,
      ),
    );

    _saveQueue = _saveQueue.then((_) async {
      await widget.controller.updateSettings(safeSettings);
    });
    await _saveQueue;
  }

  Future<_PathErrors> _validatePaths(AppSettings draft) async {
    final results = await Future.wait<String?>([
      _directoryError(
        draft.outputPath,
        label: 'Library folder',
        allowEmpty: true,
      ),
      draft.diabloIV.useCustomPath
          ? _directoryError(
              draft.diabloIV.sourcePath,
              label: 'Diablo IV screenshot folder',
            )
          : Future.value(),
      draft.guildWars2.useCustomPath
          ? _directoryError(
              draft.guildWars2.sourcePath,
              label: 'Guild Wars 2 screenshot folder',
            )
          : Future.value(),
      draft.steam.useCustomPath
          ? _directoryError(draft.steam.userdataPath, label: 'Steam folder')
          : Future.value(),
    ]);

    return _PathErrors(
      outputPath: results[0],
      diabloIV: results[1],
      guildWars2: results[2],
      steam: results[3],
    );
  }

  Future<String?> _directoryError(
    String path, {
    required String label,
    bool allowEmpty = false,
  }) async {
    final value = path.trim();
    if (value.isEmpty) {
      return allowEmpty ? null : 'Choose a folder.';
    }

    try {
      if (await Directory(expandUserPath(value)).exists()) {
        return null;
      }
    } on FileSystemException {
      // The same field error covers inaccessible and missing directories.
    }
    return '$label does not exist.';
  }

  void _showPathErrors(_PathErrors errors) {
    setState(() {
      _outputPathError = errors.outputPath;
      _diabloPathError = errors.diabloIV;
      _guildWars2PathError = errors.guildWars2;
      _steamPathError = errors.steam;
    });
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
    _scheduleAutosave();
  }

  void _removeIgnoredGame(String appId) {
    setState(() => _steamIgnoredGames.remove(appId));
    _scheduleAutosave();
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
    _scheduleAutosave();
  }

  void _removeCustomGame(String appId) {
    setState(
      () => _steamCustomGames.removeWhere((game) => game.appId == appId),
    );
    _scheduleAutosave();
  }
}

class _PathErrors {
  const _PathErrors({
    required this.outputPath,
    required this.diabloIV,
    required this.guildWars2,
    required this.steam,
  });

  final String? outputPath;
  final String? diabloIV;
  final String? guildWars2;
  final String? steam;
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
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.hint,
    required this.onBrowse,
    this.error,
    this.enabled = true,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback onBrowse;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.theme.typography.body.sm),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FTextField(
                key: fieldKey,
                control: FTextFieldControl.managed(controller: controller),
                hint: hint,
                error: error == null ? null : Text(error!),
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
        ),
      ],
    );
  }
}
