import 'dart:async';
import 'dart:io';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../providers/battle_net_provider.dart';
import '../services/battle_net_games.dart';
import '../models/app_settings.dart';
import '../services/folder_access_service.dart';
import '../services/library_scanner.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.controller, super.key});

  final LibraryController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _outputController;
  final Map<String, TextEditingController> _battleNetControllers = {};
  late final TextEditingController _guildWars2Controller;
  late final TextEditingController _hytaleController;
  late final TextEditingController _minecraftController;
  late final TextEditingController _nintendoSwitch2Controller;
  late final TextEditingController _nintendoSwitch2IgnoredInputController;
  late final TextEditingController _playStation4Controller;
  late final TextEditingController _playStation5Controller;
  late final TextEditingController _steamPathController;
  late final TextEditingController _steamUserController;
  late final TextEditingController _steamKeyController;
  late final TextEditingController _steamIgnoredInputController;
  late final TextEditingController _steamCustomIdController;
  late final TextEditingController _steamCustomNameController;
  late final List<String> _nintendoSwitch2IgnoredFolders;
  late final List<String> _steamIgnoredGames;
  late final List<_CustomGame> _steamCustomGames;
  late AppThemeMode _themeMode;
  late bool _diabloEnabled;
  final Map<String, bool> _battleNetUseCustomPath = {};
  final Map<String, bool> _battleNetGameEnabled = {};
  late bool _guildWars2Enabled;
  late bool _guildWars2UseCustomPath;
  late bool _hytaleEnabled;
  late bool _hytaleUseCustomPath;
  late bool _hytaleDownloadCovers;
  late bool _minecraftEnabled;
  late bool _minecraftUseCustomPath;
  late bool _nintendoSwitch2Enabled;
  late bool _nintendoSwitch2UseCustomPath;
  late bool _playStation4Enabled;
  late bool _playStation5Enabled;
  late bool _steamEnabled;
  late bool _steamUseCustomPath;
  late bool _steamOnlineGallery;
  late bool _steamDownloadCovers;
  String? _outputPathError;
  String? _diabloPathError;
  final Map<String, String?> _battleNetGameErrors = {};
  String? _guildWars2PathError;
  String? _hytalePathError;
  String? _minecraftPathError;
  String? _nintendoSwitch2PathError;
  String? _playStation4PathError;
  String? _playStation5PathError;
  String? _steamPathError;
  Timer? _saveTimer;
  var _draftRevision = 0;
  var _hasPendingChanges = false;
  var _suppressAutosave = false;
  var _settingsTab = 0;
  _SettingsProvider? _expandedProvider;
  final _providerActivationErrors = <_SettingsProvider, String>{};
  Future<void> _saveQueue = Future.value();

  /// Rebuilds the per-game editing state from saved settings. Each game keeps
  /// its own switch, custom-folder flag and path, so they are held in maps
  /// keyed by game id rather than as fields.
  void _loadBattleNetGameState(AppSettings settings) {
    for (final game in battleNetGames) {
      final saved = settings.battleNet.game(game.id);
      _battleNetGameEnabled[game.id] = saved.enabled;
      _battleNetUseCustomPath[game.id] = saved.useCustomPath;
      final controller = _battleNetControllers[game.id];
      if (controller == null) {
        _battleNetControllers[game.id] = TextEditingController(
          text: saved.sourcePath,
        );
      } else {
        controller.text = saved.sourcePath;
      }
    }
  }

  void _setBattleNetGameEnabled(BattleNetGame game, bool value) {
    setState(() {
      _battleNetGameEnabled[game.id] = value;
      if (!value) {
        _battleNetGameErrors.remove(game.id);
      }
    });
    _scheduleAutosave(immediate: true);
  }

  Future<void> _setBattleNetGameCustomPath(
    BattleNetGame game,
    bool value,
  ) async {
    setState(() {
      _battleNetUseCustomPath[game.id] = value;
      if (!value) {
        _battleNetControllerFor(game.id).text = '';
        _battleNetGameErrors.remove(game.id);
      }
    });
    if (!value || !widget.controller.usesPersistentFolderAccess) {
      // Off macOS the field is simply typed into, as it is for every other
      // provider. On macOS picking the folder is also how the grant is made,
      // so the dialog opens straight away.
      _scheduleAutosave(immediate: true);
      return;
    }
    await _chooseDirectory(
      SettingsFolderTarget.battleNetGameCustom,
      initialPath: _battleNetControllerFor(game.id).text,
      gameId: game.id,
    );
  }

  bool _battleNetGameOn(String gameId) => _battleNetGameEnabled[gameId] ?? true;

  bool _battleNetGameCustom(String gameId) =>
      _battleNetUseCustomPath[gameId] ?? false;

  TextEditingController _battleNetControllerFor(String gameId) =>
      _battleNetControllers.putIfAbsent(gameId, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    _outputController = TextEditingController(
      text: widget.controller.settings.outputPath,
    );
    _loadBattleNetGameState(widget.controller.settings);
    _guildWars2Controller = TextEditingController(
      text: widget.controller.settings.guildWars2.sourcePath,
    );
    final hytale = widget.controller.settings.hytale;
    _hytaleController = TextEditingController(text: hytale.sourcePath);
    final minecraft = widget.controller.settings.minecraft;
    _minecraftController = TextEditingController(text: minecraft.sourcePath);
    final nintendoSwitch2 = widget.controller.settings.nintendoSwitch2;
    _nintendoSwitch2Controller = TextEditingController(
      text: nintendoSwitch2.sourcePath,
    );
    _nintendoSwitch2IgnoredInputController = TextEditingController();
    _nintendoSwitch2IgnoredFolders = nintendoSwitch2.ignoredFolders.toList();
    final playStation4 = widget.controller.settings.playStation4;
    _playStation4Controller = TextEditingController(
      text: playStation4.sourcePath,
    );
    final playStation5 = widget.controller.settings.playStation5;
    _playStation5Controller = TextEditingController(
      text: playStation5.sourcePath,
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
    _diabloEnabled = widget.controller.settings.battleNet.enabled;
    _guildWars2Enabled = widget.controller.settings.guildWars2.enabled;
    _guildWars2UseCustomPath =
        widget.controller.settings.guildWars2.useCustomPath;
    _hytaleEnabled = hytale.enabled;
    _hytaleUseCustomPath = hytale.useCustomPath;
    _hytaleDownloadCovers = hytale.downloadCovers;
    _minecraftEnabled = minecraft.enabled;
    _minecraftUseCustomPath = minecraft.useCustomPath;
    _nintendoSwitch2Enabled = nintendoSwitch2.enabled;
    _nintendoSwitch2UseCustomPath = nintendoSwitch2.useCustomPath;
    _playStation4Enabled = playStation4.enabled;
    _playStation5Enabled = playStation5.enabled;
    _steamEnabled = steam.enabled;
    _steamUseCustomPath = steam.useCustomPath;
    _steamOnlineGallery = steam.onlineGallery;
    _steamDownloadCovers = steam.downloadCovers;
    _themeMode = widget.controller.settings.themeMode;
    for (final provider in _SettingsProvider.values) {
      final error = widget.controller.providerValidationError(
        _providerName(provider),
      );
      if (error != null) {
        _providerActivationErrors[provider] = error;
      }
    }
    if (_providerActivationErrors.isNotEmpty) {
      _expandedProvider = _providerActivationErrors.keys.first;
    }

    for (final controller in [
      _outputController,
      ..._battleNetControllers.values,
      _guildWars2Controller,
      _hytaleController,
      _minecraftController,
      _nintendoSwitch2Controller,
      _playStation4Controller,
      _playStation5Controller,
      _steamPathController,
      _steamUserController,
      _steamKeyController,
    ]) {
      controller.addListener(_onTextChanged);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_validateInitialPaths());
      }
    });
  }

  void _onTextChanged() {
    if (!_suppressAutosave) {
      _scheduleAutosave();
    }
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
    for (final controller in _battleNetControllers.values) {
      controller.dispose();
    }
    _guildWars2Controller.dispose();
    _hytaleController.dispose();
    _minecraftController.dispose();
    _nintendoSwitch2Controller.dispose();
    _nintendoSwitch2IgnoredInputController.dispose();
    _playStation4Controller.dispose();
    _playStation5Controller.dispose();
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
          child: _SettingsSections(
            sortProviders: _settingsTab == 2,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Library and provider setup',
                style: context.theme.typography.body.sm.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
              const SizedBox(height: 18),
              FTabs(
                key: const ValueKey('settings-tabs'),
                control: FTabControl.lifted(
                  index: _settingsTab,
                  onChange: (index) => setState(() => _settingsTab = index),
                ),
                children: const [
                  FTabEntry(
                    label: Text(
                      'Appearance',
                      key: ValueKey('settings-tab-appearance'),
                    ),
                    child: SizedBox.shrink(),
                  ),
                  FTabEntry(
                    label: Text(
                      'Library',
                      key: ValueKey('settings-tab-library'),
                    ),
                    child: SizedBox.shrink(),
                  ),
                  FTabEntry(
                    label: Text(
                      'Providers',
                      key: ValueKey('settings-tab-providers'),
                    ),
                    child: SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (_settingsTab == 0) ...[
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
              ],
              if (_settingsTab == 1) ...[
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
                          readOnly:
                              widget.controller.usesPersistentFolderAccess,
                          buttonLabel: _folderButtonLabel(
                            FolderGrantIds.library,
                          ),
                          onBrowse: () => _chooseDirectory(
                            SettingsFolderTarget.library,
                            initialPath: _outputController.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_settingsTab == 2)
                FCard(
                  key: const ValueKey('provider-sort-Battle.net'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProviderHeader(
                          headerKey: const ValueKey('provider-card-battle-net'),
                          switchKey: const ValueKey('battle-net-enabled'),
                          name: 'Battle.net',
                          description: 'PC · Installed Blizzard games',
                          expanded:
                              _expandedProvider == _SettingsProvider.battleNet,
                          enabled: _diabloEnabled,
                          error:
                              _providerActivationErrors[_SettingsProvider
                                  .battleNet],
                          onTap: () =>
                              _toggleProvider(_SettingsProvider.battleNet),
                          onEnabled: (value) => unawaited(
                            _setProviderEnabled(
                              _SettingsProvider.battleNet,
                              value,
                            ),
                          ),
                        ),
                        if (_expandedProvider ==
                            _SettingsProvider.battleNet) ...[
                          const SizedBox(height: 18),
                          Text(
                            _diabloPathError ?? 'Each game is checked for in its default screenshot folder. Turn off a game to skip it, or point it somewhere else.',
                            key: const ValueKey('battle-net-summary'),
                            style: context.theme.typography.body.sm.copyWith(
                              color: _diabloPathError == null
                                  ? context.theme.colors.mutedForeground
                                  : context.theme.colors.destructive,
                            ),
                          ),
                          for (final folder
                              in widget.controller.battleNetGameFolders(
                                _draftSettings(),
                              )) ...[
                            const SizedBox(height: 18),
                            _BattleNetGameRow(
                              folder: folder,
                              enabled: _battleNetGameOn(folder.game.id),
                              useCustomPath: _battleNetGameCustom(
                                folder.game.id,
                              ),
                              controller: _battleNetControllerFor(
                                folder.game.id,
                              ),
                              error: _battleNetGameErrors[folder.game.id],
                              usesPersistentFolderAccess:
                                  widget.controller.usesPersistentFolderAccess,
                              access: widget.controller.folderAuthorization(
                                BattleNetProvider.grantIdForGame(
                                  folder.game.id,
                                ),
                              ),
                              folderButtonLabel: _folderButtonLabel(
                                BattleNetProvider.grantIdForGame(
                                  folder.game.id,
                                ),
                              ),
                              onEnabled: (value) =>
                                  _setBattleNetGameEnabled(folder.game, value),
                              onUseCustomPath: (value) =>
                                  _setBattleNetGameCustomPath(
                                    folder.game,
                                    value,
                                  ),
                              onBrowse: () => _chooseDirectory(
                                SettingsFolderTarget.battleNetGameCustom,
                                initialPath: _battleNetControllerFor(
                                  folder.game.id,
                                ).text,
                                gameId: folder.game.id,
                              ),
                              onAllow: () => _chooseDirectory(
                                SettingsFolderTarget.battleNetGameAutomatic,
                                initialPath: folder.path,
                                gameId: folder.game.id,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              if (_settingsTab == 2) const SizedBox(height: 12),
              if (_settingsTab == 2)
                FCard(
                  key: const ValueKey('provider-sort-Hytale'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProviderHeader(
                          headerKey: const ValueKey('provider-card-hytale'),
                          switchKey: const ValueKey('hytale-enabled'),
                          name: 'Hytale',
                          description: 'PC · Screenshots',
                          expanded:
                              _expandedProvider == _SettingsProvider.hytale,
                          enabled: _hytaleEnabled,
                          error:
                              _providerActivationErrors[_SettingsProvider
                                  .hytale],
                          onTap: () =>
                              _toggleProvider(_SettingsProvider.hytale),
                          onEnabled: (value) => unawaited(
                            _setProviderEnabled(
                              _SettingsProvider.hytale,
                              value,
                            ),
                          ),
                        ),
                        if (_expandedProvider == _SettingsProvider.hytale) ...[
                          const SizedBox(height: 18),
                          FCheckbox(
                            key: const ValueKey('hytale-custom-path'),
                            label: const Text('Use custom folder'),
                            description: const Text(
                              'Otherwise, the screenshot folder is discovered automatically.',
                            ),
                            value: _hytaleUseCustomPath,
                            enabled: true,
                            onChange: (value) => unawaited(
                              _setCustomPath(_SettingsProvider.hytale, value),
                            ),
                          ),
                          if (_hytaleUseCustomPath) ...[
                            const SizedBox(height: 16),
                            _DirectoryField(
                              fieldKey: const ValueKey('hytale-path-field'),
                              controller: _hytaleController,
                              label: 'Screenshot folder',
                              hint: '/path/to/Hytale Screenshots',
                              error: _hytalePathError,
                              readOnly:
                                  widget.controller.usesPersistentFolderAccess,
                              buttonLabel: _folderButtonLabel(
                                FolderGrantIds.hytale,
                              ),
                              onBrowse: () => _chooseDirectory(
                                SettingsFolderTarget.hytaleCustom,
                                initialPath: _hytaleController.text,
                              ),
                            ),
                          ] else if (widget
                              .controller
                              .usesPersistentFolderAccess) ...[
                            const SizedBox(height: 16),
                            _FolderAccessRow(
                              buttonKey: const ValueKey(
                                'hytale-automatic-folder-access',
                              ),
                              providerName: 'Hytale',
                              automaticDescription: 'Hytale screenshots are stored in “Pictures/Hytale Screenshots”. The macOS dialog will open that folder; click Allow Access to grant access.',
                              status: widget.controller.folderAuthorization(
                                FolderGrantIds.hytale,
                              ),
                              error: _hytalePathError,
                              onAllow: () => _chooseAutomaticDirectory(
                                SettingsFolderTarget.hytaleAutomatic,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _SwitchSetting(
                            switchKey: const ValueKey('hytale-bundled-cover'),
                            label: 'Use bundled game cover',
                            description:
                                'Save the included cover.png in the album.',
                            value: _hytaleDownloadCovers,
                            enabled: true,
                            onChange: (value) {
                              setState(() => _hytaleDownloadCovers = value);
                              _scheduleAutosave();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (_settingsTab == 2) const SizedBox(height: 12),
              if (_settingsTab == 2)
                _PlayStationProviderCard(
                  headerKey: const ValueKey('provider-card-playstation-4'),
                  name: 'PlayStation 4',
                  description: 'Screenshots and 30-second clips',
                  fieldKey: const ValueKey('playstation-4-path-field'),
                  switchKey: const ValueKey('playstation-4-enabled'),
                  controller: _playStation4Controller,
                  expanded: _expandedProvider == _SettingsProvider.playStation4,
                  enabled: _playStation4Enabled,
                  activationError:
                      _providerActivationErrors[_SettingsProvider.playStation4],
                  error: _playStation4PathError,
                  readOnly: widget.controller.usesPersistentFolderAccess,
                  buttonLabel: _playStation4Enabled
                      ? _folderButtonLabel(FolderGrantIds.playStation4)
                      : 'Select Folder',
                  requirement: 'Requires ExifTool to read screenshot dates.',
                  onTap: () => _toggleProvider(_SettingsProvider.playStation4),
                  onEnabled: (value) => unawaited(
                    _setProviderEnabled(_SettingsProvider.playStation4, value),
                  ),
                  onBrowse: () => _chooseDirectory(
                    SettingsFolderTarget.playStation4Custom,
                    initialPath: _playStation4Controller.text,
                  ),
                ),
              if (_settingsTab == 2) const SizedBox(height: 12),
              if (_settingsTab == 2)
                _PlayStationProviderCard(
                  headerKey: const ValueKey('provider-card-playstation-5'),
                  name: 'PlayStation 5',
                  description: 'Screenshots and 30-second clips',
                  fieldKey: const ValueKey('playstation-5-path-field'),
                  switchKey: const ValueKey('playstation-5-enabled'),
                  controller: _playStation5Controller,
                  expanded: _expandedProvider == _SettingsProvider.playStation5,
                  enabled: _playStation5Enabled,
                  activationError:
                      _providerActivationErrors[_SettingsProvider.playStation5],
                  error: _playStation5PathError,
                  readOnly: widget.controller.usesPersistentFolderAccess,
                  buttonLabel: _playStation5Enabled
                      ? _folderButtonLabel(FolderGrantIds.playStation5)
                      : 'Select Folder',
                  requirement: 'FFprobe is optional. Without it, clips use the end time in their filename.',
                  onTap: () => _toggleProvider(_SettingsProvider.playStation5),
                  onEnabled: (value) => unawaited(
                    _setProviderEnabled(_SettingsProvider.playStation5, value),
                  ),
                  onBrowse: () => _chooseDirectory(
                    SettingsFolderTarget.playStation5Custom,
                    initialPath: _playStation5Controller.text,
                  ),
                ),
              if (_settingsTab == 2) const SizedBox(height: 12),
              if (_settingsTab == 2)
                FCard(
                  key: const ValueKey('provider-sort-Nintendo Switch 2'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProviderHeader(
                          headerKey: const ValueKey(
                            'provider-card-nintendo-switch-2',
                          ),
                          switchKey: const ValueKey(
                            'nintendo-switch-2-enabled',
                          ),
                          name: 'Nintendo Switch 2',
                          description: 'Console · Screenshots and clips',
                          expanded:
                              _expandedProvider ==
                              _SettingsProvider.nintendoSwitch2,
                          enabled: _nintendoSwitch2Enabled,
                          error:
                              _providerActivationErrors[_SettingsProvider
                                  .nintendoSwitch2],
                          onTap: () => _toggleProvider(
                            _SettingsProvider.nintendoSwitch2,
                          ),
                          onEnabled: (value) => unawaited(
                            _setProviderEnabled(
                              _SettingsProvider.nintendoSwitch2,
                              value,
                            ),
                          ),
                        ),
                        if (_expandedProvider ==
                            _SettingsProvider.nintendoSwitch2) ...[
                          const SizedBox(height: 18),
                          FCheckbox(
                            key: const ValueKey(
                              'nintendo-switch-2-custom-path',
                            ),
                            label: const Text('Use copied album folder'),
                            description: const Text(
                              'Otherwise, read a connected console over USB on Linux.',
                            ),
                            value: _nintendoSwitch2UseCustomPath,
                            enabled: true,
                            onChange: (value) => unawaited(
                              _setCustomPath(
                                _SettingsProvider.nintendoSwitch2,
                                value,
                              ),
                            ),
                          ),
                          if (_nintendoSwitch2UseCustomPath) ...[
                            const SizedBox(height: 16),
                            _DirectoryField(
                              fieldKey: const ValueKey(
                                'nintendo-switch-2-path-field',
                              ),
                              controller: _nintendoSwitch2Controller,
                              label: 'Copied album folder',
                              hint: '/path/to/Nintendo Switch 2 album',
                              error: _nintendoSwitch2PathError,
                              readOnly:
                                  widget.controller.usesPersistentFolderAccess,
                              buttonLabel: _folderButtonLabel(
                                FolderGrantIds.nintendoSwitch2,
                              ),
                              onBrowse: () => _chooseDirectory(
                                SettingsFolderTarget.nintendoSwitch2Custom,
                                initialPath: _nintendoSwitch2Controller.text,
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 10),
                            Text(
                              'Direct collection requires Linux and the mtp-folders, mtp-files, and mtp-connect tools from libmtp.',
                              style: context.theme.typography.body.xs.copyWith(
                                color: context.theme.colors.mutedForeground,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: FTextField(
                                  key: const ValueKey(
                                    'nintendo-switch-2-ignored-input',
                                  ),
                                  control: FTextFieldControl.managed(
                                    controller:
                                        _nintendoSwitch2IgnoredInputController,
                                  ),
                                  label: const Text('Ignored album folder'),
                                  hint: 'Other folder',
                                  onSubmit: (_) =>
                                      _addNintendoSwitch2IgnoredFolder(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FButton(
                                key: const ValueKey(
                                  'nintendo-switch-2-ignored-add',
                                ),
                                variant: FButtonVariant.outline,
                                mainAxisSize: MainAxisSize.min,
                                onPress: _addNintendoSwitch2IgnoredFolder,
                                prefix: const Icon(FLucideIcons.plus),
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Skip the console folder used for captures outside games, or any game you do not want to import.',
                            style: context.theme.typography.body.xs.copyWith(
                              color: context.theme.colors.mutedForeground,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _IgnoredFoldersList(
                            folders: _nintendoSwitch2IgnoredFolders,
                            enabled: true,
                            onRemove: _removeNintendoSwitch2IgnoredFolder,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (_settingsTab == 2) const SizedBox(height: 12),
              if (_settingsTab == 2)
                FCard(
                  key: const ValueKey('provider-sort-Minecraft'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProviderHeader(
                          headerKey: const ValueKey('provider-card-minecraft'),
                          switchKey: const ValueKey('minecraft-enabled'),
                          name: 'Minecraft',
                          description: 'PC · Launcher and Flatpak screenshots',
                          expanded:
                              _expandedProvider == _SettingsProvider.minecraft,
                          enabled: _minecraftEnabled,
                          error:
                              _providerActivationErrors[_SettingsProvider
                                  .minecraft],
                          onTap: () =>
                              _toggleProvider(_SettingsProvider.minecraft),
                          onEnabled: (value) => unawaited(
                            _setProviderEnabled(
                              _SettingsProvider.minecraft,
                              value,
                            ),
                          ),
                        ),
                        if (_expandedProvider ==
                            _SettingsProvider.minecraft) ...[
                          const SizedBox(height: 18),
                          FCheckbox(
                            key: const ValueKey('minecraft-custom-path'),
                            label: const Text('Use custom folder'),
                            description: const Text(
                              'Otherwise, launcher and Flatpak folders are discovered automatically.',
                            ),
                            value: _minecraftUseCustomPath,
                            enabled: true,
                            onChange: (value) => unawaited(
                              _setCustomPath(
                                _SettingsProvider.minecraft,
                                value,
                              ),
                            ),
                          ),
                          if (_minecraftUseCustomPath) ...[
                            const SizedBox(height: 16),
                            _DirectoryField(
                              fieldKey: const ValueKey('minecraft-path-field'),
                              controller: _minecraftController,
                              label: 'Screenshot folder',
                              hint: '/path/to/.minecraft/screenshots',
                              error: _minecraftPathError,
                              readOnly:
                                  widget.controller.usesPersistentFolderAccess,
                              buttonLabel: _folderButtonLabel(
                                FolderGrantIds.minecraft,
                              ),
                              onBrowse: () => _chooseDirectory(
                                SettingsFolderTarget.minecraftCustom,
                                initialPath: _minecraftController.text,
                              ),
                            ),
                          ] else if (widget
                              .controller
                              .usesPersistentFolderAccess) ...[
                            const SizedBox(height: 16),
                            _FolderAccessRow(
                              buttonKey: const ValueKey(
                                'minecraft-automatic-folder-access',
                              ),
                              providerName: 'Minecraft',
                              automaticDescription: 'Minecraft screenshots are stored in the launcher screenshots folder. The macOS dialog will open it; click Allow Access to grant access.',
                              status: widget.controller.folderAuthorization(
                                FolderGrantIds.minecraft,
                              ),
                              error: _minecraftPathError,
                              onAllow: () => _chooseAutomaticDirectory(
                                SettingsFolderTarget.minecraftAutomatic,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              if (_settingsTab == 2) const SizedBox(height: 12),
              if (_settingsTab == 2)
                FCard(
                  key: const ValueKey('provider-sort-Guild Wars 2'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProviderHeader(
                          headerKey: const ValueKey(
                            'provider-card-guild-wars-2',
                          ),
                          switchKey: const ValueKey('guild-wars-2-enabled'),
                          name: 'Guild Wars 2',
                          description: 'PC · Screenshots',
                          expanded:
                              _expandedProvider == _SettingsProvider.guildWars2,
                          enabled: _guildWars2Enabled,
                          error:
                              _providerActivationErrors[_SettingsProvider
                                  .guildWars2],
                          onTap: () =>
                              _toggleProvider(_SettingsProvider.guildWars2),
                          onEnabled: (value) => unawaited(
                            _setProviderEnabled(
                              _SettingsProvider.guildWars2,
                              value,
                            ),
                          ),
                        ),
                        if (_expandedProvider ==
                            _SettingsProvider.guildWars2) ...[
                          const SizedBox(height: 18),
                          FCheckbox(
                            key: const ValueKey('guild-wars-2-custom-path'),
                            label: const Text('Use custom folder'),
                            description: const Text(
                              'Otherwise, the screenshot folder is discovered automatically.',
                            ),
                            value: _guildWars2UseCustomPath,
                            enabled: true,
                            onChange: (value) => unawaited(
                              _setCustomPath(
                                _SettingsProvider.guildWars2,
                                value,
                              ),
                            ),
                          ),
                          if (!_guildWars2UseCustomPath &&
                              _guildWars2PathError != null) ...[
                            const SizedBox(height: 8),
                            _InlinePathError(_guildWars2PathError!),
                          ],
                          if (_guildWars2UseCustomPath) ...[
                            const SizedBox(height: 16),
                            _DirectoryField(
                              fieldKey: const ValueKey(
                                'guild-wars-2-path-field',
                              ),
                              controller: _guildWars2Controller,
                              label: 'Screenshot folder',
                              hint: '/path/to/Guild Wars 2/Screens',
                              error: _guildWars2PathError,
                              readOnly:
                                  widget.controller.usesPersistentFolderAccess,
                              buttonLabel: _folderButtonLabel(
                                FolderGrantIds.guildWars2,
                              ),
                              onBrowse: () => _chooseDirectory(
                                SettingsFolderTarget.guildWars2Custom,
                                initialPath: _guildWars2Controller.text,
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
                      ],
                    ),
                  ),
                ),
              if (_settingsTab == 2) const SizedBox(height: 12),
              if (_settingsTab == 2)
                FCard(
                  key: const ValueKey('provider-sort-Steam'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProviderHeader(
                          headerKey: const ValueKey('provider-card-steam'),
                          switchKey: const ValueKey('steam-enabled'),
                          name: 'Steam',
                          description: 'PC · Local and online screenshots',
                          expanded:
                              _expandedProvider == _SettingsProvider.steam,
                          enabled: _steamEnabled,
                          error:
                              _providerActivationErrors[_SettingsProvider
                                  .steam],
                          onTap: () => _toggleProvider(_SettingsProvider.steam),
                          onEnabled: (value) => unawaited(
                            _setProviderEnabled(_SettingsProvider.steam, value),
                          ),
                        ),
                        if (_expandedProvider == _SettingsProvider.steam) ...[
                          const SizedBox(height: 18),
                          FCheckbox(
                            key: const ValueKey('steam-custom-path'),
                            label: const Text('Use custom folder'),
                            description: const Text(
                              'Otherwise, the Steam folder is discovered automatically.',
                            ),
                            value: _steamUseCustomPath,
                            enabled: true,
                            onChange: (value) => unawaited(
                              _setCustomPath(_SettingsProvider.steam, value),
                            ),
                          ),
                          if (_steamUseCustomPath) ...[
                            const SizedBox(height: 16),
                            _DirectoryField(
                              fieldKey: const ValueKey('steam-path-field'),
                              controller: _steamPathController,
                              label: 'Steam folder',
                              hint: '/path/to/Steam',
                              error: _steamPathError,
                              readOnly:
                                  widget.controller.usesPersistentFolderAccess,
                              buttonLabel: _folderButtonLabel(
                                FolderGrantIds.steam,
                              ),
                              onBrowse: () => _chooseDirectory(
                                SettingsFolderTarget.steamCustom,
                                initialPath: _steamPathController.text,
                              ),
                            ),
                          ] else if (widget
                              .controller
                              .usesPersistentFolderAccess) ...[
                            const SizedBox(height: 16),
                            _FolderAccessRow(
                              buttonKey: const ValueKey(
                                'steam-automatic-folder-access',
                              ),
                              providerName: 'Steam',
                              automaticDescription: 'Steam screenshots are stored in its “userdata” folder. The macOS dialog will open Steam; click Allow Access to grant access to that folder.',
                              status: widget.controller.folderAuthorization(
                                FolderGrantIds.steam,
                              ),
                              error: _steamPathError,
                              onAllow: () => _chooseAutomaticDirectory(
                                SettingsFolderTarget.steamAutomatic,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _SwitchSetting(
                            label: 'Download game covers',
                            description: 'Save a cover.jpg file in each album.',
                            value: _steamDownloadCovers,
                            enabled: true,
                            onChange: (value) {
                              setState(() => _steamDownloadCovers = value);
                              _scheduleAutosave();
                            },
                          ),
                          const SizedBox(height: 12),
                          _SwitchSetting(
                            label: 'Import online gallery',
                            description:
                                'Import public screenshots from Steam.',
                            value: _steamOnlineGallery,
                            enabled: true,
                            onChange: (value) {
                              setState(() => _steamOnlineGallery = value);
                              _scheduleAutosave();
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Text(
                                'Steam credentials',
                                style: context.theme.typography.body.sm
                                    .copyWith(fontWeight: FontWeight.w600),
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
                                  key: const ValueKey('steam-user-id'),
                                  control: FTextFieldControl.managed(
                                    controller: _steamUserController,
                                  ),
                                  label: const Text('Steam user ID'),
                                  hint: '7656119…',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FTextField.password(
                                  key: const ValueKey('steam-api-key'),
                                  control: FTextFieldControl.managed(
                                    controller: _steamKeyController,
                                  ),
                                  label: const Text('Steam Web API key'),
                                  hint: 'Required for game names',
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
                                  onSubmit: (_) => _addIgnoredGame(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FButton(
                                key: const ValueKey('steam-ignored-add'),
                                variant: FButtonVariant.outline,
                                mainAxisSize: MainAxisSize.min,
                                onPress: _addIgnoredGame,
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
                            enabled: true,
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
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: FTextField(
                                  key: const ValueKey(
                                    'steam-custom-name-input',
                                  ),
                                  control: FTextFieldControl.managed(
                                    controller: _steamCustomNameController,
                                  ),
                                  label: const Text('Custom game name'),
                                  hint: 'My Game',
                                  onSubmit: (_) => _addCustomGame(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FButton(
                                key: const ValueKey('steam-custom-add'),
                                variant: FButtonVariant.outline,
                                mainAxisSize: MainAxisSize.min,
                                onPress: _addCustomGame,
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
                            enabled: true,
                            onRemove: _removeCustomGame,
                          ),
                        ],
                      ],
                    ),
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

  void _toggleProvider(_SettingsProvider provider) {
    setState(() {
      _expandedProvider = _expandedProvider == provider ? null : provider;
    });
  }

  Future<void> _chooseDirectory(
    SettingsFolderTarget target, {
    String? initialPath,
    String? gameId,
  }) async {
    final provider = _providerForFolderTarget(target);
    final wasEnabled = provider == null ? null : _providerEnabled(provider);
    await _flushPendingChanges();
    if (!mounted) {
      return;
    }

    final result = await widget.controller.chooseFolder(
      target,
      initialPath: initialPath,
      gameId: gameId,
    );
    if (!mounted || result.cancelled) {
      return;
    }
    if (!result.saved) {
      setState(() => _setFolderError(target, result.message));
      return;
    }

    if (provider != null && wasEnabled == false) {
      await widget.controller.updateSettings(
        _settingsWithProviderEnabled(
          widget.controller.settings,
          provider,
          false,
        ),
        showNotification: false,
      );
      if (!mounted) {
        return;
      }
    }

    _suppressAutosave = true;
    final saved = widget.controller.settings;
    _outputController.text = saved.outputPath;
    _loadBattleNetGameState(saved);
    _guildWars2Controller.text = saved.guildWars2.sourcePath;
    _hytaleController.text = saved.hytale.sourcePath;
    _minecraftController.text = saved.minecraft.sourcePath;
    _nintendoSwitch2Controller.text = saved.nintendoSwitch2.sourcePath;
    _playStation4Controller.text = saved.playStation4.sourcePath;
    _playStation5Controller.text = saved.playStation5.sourcePath;
    _steamPathController.text = saved.steam.userdataPath;
    _suppressAutosave = false;
    setState(() {
      _diabloEnabled = saved.battleNet.enabled;
      _guildWars2Enabled = saved.guildWars2.enabled;
      _guildWars2UseCustomPath = saved.guildWars2.useCustomPath;
      _hytaleEnabled = saved.hytale.enabled;
      _hytaleUseCustomPath = saved.hytale.useCustomPath;
      _minecraftEnabled = saved.minecraft.enabled;
      _minecraftUseCustomPath = saved.minecraft.useCustomPath;
      _nintendoSwitch2Enabled = saved.nintendoSwitch2.enabled;
      _nintendoSwitch2UseCustomPath = saved.nintendoSwitch2.useCustomPath;
      _playStation4Enabled = saved.playStation4.enabled;
      _playStation5Enabled = saved.playStation5.enabled;
      _steamEnabled = saved.steam.enabled;
      _steamUseCustomPath = saved.steam.useCustomPath;
      _setFolderError(target, null);
    });
  }

  Future<void> _chooseAutomaticDirectory(SettingsFolderTarget target) async {
    final candidates = widget.controller.automaticFolderCandidates(target);
    if (candidates.isEmpty) {
      if (mounted) {
        setState(
          () => _setFolderError(
            target,
            'No supported ${_automaticProviderName(target)} folder was found on this platform.',
          ),
        );
      }
      return;
    }

    final candidate = candidates.length == 1
        ? candidates.single
        : await _showAutomaticFolderChoices(target, candidates);
    if (candidate == null || !mounted) {
      return;
    }
    await _chooseDirectory(target, initialPath: candidate.path);
  }

  Future<AutomaticFolderCandidate?> _showAutomaticFolderChoices(
    SettingsFolderTarget target,
    List<AutomaticFolderCandidate> candidates,
  ) {
    final providerName = _automaticProviderName(target);
    return showFDialog<AutomaticFolderCandidate>(
      context: context,
      builder: (dialogContext, _, animation) => FDialog(
        animation: animation,
        semanticsLabel: 'Choose a $providerName folder',
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose a $providerName folder',
                  style: context.theme.typography.display.sm,
                ),
                const SizedBox(height: 8),
                Text(
                  'More than one supported $providerName folder is available. Choose the one used by your installation. macOS will then ask you to confirm that exact folder.',
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 18),
                for (final candidate in candidates) ...[
                  FButton(
                    key: ValueKey('automatic-folder-${candidate.path}'),
                    variant: FButtonVariant.outline,
                    onPress: () => Navigator.of(dialogContext).pop(candidate),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(candidate.name),
                          const SizedBox(height: 2),
                          Text(
                            candidate.path,
                            style: context.theme.typography.body.xs.copyWith(
                              color: context.theme.colors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: FButton(
                    variant: FButtonVariant.ghost,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setProviderEnabled(
    _SettingsProvider provider,
    bool value,
  ) async {
    if (!value) {
      setState(() {
        _setProviderEnabledValue(provider, false);
        _providerActivationErrors.remove(provider);
      });
      _scheduleAutosave(immediate: true);
      return;
    }

    setState(() {
      _expandedProvider = provider;
      _providerActivationErrors.remove(provider);
    });

    if (!widget.controller.usesPersistentFolderAccess) {
      await _enableProviderIfValid(provider);
      return;
    }

    final target = switch ((provider, _usesCustomPath(provider))) {
      // Battle.net folders are chosen per game, from the game's own row.
      (_SettingsProvider.battleNet, _) => null,
      (_SettingsProvider.guildWars2, true) =>
        SettingsFolderTarget.guildWars2Custom,
      (_SettingsProvider.hytale, true) => SettingsFolderTarget.hytaleCustom,
      (_SettingsProvider.hytale, false) => SettingsFolderTarget.hytaleAutomatic,
      (_SettingsProvider.minecraft, true) =>
        SettingsFolderTarget.minecraftCustom,
      (_SettingsProvider.minecraft, false) =>
        SettingsFolderTarget.minecraftAutomatic,
      (_SettingsProvider.nintendoSwitch2, true) =>
        SettingsFolderTarget.nintendoSwitch2Custom,
      (_SettingsProvider.playStation4, true) =>
        SettingsFolderTarget.playStation4Custom,
      (_SettingsProvider.playStation5, true) =>
        SettingsFolderTarget.playStation5Custom,
      (_SettingsProvider.steam, true) => SettingsFolderTarget.steamCustom,
      (_SettingsProvider.steam, false) => SettingsFolderTarget.steamAutomatic,
      _ => null,
    };
    if (target == null || _providerAccessReady(provider)) {
      await _enableProviderIfValid(provider);
      return;
    }

    if (_isAutomaticTarget(target)) {
      await _chooseAutomaticDirectory(target);
    } else {
      await _chooseDirectory(target, initialPath: _providerPath(provider));
    }
    if (mounted && _providerAccessReady(provider)) {
      await _enableProviderIfValid(provider);
    }
  }

  Future<void> _enableProviderIfValid(_SettingsProvider provider) async {
    final draft = _settingsWithProviderEnabled(
      _draftSettings(),
      provider,
      true,
    );

    final pathErrors = await _validatePaths(draft);
    if (!mounted) {
      return;
    }
    _showPathErrors(pathErrors);
    final pathError = pathErrors.forProvider(provider);
    final configurationError = pathError == null
        ? await widget.controller.providerConfigurationError(
            _providerName(provider),
            draft,
          )
        : null;
    if (!mounted) {
      return;
    }
    final error = pathError ?? configurationError;
    if (error != null) {
      setState(() {
        _setProviderEnabledValue(provider, false);
        _expandedProvider = provider;
        _providerActivationErrors[provider] = error;
      });
      _scheduleAutosave(immediate: true);
      return;
    }

    setState(() {
      _setProviderEnabledValue(provider, true);
      _providerActivationErrors.remove(provider);
    });
    _scheduleAutosave(immediate: true);
  }

  bool _providerEnabled(_SettingsProvider provider) => switch (provider) {
    _SettingsProvider.battleNet => _diabloEnabled,
    _SettingsProvider.guildWars2 => _guildWars2Enabled,
    _SettingsProvider.hytale => _hytaleEnabled,
    _SettingsProvider.minecraft => _minecraftEnabled,
    _SettingsProvider.nintendoSwitch2 => _nintendoSwitch2Enabled,
    _SettingsProvider.playStation4 => _playStation4Enabled,
    _SettingsProvider.playStation5 => _playStation5Enabled,
    _SettingsProvider.steam => _steamEnabled,
  };

  String _providerName(_SettingsProvider provider) => switch (provider) {
    _SettingsProvider.battleNet => 'Battle.net',
    _SettingsProvider.guildWars2 => 'Guild Wars 2',
    _SettingsProvider.hytale => 'Hytale',
    _SettingsProvider.minecraft => 'Minecraft',
    _SettingsProvider.nintendoSwitch2 => 'Nintendo Switch 2',
    _SettingsProvider.playStation4 => 'PlayStation 4',
    _SettingsProvider.playStation5 => 'PlayStation 5',
    _SettingsProvider.steam => 'Steam',
  };

  _SettingsProvider? _providerForFolderTarget(
    SettingsFolderTarget target,
  ) => switch (target) {
    SettingsFolderTarget.library => null,
    SettingsFolderTarget.battleNetGameCustom ||
    SettingsFolderTarget.battleNetGameAutomatic => _SettingsProvider.battleNet,
    SettingsFolderTarget.guildWars2Custom => _SettingsProvider.guildWars2,
    SettingsFolderTarget.hytaleCustom ||
    SettingsFolderTarget.hytaleAutomatic => _SettingsProvider.hytale,
    SettingsFolderTarget.minecraftCustom ||
    SettingsFolderTarget.minecraftAutomatic => _SettingsProvider.minecraft,
    SettingsFolderTarget.nintendoSwitch2Custom =>
      _SettingsProvider.nintendoSwitch2,
    SettingsFolderTarget.playStation4Custom => _SettingsProvider.playStation4,
    SettingsFolderTarget.playStation5Custom => _SettingsProvider.playStation5,
    SettingsFolderTarget.steamCustom ||
    SettingsFolderTarget.steamAutomatic => _SettingsProvider.steam,
  };

  AppSettings _settingsWithProviderEnabled(
    AppSettings settings,
    _SettingsProvider provider,
    bool enabled,
  ) => switch (provider) {
    _SettingsProvider.battleNet => settings.copyWith(
      battleNet: settings.battleNet.copyWith(enabled: enabled),
    ),
    _SettingsProvider.guildWars2 => settings.copyWith(
      guildWars2: settings.guildWars2.copyWith(enabled: enabled),
    ),
    _SettingsProvider.hytale => settings.copyWith(
      hytale: settings.hytale.copyWith(enabled: enabled),
    ),
    _SettingsProvider.minecraft => settings.copyWith(
      minecraft: settings.minecraft.copyWith(enabled: enabled),
    ),
    _SettingsProvider.nintendoSwitch2 => settings.copyWith(
      nintendoSwitch2: settings.nintendoSwitch2.copyWith(enabled: enabled),
    ),
    _SettingsProvider.playStation4 => settings.copyWith(
      playStation4: settings.playStation4.copyWith(enabled: enabled),
    ),
    _SettingsProvider.playStation5 => settings.copyWith(
      playStation5: settings.playStation5.copyWith(enabled: enabled),
    ),
    _SettingsProvider.steam => settings.copyWith(
      steam: settings.steam.copyWith(enabled: enabled),
    ),
  };

  Future<void> _setCustomPath(_SettingsProvider provider, bool value) async {
    if (!widget.controller.usesPersistentFolderAccess) {
      setState(() {
        _setUseCustomPathValue(provider, value);
        if (!value) {
          _setProviderPathError(provider, null);
        }
      });
      _scheduleAutosave(immediate: true);
      return;
    }

    final target = value
        ? switch (provider) {
            _SettingsProvider.battleNet => null,
            _SettingsProvider.guildWars2 =>
              SettingsFolderTarget.guildWars2Custom,
            _SettingsProvider.hytale => SettingsFolderTarget.hytaleCustom,
            _SettingsProvider.minecraft => SettingsFolderTarget.minecraftCustom,
            _SettingsProvider.nintendoSwitch2 =>
              SettingsFolderTarget.nintendoSwitch2Custom,
            _SettingsProvider.playStation4 =>
              SettingsFolderTarget.playStation4Custom,
            _SettingsProvider.playStation5 =>
              SettingsFolderTarget.playStation5Custom,
            _SettingsProvider.steam => SettingsFolderTarget.steamCustom,
          }
        : switch (provider) {
            _SettingsProvider.battleNet => null,
            _SettingsProvider.hytale => SettingsFolderTarget.hytaleAutomatic,
            _SettingsProvider.minecraft =>
              SettingsFolderTarget.minecraftAutomatic,
            _SettingsProvider.steam => SettingsFolderTarget.steamAutomatic,
            _ => null,
          };
    if (target != null) {
      if (_isAutomaticTarget(target)) {
        await _chooseAutomaticDirectory(target);
      } else {
        await _chooseDirectory(target, initialPath: _providerPath(provider));
      }
      return;
    }

    setState(() {
      _setUseCustomPathValue(provider, false);
      _setProviderPathError(provider, null);
    });
    _scheduleAutosave(immediate: true);
  }

  Future<void> _flushPendingChanges() async {
    _saveTimer?.cancel();
    if (_hasPendingChanges) {
      final revision = ++_draftRevision;
      await _validateAndSave(_draftSettings(), revision: revision);
    }
    await _saveQueue;
  }

  bool _usesCustomPath(_SettingsProvider provider) => switch (provider) {
    _SettingsProvider.battleNet => false,
    _SettingsProvider.guildWars2 => _guildWars2UseCustomPath,
    _SettingsProvider.hytale => _hytaleUseCustomPath,
    _SettingsProvider.minecraft => _minecraftUseCustomPath,
    _SettingsProvider.nintendoSwitch2 => _nintendoSwitch2UseCustomPath,
    _SettingsProvider.playStation4 => true,
    _SettingsProvider.playStation5 => true,
    _SettingsProvider.steam => _steamUseCustomPath,
  };

  String _providerPath(_SettingsProvider provider) => switch (provider) {
    _SettingsProvider.battleNet => '',
    _SettingsProvider.guildWars2 => _guildWars2Controller.text,
    _SettingsProvider.hytale => _hytaleController.text,
    _SettingsProvider.minecraft => _minecraftController.text,
    _SettingsProvider.nintendoSwitch2 => _nintendoSwitch2Controller.text,
    _SettingsProvider.playStation4 => _playStation4Controller.text,
    _SettingsProvider.playStation5 => _playStation5Controller.text,
    _SettingsProvider.steam => _steamPathController.text,
  };

  bool _providerAccessReady(_SettingsProvider provider) {
    final id = switch (provider) {
      _SettingsProvider.battleNet => FolderGrantIds.battleNet,
      _SettingsProvider.guildWars2 => FolderGrantIds.guildWars2,
      _SettingsProvider.hytale => FolderGrantIds.hytale,
      _SettingsProvider.minecraft => FolderGrantIds.minecraft,
      _SettingsProvider.nintendoSwitch2 => FolderGrantIds.nintendoSwitch2,
      _SettingsProvider.playStation4 => FolderGrantIds.playStation4,
      _SettingsProvider.playStation5 => FolderGrantIds.playStation5,
      _SettingsProvider.steam => FolderGrantIds.steam,
    };
    return widget.controller.folderAuthorization(id).isReady;
  }

  void _setProviderEnabledValue(_SettingsProvider provider, bool value) {
    switch (provider) {
      case _SettingsProvider.battleNet:
        _diabloEnabled = value;
        break;
      case _SettingsProvider.guildWars2:
        _guildWars2Enabled = value;
        break;
      case _SettingsProvider.hytale:
        _hytaleEnabled = value;
        break;
      case _SettingsProvider.minecraft:
        _minecraftEnabled = value;
        break;
      case _SettingsProvider.nintendoSwitch2:
        _nintendoSwitch2Enabled = value;
        break;
      case _SettingsProvider.playStation4:
        _playStation4Enabled = value;
        break;
      case _SettingsProvider.playStation5:
        _playStation5Enabled = value;
        break;
      case _SettingsProvider.steam:
        _steamEnabled = value;
        break;
    }
  }

  void _setUseCustomPathValue(_SettingsProvider provider, bool value) {
    switch (provider) {
      case _SettingsProvider.battleNet:
        // Battle.net has no provider-level custom folder; each game has one.
        break;
      case _SettingsProvider.guildWars2:
        _guildWars2UseCustomPath = value;
        break;
      case _SettingsProvider.hytale:
        _hytaleUseCustomPath = value;
        break;
      case _SettingsProvider.minecraft:
        _minecraftUseCustomPath = value;
        break;
      case _SettingsProvider.nintendoSwitch2:
        _nintendoSwitch2UseCustomPath = value;
        break;
      case _SettingsProvider.playStation4:
      case _SettingsProvider.playStation5:
        break;
      case _SettingsProvider.steam:
        _steamUseCustomPath = value;
        break;
    }
  }

  void _setProviderPathError(_SettingsProvider provider, String? value) {
    switch (provider) {
      case _SettingsProvider.battleNet:
        _diabloPathError = value;
        break;
      case _SettingsProvider.guildWars2:
        _guildWars2PathError = value;
        break;
      case _SettingsProvider.hytale:
        _hytalePathError = value;
        break;
      case _SettingsProvider.minecraft:
        _minecraftPathError = value;
        break;
      case _SettingsProvider.nintendoSwitch2:
        _nintendoSwitch2PathError = value;
        break;
      case _SettingsProvider.playStation4:
        _playStation4PathError = value;
        break;
      case _SettingsProvider.playStation5:
        _playStation5PathError = value;
        break;
      case _SettingsProvider.steam:
        _steamPathError = value;
        break;
    }
  }

  void _setFolderError(SettingsFolderTarget target, String? value) {
    switch (target) {
      case SettingsFolderTarget.library:
        _outputPathError = value;
        break;
      case SettingsFolderTarget.battleNetGameCustom:
      case SettingsFolderTarget.battleNetGameAutomatic:
        _diabloPathError = value;
        break;
      case SettingsFolderTarget.guildWars2Custom:
        _guildWars2PathError = value;
        break;
      case SettingsFolderTarget.hytaleCustom:
      case SettingsFolderTarget.hytaleAutomatic:
        _hytalePathError = value;
        break;
      case SettingsFolderTarget.minecraftCustom:
      case SettingsFolderTarget.minecraftAutomatic:
        _minecraftPathError = value;
        break;
      case SettingsFolderTarget.nintendoSwitch2Custom:
        _nintendoSwitch2PathError = value;
        break;
      case SettingsFolderTarget.playStation4Custom:
        _playStation4PathError = value;
        break;
      case SettingsFolderTarget.playStation5Custom:
        _playStation5PathError = value;
        break;
      case SettingsFolderTarget.steamCustom:
      case SettingsFolderTarget.steamAutomatic:
        _steamPathError = value;
        break;
    }
  }

  String _folderButtonLabel(String id) {
    if (!widget.controller.usesPersistentFolderAccess) {
      return 'Choose';
    }
    final status = widget.controller.folderAuthorization(id).status;
    return status == FolderAuthorizationStatus.ready
        ? 'Change'
        : 'Allow Access';
  }

  bool _isAutomaticTarget(SettingsFolderTarget target) {
    return target == SettingsFolderTarget.battleNetGameAutomatic ||
        target == SettingsFolderTarget.hytaleAutomatic ||
        target == SettingsFolderTarget.minecraftAutomatic ||
        target == SettingsFolderTarget.steamAutomatic;
  }

  String _automaticProviderName(SettingsFolderTarget target) {
    return switch (target) {
      SettingsFolderTarget.battleNetGameAutomatic => 'Battle.net',
      SettingsFolderTarget.hytaleAutomatic => 'Hytale',
      SettingsFolderTarget.minecraftAutomatic => 'Minecraft',
      SettingsFolderTarget.steamAutomatic => 'Steam',
      _ => 'automatic',
    };
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
      battleNet: BattleNetSettings(
        enabled: _diabloEnabled,
        games: {
          for (final game in battleNetGames)
            game.id: ProviderSettings(
              enabled: _battleNetGameOn(game.id),
              useCustomPath: _battleNetGameCustom(game.id),
              sourcePath: _battleNetControllerFor(game.id).text.trim(),
            ),
        },
      ),
      guildWars2: ProviderSettings(
        enabled: _guildWars2Enabled,
        useCustomPath: _guildWars2UseCustomPath,
        sourcePath: _guildWars2Controller.text.trim(),
      ),
      hytale: ProviderSettings(
        enabled: _hytaleEnabled,
        useCustomPath: _hytaleUseCustomPath,
        sourcePath: _hytaleController.text.trim(),
        downloadCovers: _hytaleDownloadCovers,
      ),
      minecraft: ProviderSettings(
        enabled: _minecraftEnabled,
        useCustomPath: _minecraftUseCustomPath,
        sourcePath: _minecraftController.text.trim(),
      ),
      nintendoSwitch2: NintendoSwitch2Settings(
        enabled: _nintendoSwitch2Enabled,
        useCustomPath: _nintendoSwitch2UseCustomPath,
        sourcePath: _nintendoSwitch2Controller.text.trim(),
        ignoredFolders: List.unmodifiable(_nintendoSwitch2IgnoredFolders),
      ),
      playStation4: ProviderSettings(
        enabled: _playStation4Enabled,
        useCustomPath: true,
        sourcePath: _playStation4Controller.text.trim(),
      ),
      playStation5: ProviderSettings(
        enabled: _playStation5Enabled,
        useCustomPath: true,
        sourcePath: _playStation5Controller.text.trim(),
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
      folderGrants: widget.controller.settings.folderGrants,
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
    final providerErrors = <String, String>{
      if (draft.battleNet.enabled && errors.battleNet != null)
        'Battle.net': errors.battleNet!,
      if (draft.guildWars2.enabled && errors.guildWars2 != null)
        'Guild Wars 2': errors.guildWars2!,
      if (draft.hytale.enabled && errors.hytale != null)
        'Hytale': errors.hytale!,
      if (draft.minecraft.enabled && errors.minecraft != null)
        'Minecraft': errors.minecraft!,
      if (draft.nintendoSwitch2.enabled && errors.nintendoSwitch2 != null)
        'Nintendo Switch 2': errors.nintendoSwitch2!,
      if (draft.playStation4.enabled && errors.playStation4 != null)
        'PlayStation 4': errors.playStation4!,
      if (draft.playStation5.enabled && errors.playStation5 != null)
        'PlayStation 5': errors.playStation5!,
      if (draft.steam.enabled && errors.steam != null) 'Steam': errors.steam!,
    };
    final safeSettings = AppSettings(
      outputPath: errors.outputPath == null
          ? draft.outputPath
          : saved.outputPath,
      themeMode: draft.themeMode,
      battleNet: _safeBattleNet(draft.battleNet, saved.battleNet),
      guildWars2: errors.guildWars2 == null
          ? draft.guildWars2
          : saved.guildWars2.copyWith(enabled: draft.guildWars2.enabled),
      hytale: errors.hytale == null
          ? draft.hytale
          : saved.hytale.copyWith(
              enabled: draft.hytale.enabled,
              downloadCovers: draft.hytale.downloadCovers,
            ),
      minecraft: errors.minecraft == null
          ? draft.minecraft
          : saved.minecraft.copyWith(enabled: draft.minecraft.enabled),
      nintendoSwitch2: errors.nintendoSwitch2 == null
          ? draft.nintendoSwitch2
          : saved.nintendoSwitch2.copyWith(
              enabled: draft.nintendoSwitch2.enabled,
              ignoredFolders: draft.nintendoSwitch2.ignoredFolders,
            ),
      playStation4: errors.playStation4 == null
          ? draft.playStation4
          : saved.playStation4.copyWith(enabled: draft.playStation4.enabled),
      playStation5: errors.playStation5 == null
          ? draft.playStation5
          : saved.playStation5.copyWith(enabled: draft.playStation5.enabled),
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
      folderGrants: saved.folderGrants,
    );

    _saveQueue = _saveQueue.then((_) async {
      await widget.controller.updateSettings(
        safeSettings,
        providerErrors: providerErrors,
      );
    });
    await _saveQueue;
    if (mounted) {
      final saved = widget.controller.settings;
      final validationErrors = widget.controller.providerValidationErrors;
      setState(() {
        _diabloEnabled = saved.battleNet.enabled;
        _guildWars2Enabled = saved.guildWars2.enabled;
        _hytaleEnabled = saved.hytale.enabled;
        _minecraftEnabled = saved.minecraft.enabled;
        _nintendoSwitch2Enabled = saved.nintendoSwitch2.enabled;
        _playStation4Enabled = saved.playStation4.enabled;
        _playStation5Enabled = saved.playStation5.enabled;
        _steamEnabled = saved.steam.enabled;
        for (final provider in _SettingsProvider.values) {
          final error = validationErrors[_providerName(provider)];
          if (error != null) {
            _providerActivationErrors[provider] = error;
          } else if (_providerEnabled(provider)) {
            _providerActivationErrors.remove(provider);
          }
        }
        if (validationErrors.isNotEmpty) {
          _expandedProvider = _SettingsProvider.values.firstWhere(
            (provider) => validationErrors.containsKey(_providerName(provider)),
          );
        }
      });
    }
  }

  Future<_PathErrors> _validatePaths(AppSettings draft) async {
    final results = await Future.wait<String?>([
      _directoryError(
        draft.outputPath,
        label: 'Library folder',
        allowEmpty: true,
        grantId: FolderGrantIds.library,
      ),
      _battleNetError(draft),
      draft.guildWars2.useCustomPath
          ? _directoryError(
              draft.guildWars2.sourcePath,
              label: 'Guild Wars 2 screenshot folder',
              grantId: FolderGrantIds.guildWars2,
            )
          : Future.value(),
      draft.hytale.useCustomPath
          ? _directoryError(
              draft.hytale.sourcePath,
              label: 'Hytale screenshot folder',
              grantId: FolderGrantIds.hytale,
            )
          : draft.hytale.enabled && widget.controller.usesPersistentFolderAccess
          ? Future.value(
              _folderAuthorizationError(
                FolderGrantIds.hytale,
                label: 'Hytale screenshot folder',
                needsAuthorizationMessage: 'Hytale screenshots are stored in “Pictures/Hytale Screenshots”. Click Allow Access to grant access to that folder.',
              ),
            )
          : Future.value(),
      draft.minecraft.useCustomPath
          ? _directoryError(
              draft.minecraft.sourcePath,
              label: 'Minecraft screenshot folder',
              grantId: FolderGrantIds.minecraft,
            )
          : draft.minecraft.enabled &&
                widget.controller.usesPersistentFolderAccess
          ? Future.value(
              _folderAuthorizationError(
                FolderGrantIds.minecraft,
                label: 'Minecraft screenshot folder',
                needsAuthorizationMessage: 'Minecraft screenshots are stored in the launcher screenshots folder. Click Allow Access to grant access to that folder.',
              ),
            )
          : Future.value(),
      draft.nintendoSwitch2.useCustomPath
          ? _directoryError(
              draft.nintendoSwitch2.sourcePath,
              label: 'Copied Nintendo Switch 2 album folder',
              grantId: FolderGrantIds.nintendoSwitch2,
            )
          : Future.value(),
      draft.playStation4.enabled
          ? _directoryError(
              draft.playStation4.sourcePath,
              label: 'PlayStation 4 exported media folder',
              grantId: FolderGrantIds.playStation4,
            )
          : Future.value(),
      draft.playStation5.enabled
          ? _directoryError(
              draft.playStation5.sourcePath,
              label: 'PlayStation 5 exported media folder',
              grantId: FolderGrantIds.playStation5,
            )
          : Future.value(),
      draft.steam.useCustomPath
          ? _directoryError(
              draft.steam.userdataPath,
              label: 'Steam folder',
              grantId: FolderGrantIds.steam,
            )
          : draft.steam.enabled && widget.controller.usesPersistentFolderAccess
          ? Future.value(
              _folderAuthorizationError(
                FolderGrantIds.steam,
                label: 'Steam screenshot folder',
                needsAuthorizationMessage: 'Steam screenshots are stored in its “userdata” folder. The macOS dialog will open Steam; click Allow Access to grant access to that folder.',
              ),
            )
          : Future.value(),
    ]);

    return _PathErrors(
      outputPath: results[0],
      battleNet: results[1],
      guildWars2: results[2],
      hytale: results[3],
      minecraft: results[4],
      nintendoSwitch2: results[5],
      playStation4: results[6],
      playStation5: results[7],
      steam: results[8],
    );
  }

  Future<String?> _directoryError(
    String path, {
    required String label,
    bool allowEmpty = false,
    String? grantId,
  }) async {
    final value = path.trim();
    if (value.isEmpty) {
      return allowEmpty ? null : 'Choose a folder.';
    }

    if (widget.controller.usesPersistentFolderAccess && grantId != null) {
      return _folderAuthorizationError(grantId, label: label);
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

  /// Keeps the draft, except for the games whose own folder failed to
  /// validate. Reverting the whole provider would throw away edits to games
  /// that are perfectly fine — turning one off, for instance.
  BattleNetSettings _safeBattleNet(
    BattleNetSettings draft,
    BattleNetSettings saved,
  ) {
    if (_battleNetGameErrors.isEmpty) {
      return draft;
    }
    return draft.copyWith(
      games: {
        for (final entry in draft.games.entries)
          entry.key: _battleNetGameErrors.containsKey(entry.key)
              ? saved.game(entry.key)
              : entry.value,
      },
    );
  }

  /// Validates every Battle.net game and records each game's own error, so a
  /// misconfigured game says so on its own row.
  ///
  /// The provider-level error is deliberately quiet about games that are
  /// simply not installed: a game nobody owns is skipped, not broken.
  Future<String?> _battleNetError(AppSettings draft) async {
    _battleNetGameErrors.clear();
    if (!draft.battleNet.enabled) {
      return null;
    }

    final folders = widget.controller.battleNetGameFolders(draft);
    var configured = 0;
    for (final folder in folders) {
      final game = draft.battleNet.game(folder.game.id);
      if (!game.enabled) {
        continue;
      }
      if (game.useCustomPath) {
        final error = await _directoryError(
          game.sourcePath,
          label: '${folder.game.name} screenshot folder',
          grantId: BattleNetProvider.grantIdForGame(folder.game.id),
        );
        if (error != null) {
          _battleNetGameErrors[folder.game.id] = error;
          continue;
        }
        configured++;
        continue;
      }
      if (!folder.exists) {
        continue;
      }
      if (widget.controller.usesPersistentFolderAccess) {
        final error = _folderAuthorizationError(
          BattleNetProvider.grantIdForGame(folder.game.id),
          label: '${folder.game.name} screenshot folder',
          needsAuthorizationMessage:
              'Click Allow Access to let Gaming Memories read ${folder.game.name} screenshots.',
        );
        if (error != null) {
          _battleNetGameErrors[folder.game.id] = error;
          continue;
        }
      }
      configured++;
    }

    if (_battleNetGameErrors.isEmpty) {
      return configured == 0
          ? 'No Battle.net games were found. Turn on a game and choose its folder.'
          : null;
    }
    return _battleNetGameErrors.length == 1
        ? _battleNetGameErrors.values.single
        : '${_battleNetGameErrors.length} Battle.net games need attention.';
  }

  String? _folderAuthorizationError(
    String id, {
    required String label,
    String? needsAuthorizationMessage,
  }) {
    return switch (widget.controller.folderAuthorization(id).status) {
      FolderAuthorizationStatus.ready ||
      FolderAuthorizationStatus.notRequired => null,
      FolderAuthorizationStatus.needsAuthorization =>
        needsAuthorizationMessage ?? 'Allow access to the $label.',
      FolderAuthorizationStatus.unavailable =>
        'The $label is unavailable. Choose it again.',
    };
  }

  void _showPathErrors(_PathErrors errors) {
    setState(() {
      _outputPathError = errors.outputPath;
      _diabloPathError = errors.battleNet;
      _guildWars2PathError = errors.guildWars2;
      _hytalePathError = errors.hytale;
      _minecraftPathError = errors.minecraft;
      _nintendoSwitch2PathError = errors.nintendoSwitch2;
      _playStation4PathError = errors.playStation4;
      _playStation5PathError = errors.playStation5;
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

  void _addNintendoSwitch2IgnoredFolder() {
    final folder = _nintendoSwitch2IgnoredInputController.text.trim();
    if (folder.isEmpty || _nintendoSwitch2IgnoredFolders.contains(folder)) {
      return;
    }

    setState(() {
      _nintendoSwitch2IgnoredFolders.add(folder);
      _nintendoSwitch2IgnoredInputController.clear();
    });
    _scheduleAutosave();
  }

  void _removeNintendoSwitch2IgnoredFolder(String folder) {
    setState(() => _nintendoSwitch2IgnoredFolders.remove(folder));
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
    required this.battleNet,
    required this.guildWars2,
    required this.hytale,
    required this.minecraft,
    required this.nintendoSwitch2,
    required this.playStation4,
    required this.playStation5,
    required this.steam,
  });

  final String? outputPath;
  final String? battleNet;
  final String? guildWars2;
  final String? hytale;
  final String? minecraft;
  final String? nintendoSwitch2;
  final String? playStation4;
  final String? playStation5;
  final String? steam;

  String? forProvider(_SettingsProvider provider) => switch (provider) {
    _SettingsProvider.battleNet => battleNet,
    _SettingsProvider.guildWars2 => guildWars2,
    _SettingsProvider.hytale => hytale,
    _SettingsProvider.minecraft => minecraft,
    _SettingsProvider.nintendoSwitch2 => nintendoSwitch2,
    _SettingsProvider.playStation4 => playStation4,
    _SettingsProvider.playStation5 => playStation5,
    _SettingsProvider.steam => steam,
  };
}

enum _SettingsProvider {
  battleNet,
  guildWars2,
  hytale,
  minecraft,
  nintendoSwitch2,
  playStation4,
  playStation5,
  steam,
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

class _IgnoredFoldersList extends StatelessWidget {
  const _IgnoredFoldersList({
    required this.folders,
    required this.enabled,
    required this.onRemove,
  });

  final List<String> folders;
  final bool enabled;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return Text(
        'No ignored album folders.',
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
          for (var index = 0; index < folders.length; index++) ...[
            if (index > 0)
              Divider(height: 1, color: context.theme.colors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      folders[index],
                      style: context.theme.typography.body.sm,
                    ),
                  ),
                  FButton.icon(
                    key: ValueKey(
                      'nintendo-switch-2-ignored-remove-${folders[index]}',
                    ),
                    variant: FButtonVariant.ghost,
                    size: FButtonSizeVariant.sm,
                    semanticsLabel:
                        'Remove ignored album folder ${folders[index]}',
                    onPress: enabled ? () => onRemove(folders[index]) : null,
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

class _SettingsSections extends StatelessWidget {
  const _SettingsSections({
    required this.sortProviders,
    required this.crossAxisAlignment,
    required this.children,
  });

  final bool sortProviders;
  final CrossAxisAlignment crossAxisAlignment;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!sortProviders) {
      return Column(crossAxisAlignment: crossAxisAlignment, children: children);
    }

    final providers =
        children
            .map((child) => (name: _providerName(child), child: child))
            .where((entry) => entry.name != null)
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.name!.toLowerCase().compareTo(right.name!.toLowerCase()),
          );
    if (providers.isEmpty) {
      return Column(crossAxisAlignment: crossAxisAlignment, children: children);
    }

    final firstProvider = children.indexWhere(
      (child) => _providerName(child) != null,
    );
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        ...children.take(firstProvider),
        for (var index = 0; index < providers.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          providers[index].child,
        ],
      ],
    );
  }

  String? _providerName(Widget child) {
    if (child case _PlayStationProviderCard card) {
      return card.name;
    }
    final key = child.key;
    if (key case ValueKey<String> valueKey) {
      const prefix = 'provider-sort-';
      if (valueKey.value.startsWith(prefix)) {
        return valueKey.value.substring(prefix.length);
      }
    }
    return null;
  }
}

class _PlayStationProviderCard extends StatelessWidget {
  const _PlayStationProviderCard({
    required this.headerKey,
    required this.name,
    required this.description,
    required this.fieldKey,
    required this.switchKey,
    required this.controller,
    required this.expanded,
    required this.enabled,
    required this.activationError,
    required this.error,
    required this.readOnly,
    required this.buttonLabel,
    required this.requirement,
    required this.onTap,
    required this.onEnabled,
    required this.onBrowse,
  });

  final Key headerKey;
  final String name;
  final String description;
  final Key fieldKey;
  final Key switchKey;
  final TextEditingController controller;
  final bool expanded;
  final bool enabled;
  final String? activationError;
  final String? error;
  final bool readOnly;
  final String buttonLabel;
  final String requirement;
  final VoidCallback onTap;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProviderHeader(
              headerKey: headerKey,
              switchKey: switchKey,
              name: name,
              description: description,
              expanded: expanded,
              enabled: enabled,
              error: activationError,
              onTap: onTap,
              onEnabled: onEnabled,
            ),
            if (expanded) ...[
              const SizedBox(height: 18),
              _DirectoryField(
                fieldKey: fieldKey,
                controller: controller,
                label: 'Exported media folder',
                hint: '/path/to/$name/Captures',
                error: error,
                readOnly: readOnly,
                buttonLabel: buttonLabel,
                onBrowse: onBrowse,
              ),
              const SizedBox(height: 10),
              Text(
                'Select the folder copied from your console. $requirement',
                style: context.theme.typography.body.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProviderHeader extends StatelessWidget {
  const _ProviderHeader({
    required this.headerKey,
    required this.name,
    required this.description,
    required this.expanded,
    required this.enabled,
    required this.onTap,
    required this.onEnabled,
    this.error,
    this.switchKey,
  });

  final Key headerKey;
  final Key? switchKey;
  final String name;
  final String description;
  final bool expanded;
  final bool enabled;
  final String? error;
  final VoidCallback onTap;
  final ValueChanged<bool> onEnabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: headerKey,
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Row(
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
                          name,
                          style: context.theme.typography.body.lg.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: context.theme.typography.body.sm.copyWith(
                            color: context.theme.colors.mutedForeground,
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            error!,
                            style: context.theme.typography.body.xs.copyWith(
                              color: context.theme.colors.destructive,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? FLucideIcons.chevronUp
                        : FLucideIcons.chevronDown,
                    size: 18,
                    color: context.theme.colors.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FSwitch(
          key: switchKey,
          value: enabled,
          semanticsLabel: 'Enable $name',
          onChange: onEnabled,
        ),
      ],
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
    this.switchKey,
  });

  final String label;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChange;
  final Key? switchKey;

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
          key: switchKey,
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
    this.readOnly = false,
    this.buttonLabel = 'Browse',
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback onBrowse;
  final String? error;
  final bool readOnly;
  final String buttonLabel;

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
                readOnly: readOnly,
              ),
            ),
            const SizedBox(width: 10),
            FButton(
              variant: FButtonVariant.outline,
              mainAxisSize: MainAxisSize.min,
              onPress: onBrowse,
              child: Text(buttonLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlinePathError extends StatelessWidget {
  const _InlinePathError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: context.theme.typography.body.sm.copyWith(
        color: context.theme.colors.destructive,
      ),
    );
  }
}

/// One Battle.net game: its switch, whether its folder was found, macOS
/// access, and an optional custom folder.
class _BattleNetGameRow extends StatelessWidget {
  const _BattleNetGameRow({
    required this.folder,
    required this.enabled,
    required this.useCustomPath,
    required this.controller,
    required this.usesPersistentFolderAccess,
    required this.access,
    required this.folderButtonLabel,
    required this.onEnabled,
    required this.onUseCustomPath,
    required this.onBrowse,
    required this.onAllow,
    this.error,
  });

  final BattleNetGameFolder folder;
  final bool enabled;
  final bool useCustomPath;
  final TextEditingController controller;
  final bool usesPersistentFolderAccess;
  final FolderAuthorization access;
  final String folderButtonLabel;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<bool> onUseCustomPath;
  final VoidCallback onBrowse;
  final VoidCallback onAllow;
  final String? error;

  bool get _hasDefaultPath => folder.path != null && !folder.isCustom;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final found = folder.exists;

    return Column(
      key: ValueKey('battle-net-game-${folder.game.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              found ? FLucideIcons.circleCheck : FLucideIcons.circleDashed,
              size: 18,
              color: found ? colors.primary : colors.mutedForeground,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(folder.game.name, style: typography.body.lg),
                  const SizedBox(height: 2),
                  Text(
                    _statusLine(),
                    style: typography.body.sm.copyWith(
                      color: error == null
                          ? colors.mutedForeground
                          : colors.destructive,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FSwitch(
              key: ValueKey('battle-net-game-${folder.game.id}-enabled'),
              value: enabled,
              onChange: onEnabled,
            ),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FCheckbox(
                  key: ValueKey('battle-net-game-${folder.game.id}-custom'),
                  label: const Text('Use custom folder'),
                  value: useCustomPath,
                  enabled: true,
                  onChange: onUseCustomPath,
                ),
                if (useCustomPath) ...[
                  const SizedBox(height: 10),
                  _DirectoryField(
                    fieldKey: ValueKey(
                      'battle-net-game-${folder.game.id}-path',
                    ),
                    controller: controller,
                    label: '${folder.game.name} screenshot folder',
                    hint: '/path/to/screenshots',
                    error: error,
                    readOnly: usesPersistentFolderAccess,
                    buttonLabel: folderButtonLabel,
                    onBrowse: onBrowse,
                  ),
                ] else if (usesPersistentFolderAccess && found) ...[
                  const SizedBox(height: 10),
                  _FolderAccessRow(
                    buttonKey: ValueKey(
                      'battle-net-game-${folder.game.id}-access',
                    ),
                    providerName: folder.game.name,
                    automaticDescription:
                        'Click Allow Access to let Gaming Memories read “${folder.path}”.',
                    status: access,
                    error: error,
                    onAllow: onAllow,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _statusLine() {
    if (error != null) {
      return error!;
    }
    if (folder.isCustom) {
      return folder.exists
          ? 'Custom folder: ${folder.path}'
          : 'Custom folder not found: ${folder.path}';
    }
    if (!_hasDefaultPath) {
      return 'No default folder on this platform. Choose one to import it.';
    }
    return folder.exists
        ? 'Found in ${folder.path}'
        : 'Not found in ${folder.path}';
  }
}

class _FolderAccessRow extends StatelessWidget {
  const _FolderAccessRow({
    required this.buttonKey,
    required this.providerName,
    required this.automaticDescription,
    required this.status,
    required this.onAllow,
    this.error,
  });

  final Key buttonKey;
  final String providerName;
  final String automaticDescription;
  final FolderAuthorization status;
  final VoidCallback onAllow;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final ready = status.status == FolderAuthorizationStatus.ready;
    final unavailable = status.status == FolderAuthorizationStatus.unavailable;
    final message =
        error ??
        (ready
            ? 'Access allowed to the automatically discovered $providerName folder.'
            : unavailable
            ? 'The $providerName folder is unavailable. Choose it again.'
            : automaticDescription);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          ready ? FLucideIcons.circleCheck : FLucideIcons.triangleAlert,
          size: 18,
          color: ready
              ? context.theme.colors.primary
              : context.theme.colors.destructive,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: context.theme.typography.body.sm.copyWith(
              color: error == null && ready
                  ? context.theme.colors.mutedForeground
                  : context.theme.colors.destructive,
            ),
          ),
        ),
        const SizedBox(width: 10),
        FButton(
          key: buttonKey,
          variant: FButtonVariant.outline,
          mainAxisSize: MainAxisSize.min,
          onPress: onAllow,
          child: Text(ready ? 'Change' : 'Allow Access'),
        ),
      ],
    );
  }
}
