import 'dart:async';
import 'dart:io';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../models/app_settings.dart';
import '../services/battle_net_games.dart';
import '../services/folder_access_service.dart';
import '../services/library_scanner.dart';
import '../sources/battle_net_source.dart';

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
  _SettingsSource? _expandedSource;
  final _sourceActivationErrors = <_SettingsSource, String>{};
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
      // source. On macOS picking the folder is also how the grant is made,
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
    for (final source in _SettingsSource.values) {
      final error = widget.controller.sourceValidationError(
        _sourceName(source),
      );
      if (error != null) {
        _sourceActivationErrors[source] = error;
      }
    }
    if (_sourceActivationErrors.isNotEmpty) {
      _expandedSource = _sourceActivationErrors.keys.first;
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
            sortSources: _settingsTab == 2,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Library and source setup',
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
                      'Sources',
                      key: ValueKey('settings-tab-sources'),
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
                  key: const ValueKey('source-sort-Battle.net'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SourceHeader(
                          headerKey: const ValueKey('source-card-battle-net'),
                          switchKey: const ValueKey('battle-net-enabled'),
                          name: 'Battle.net',
                          description: 'PC · Installed Blizzard games',
                          expanded:
                              _expandedSource == _SettingsSource.battleNet,
                          enabled: _diabloEnabled,
                          error:
                              _sourceActivationErrors[_SettingsSource
                                  .battleNet],
                          onTap: () => _toggleSource(_SettingsSource.battleNet),
                          onEnabled: (value) => unawaited(
                            _setSourceEnabled(_SettingsSource.battleNet, value),
                          ),
                        ),
                        if (_expandedSource == _SettingsSource.battleNet) ...[
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
                                BattleNetSource.grantIdForGame(folder.game.id),
                              ),
                              folderButtonLabel: _folderButtonLabel(
                                BattleNetSource.grantIdForGame(folder.game.id),
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
                  key: const ValueKey('source-sort-Hytale'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SourceHeader(
                          headerKey: const ValueKey('source-card-hytale'),
                          switchKey: const ValueKey('hytale-enabled'),
                          name: 'Hytale',
                          description: 'PC · Screenshots',
                          expanded: _expandedSource == _SettingsSource.hytale,
                          enabled: _hytaleEnabled,
                          error:
                              _sourceActivationErrors[_SettingsSource.hytale],
                          onTap: () => _toggleSource(_SettingsSource.hytale),
                          onEnabled: (value) => unawaited(
                            _setSourceEnabled(_SettingsSource.hytale, value),
                          ),
                        ),
                        if (_expandedSource == _SettingsSource.hytale) ...[
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
                              _setCustomPath(_SettingsSource.hytale, value),
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
                              sourceName: 'Hytale',
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
                _PlayStationSourceCard(
                  headerKey: const ValueKey('source-card-playstation-4'),
                  name: 'PlayStation 4',
                  description: 'Screenshots and 30-second clips',
                  fieldKey: const ValueKey('playstation-4-path-field'),
                  switchKey: const ValueKey('playstation-4-enabled'),
                  controller: _playStation4Controller,
                  expanded: _expandedSource == _SettingsSource.playStation4,
                  enabled: _playStation4Enabled,
                  activationError:
                      _sourceActivationErrors[_SettingsSource.playStation4],
                  error: _playStation4PathError,
                  readOnly: widget.controller.usesPersistentFolderAccess,
                  buttonLabel: _playStation4Enabled
                      ? _folderButtonLabel(FolderGrantIds.playStation4)
                      : 'Select Folder',
                  onTap: () => _toggleSource(_SettingsSource.playStation4),
                  onEnabled: (value) => unawaited(
                    _setSourceEnabled(_SettingsSource.playStation4, value),
                  ),
                  onBrowse: () => _chooseDirectory(
                    SettingsFolderTarget.playStation4Custom,
                    initialPath: _playStation4Controller.text,
                  ),
                ),
              if (_settingsTab == 2) const SizedBox(height: 12),
              if (_settingsTab == 2)
                _PlayStationSourceCard(
                  headerKey: const ValueKey('source-card-playstation-5'),
                  name: 'PlayStation 5',
                  description: 'Screenshots and 30-second clips',
                  fieldKey: const ValueKey('playstation-5-path-field'),
                  switchKey: const ValueKey('playstation-5-enabled'),
                  controller: _playStation5Controller,
                  expanded: _expandedSource == _SettingsSource.playStation5,
                  enabled: _playStation5Enabled,
                  activationError:
                      _sourceActivationErrors[_SettingsSource.playStation5],
                  error: _playStation5PathError,
                  readOnly: widget.controller.usesPersistentFolderAccess,
                  buttonLabel: _playStation5Enabled
                      ? _folderButtonLabel(FolderGrantIds.playStation5)
                      : 'Select Folder',
                  requirement: 'FFprobe is optional. Without it, clips use the end time in their filename.',
                  onTap: () => _toggleSource(_SettingsSource.playStation5),
                  onEnabled: (value) => unawaited(
                    _setSourceEnabled(_SettingsSource.playStation5, value),
                  ),
                  onBrowse: () => _chooseDirectory(
                    SettingsFolderTarget.playStation5Custom,
                    initialPath: _playStation5Controller.text,
                  ),
                ),
              if (_settingsTab == 2) const SizedBox(height: 12),
              if (_settingsTab == 2)
                FCard(
                  key: const ValueKey('source-sort-Nintendo Switch 2'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SourceHeader(
                          headerKey: const ValueKey(
                            'source-card-nintendo-switch-2',
                          ),
                          switchKey: const ValueKey(
                            'nintendo-switch-2-enabled',
                          ),
                          name: 'Nintendo Switch 2',
                          description: 'Console · Screenshots and clips',
                          expanded:
                              _expandedSource ==
                              _SettingsSource.nintendoSwitch2,
                          enabled: _nintendoSwitch2Enabled,
                          error:
                              _sourceActivationErrors[_SettingsSource
                                  .nintendoSwitch2],
                          onTap: () =>
                              _toggleSource(_SettingsSource.nintendoSwitch2),
                          onEnabled: (value) => unawaited(
                            _setSourceEnabled(
                              _SettingsSource.nintendoSwitch2,
                              value,
                            ),
                          ),
                        ),
                        if (_expandedSource ==
                            _SettingsSource.nintendoSwitch2) ...[
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
                                _SettingsSource.nintendoSwitch2,
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
                  key: const ValueKey('source-sort-Minecraft'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SourceHeader(
                          headerKey: const ValueKey('source-card-minecraft'),
                          switchKey: const ValueKey('minecraft-enabled'),
                          name: 'Minecraft',
                          description: 'PC · Launcher and Flatpak screenshots',
                          expanded:
                              _expandedSource == _SettingsSource.minecraft,
                          enabled: _minecraftEnabled,
                          error:
                              _sourceActivationErrors[_SettingsSource
                                  .minecraft],
                          onTap: () => _toggleSource(_SettingsSource.minecraft),
                          onEnabled: (value) => unawaited(
                            _setSourceEnabled(_SettingsSource.minecraft, value),
                          ),
                        ),
                        if (_expandedSource == _SettingsSource.minecraft) ...[
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
                              _setCustomPath(_SettingsSource.minecraft, value),
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
                              sourceName: 'Minecraft',
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
                  key: const ValueKey('source-sort-Guild Wars 2'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SourceHeader(
                          headerKey: const ValueKey('source-card-guild-wars-2'),
                          switchKey: const ValueKey('guild-wars-2-enabled'),
                          name: 'Guild Wars 2',
                          description: 'PC · Screenshots',
                          expanded:
                              _expandedSource == _SettingsSource.guildWars2,
                          enabled: _guildWars2Enabled,
                          error:
                              _sourceActivationErrors[_SettingsSource
                                  .guildWars2],
                          onTap: () =>
                              _toggleSource(_SettingsSource.guildWars2),
                          onEnabled: (value) => unawaited(
                            _setSourceEnabled(
                              _SettingsSource.guildWars2,
                              value,
                            ),
                          ),
                        ),
                        if (_expandedSource == _SettingsSource.guildWars2) ...[
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
                              _setCustomPath(_SettingsSource.guildWars2, value),
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
                        ],
                      ],
                    ),
                  ),
                ),
              if (_settingsTab == 2) const SizedBox(height: 12),
              if (_settingsTab == 2)
                FCard(
                  key: const ValueKey('source-sort-Steam'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SourceHeader(
                          headerKey: const ValueKey('source-card-steam'),
                          switchKey: const ValueKey('steam-enabled'),
                          name: 'Steam',
                          description: 'PC · Local and online screenshots',
                          expanded: _expandedSource == _SettingsSource.steam,
                          enabled: _steamEnabled,
                          error: _sourceActivationErrors[_SettingsSource.steam],
                          onTap: () => _toggleSource(_SettingsSource.steam),
                          onEnabled: (value) => unawaited(
                            _setSourceEnabled(_SettingsSource.steam, value),
                          ),
                        ),
                        if (_expandedSource == _SettingsSource.steam) ...[
                          const SizedBox(height: 18),
                          _SettingsSectionHeader(
                            title: 'Steam Web API key',
                            description: 'Required. Steam gives no game name and no online screenshot without this key.',
                            helpKey: const ValueKey('steam-api-key-help'),
                            helpSemanticsLabel:
                                'Help with the Steam Web API key',
                            onHelp: _showSteamApiKeyHelp,
                          ),
                          const SizedBox(height: 12),
                          FTextField.password(
                            key: const ValueKey('steam-api-key'),
                            control: FTextFieldControl.managed(
                              controller: _steamKeyController,
                            ),
                            label: const Text('Steam Web API key'),
                            hint: '32 hexadecimal characters',
                          ),
                          const SizedBox(height: 4),
                          const FDivider(),
                          const SizedBox(height: 4),
                          FCheckbox(
                            key: const ValueKey('steam-custom-path'),
                            label: const Text('Use custom folder'),
                            description: const Text(
                              'Otherwise, the Steam folder is discovered automatically.',
                            ),
                            value: _steamUseCustomPath,
                            enabled: true,
                            onChange: (value) => unawaited(
                              _setCustomPath(_SettingsSource.steam, value),
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
                              sourceName: 'Steam',
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
                          if (_steamOnlineGallery) ...[
                            const SizedBox(height: 12),
                            FTextField(
                              key: const ValueKey('steam-user-id'),
                              control: FTextFieldControl.managed(
                                controller: _steamUserController,
                              ),
                              label: const Text('Steam user ID'),
                              hint: '7656119…',
                              description: const Text(
                                'Required for the online gallery. Open Steam, select your account name, then select Account details. Copy the 17-digit Steam ID.',
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          const FDivider(),
                          const SizedBox(height: 4),
                          _SettingsSectionHeader(
                            title: 'Ignored apps',
                            description: 'Gaming Memories skips the screenshots of these Steam app IDs.',
                            helpKey: const ValueKey('steam-ignored-help'),
                            helpSemanticsLabel: 'Help with ignored apps',
                            onHelp: _showSteamIgnoredAppsHelp,
                          ),
                          const SizedBox(height: 12),
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
                          const SizedBox(height: 4),
                          const FDivider(),
                          const SizedBox(height: 4),
                          _SettingsSectionHeader(
                            title: 'Custom apps',
                            description:
                                'Give your own name to a Steam app ID.',
                            helpKey: const ValueKey('steam-custom-help'),
                            helpSemanticsLabel: 'Help with custom apps',
                            onHelp: _showSteamCustomAppsHelp,
                          ),
                          const SizedBox(height: 12),
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

  void _toggleSource(_SettingsSource source) {
    setState(() {
      _expandedSource = _expandedSource == source ? null : source;
    });
  }

  Future<void> _chooseDirectory(
    SettingsFolderTarget target, {
    String? initialPath,
    String? gameId,
  }) async {
    final source = _sourceForFolderTarget(target);
    final wasEnabled = source == null ? null : _sourceEnabled(source);
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

    if (source != null && wasEnabled == false) {
      await widget.controller.updateSettings(
        _settingsWithSourceEnabled(widget.controller.settings, source, false),
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
            'No supported ${_automaticSourceName(target)} folder was found on this platform.',
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
    final sourceName = _automaticSourceName(target);
    return showFDialog<AutomaticFolderCandidate>(
      context: context,
      builder: (dialogContext, _, animation) => FDialog(
        animation: animation,
        semanticsLabel: 'Choose a $sourceName folder',
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose a $sourceName folder',
                  style: context.theme.typography.display.sm,
                ),
                const SizedBox(height: 8),
                Text(
                  'More than one supported $sourceName folder is available. Choose the one used by your installation. macOS will then ask you to confirm that exact folder.',
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

  Future<void> _setSourceEnabled(_SettingsSource source, bool value) async {
    if (!value) {
      setState(() {
        _setSourceEnabledValue(source, false);
        _sourceActivationErrors.remove(source);
      });
      _scheduleAutosave(immediate: true);
      return;
    }

    setState(() {
      _expandedSource = source;
      _sourceActivationErrors.remove(source);
    });

    if (!widget.controller.usesPersistentFolderAccess) {
      await _enableSourceIfValid(source);
      return;
    }

    final target = switch ((source, _usesCustomPath(source))) {
      // Battle.net folders are chosen per game, from the game's own row.
      (_SettingsSource.battleNet, _) => null,
      (_SettingsSource.guildWars2, true) =>
        SettingsFolderTarget.guildWars2Custom,
      (_SettingsSource.hytale, true) => SettingsFolderTarget.hytaleCustom,
      (_SettingsSource.hytale, false) => SettingsFolderTarget.hytaleAutomatic,
      (_SettingsSource.minecraft, true) => SettingsFolderTarget.minecraftCustom,
      (_SettingsSource.minecraft, false) =>
        SettingsFolderTarget.minecraftAutomatic,
      (_SettingsSource.nintendoSwitch2, true) =>
        SettingsFolderTarget.nintendoSwitch2Custom,
      (_SettingsSource.playStation4, true) =>
        SettingsFolderTarget.playStation4Custom,
      (_SettingsSource.playStation5, true) =>
        SettingsFolderTarget.playStation5Custom,
      (_SettingsSource.steam, true) => SettingsFolderTarget.steamCustom,
      (_SettingsSource.steam, false) => SettingsFolderTarget.steamAutomatic,
      _ => null,
    };
    if (target == null || _sourceAccessReady(source)) {
      await _enableSourceIfValid(source);
      return;
    }

    if (_isAutomaticTarget(target)) {
      await _chooseAutomaticDirectory(target);
    } else {
      await _chooseDirectory(target, initialPath: _sourcePath(source));
    }
    if (mounted && _sourceAccessReady(source)) {
      await _enableSourceIfValid(source);
    }
  }

  Future<void> _enableSourceIfValid(_SettingsSource source) async {
    final draft = _settingsWithSourceEnabled(_draftSettings(), source, true);

    final pathErrors = await _validatePaths(draft);
    if (!mounted) {
      return;
    }
    _showPathErrors(pathErrors);
    final pathError = pathErrors.forSource(source);
    final configurationError = pathError == null
        ? await widget.controller.sourceConfigurationError(
            _sourceName(source),
            draft,
          )
        : null;
    if (!mounted) {
      return;
    }
    final error = pathError ?? configurationError;
    if (error != null) {
      setState(() {
        _setSourceEnabledValue(source, false);
        _expandedSource = source;
        _sourceActivationErrors[source] = error;
      });
      _scheduleAutosave(immediate: true);
      return;
    }

    setState(() {
      _setSourceEnabledValue(source, true);
      _sourceActivationErrors.remove(source);
    });
    _scheduleAutosave(immediate: true);
  }

  bool _sourceEnabled(_SettingsSource source) => switch (source) {
    _SettingsSource.battleNet => _diabloEnabled,
    _SettingsSource.guildWars2 => _guildWars2Enabled,
    _SettingsSource.hytale => _hytaleEnabled,
    _SettingsSource.minecraft => _minecraftEnabled,
    _SettingsSource.nintendoSwitch2 => _nintendoSwitch2Enabled,
    _SettingsSource.playStation4 => _playStation4Enabled,
    _SettingsSource.playStation5 => _playStation5Enabled,
    _SettingsSource.steam => _steamEnabled,
  };

  String _sourceName(_SettingsSource source) => switch (source) {
    _SettingsSource.battleNet => 'Battle.net',
    _SettingsSource.guildWars2 => 'Guild Wars 2',
    _SettingsSource.hytale => 'Hytale',
    _SettingsSource.minecraft => 'Minecraft',
    _SettingsSource.nintendoSwitch2 => 'Nintendo Switch 2',
    _SettingsSource.playStation4 => 'PlayStation 4',
    _SettingsSource.playStation5 => 'PlayStation 5',
    _SettingsSource.steam => 'Steam',
  };

  _SettingsSource? _sourceForFolderTarget(SettingsFolderTarget target) =>
      switch (target) {
        SettingsFolderTarget.library => null,
        SettingsFolderTarget.battleNetGameCustom ||
        SettingsFolderTarget.battleNetGameAutomatic =>
          _SettingsSource.battleNet,
        SettingsFolderTarget.guildWars2Custom => _SettingsSource.guildWars2,
        SettingsFolderTarget.hytaleCustom ||
        SettingsFolderTarget.hytaleAutomatic => _SettingsSource.hytale,
        SettingsFolderTarget.minecraftCustom ||
        SettingsFolderTarget.minecraftAutomatic => _SettingsSource.minecraft,
        SettingsFolderTarget.nintendoSwitch2Custom =>
          _SettingsSource.nintendoSwitch2,
        SettingsFolderTarget.playStation4Custom => _SettingsSource.playStation4,
        SettingsFolderTarget.playStation5Custom => _SettingsSource.playStation5,
        SettingsFolderTarget.steamCustom ||
        SettingsFolderTarget.steamAutomatic => _SettingsSource.steam,
      };

  AppSettings _settingsWithSourceEnabled(
    AppSettings settings,
    _SettingsSource source,
    bool enabled,
  ) => switch (source) {
    _SettingsSource.battleNet => settings.copyWith(
      battleNet: settings.battleNet.copyWith(enabled: enabled),
    ),
    _SettingsSource.guildWars2 => settings.copyWith(
      guildWars2: settings.guildWars2.copyWith(enabled: enabled),
    ),
    _SettingsSource.hytale => settings.copyWith(
      hytale: settings.hytale.copyWith(enabled: enabled),
    ),
    _SettingsSource.minecraft => settings.copyWith(
      minecraft: settings.minecraft.copyWith(enabled: enabled),
    ),
    _SettingsSource.nintendoSwitch2 => settings.copyWith(
      nintendoSwitch2: settings.nintendoSwitch2.copyWith(enabled: enabled),
    ),
    _SettingsSource.playStation4 => settings.copyWith(
      playStation4: settings.playStation4.copyWith(enabled: enabled),
    ),
    _SettingsSource.playStation5 => settings.copyWith(
      playStation5: settings.playStation5.copyWith(enabled: enabled),
    ),
    _SettingsSource.steam => settings.copyWith(
      steam: settings.steam.copyWith(enabled: enabled),
    ),
  };

  Future<void> _setCustomPath(_SettingsSource source, bool value) async {
    if (!widget.controller.usesPersistentFolderAccess) {
      setState(() {
        _setUseCustomPathValue(source, value);
        if (!value) {
          _setSourcePathError(source, null);
        }
      });
      _scheduleAutosave(immediate: true);
      return;
    }

    final target = value
        ? switch (source) {
            _SettingsSource.battleNet => null,
            _SettingsSource.guildWars2 => SettingsFolderTarget.guildWars2Custom,
            _SettingsSource.hytale => SettingsFolderTarget.hytaleCustom,
            _SettingsSource.minecraft => SettingsFolderTarget.minecraftCustom,
            _SettingsSource.nintendoSwitch2 =>
              SettingsFolderTarget.nintendoSwitch2Custom,
            _SettingsSource.playStation4 =>
              SettingsFolderTarget.playStation4Custom,
            _SettingsSource.playStation5 =>
              SettingsFolderTarget.playStation5Custom,
            _SettingsSource.steam => SettingsFolderTarget.steamCustom,
          }
        : switch (source) {
            _SettingsSource.battleNet => null,
            _SettingsSource.hytale => SettingsFolderTarget.hytaleAutomatic,
            _SettingsSource.minecraft =>
              SettingsFolderTarget.minecraftAutomatic,
            _SettingsSource.steam => SettingsFolderTarget.steamAutomatic,
            _ => null,
          };
    if (target != null) {
      if (_isAutomaticTarget(target)) {
        await _chooseAutomaticDirectory(target);
      } else {
        await _chooseDirectory(target, initialPath: _sourcePath(source));
      }
      return;
    }

    setState(() {
      _setUseCustomPathValue(source, false);
      _setSourcePathError(source, null);
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

  bool _usesCustomPath(_SettingsSource source) => switch (source) {
    _SettingsSource.battleNet => false,
    _SettingsSource.guildWars2 => _guildWars2UseCustomPath,
    _SettingsSource.hytale => _hytaleUseCustomPath,
    _SettingsSource.minecraft => _minecraftUseCustomPath,
    _SettingsSource.nintendoSwitch2 => _nintendoSwitch2UseCustomPath,
    _SettingsSource.playStation4 => true,
    _SettingsSource.playStation5 => true,
    _SettingsSource.steam => _steamUseCustomPath,
  };

  String _sourcePath(_SettingsSource source) => switch (source) {
    _SettingsSource.battleNet => '',
    _SettingsSource.guildWars2 => _guildWars2Controller.text,
    _SettingsSource.hytale => _hytaleController.text,
    _SettingsSource.minecraft => _minecraftController.text,
    _SettingsSource.nintendoSwitch2 => _nintendoSwitch2Controller.text,
    _SettingsSource.playStation4 => _playStation4Controller.text,
    _SettingsSource.playStation5 => _playStation5Controller.text,
    _SettingsSource.steam => _steamPathController.text,
  };

  bool _sourceAccessReady(_SettingsSource source) {
    final id = switch (source) {
      _SettingsSource.battleNet => FolderGrantIds.battleNet,
      _SettingsSource.guildWars2 => FolderGrantIds.guildWars2,
      _SettingsSource.hytale => FolderGrantIds.hytale,
      _SettingsSource.minecraft => FolderGrantIds.minecraft,
      _SettingsSource.nintendoSwitch2 => FolderGrantIds.nintendoSwitch2,
      _SettingsSource.playStation4 => FolderGrantIds.playStation4,
      _SettingsSource.playStation5 => FolderGrantIds.playStation5,
      _SettingsSource.steam => FolderGrantIds.steam,
    };
    return widget.controller.folderAuthorization(id).isReady;
  }

  void _setSourceEnabledValue(_SettingsSource source, bool value) {
    switch (source) {
      case _SettingsSource.battleNet:
        _diabloEnabled = value;
        break;
      case _SettingsSource.guildWars2:
        _guildWars2Enabled = value;
        break;
      case _SettingsSource.hytale:
        _hytaleEnabled = value;
        break;
      case _SettingsSource.minecraft:
        _minecraftEnabled = value;
        break;
      case _SettingsSource.nintendoSwitch2:
        _nintendoSwitch2Enabled = value;
        break;
      case _SettingsSource.playStation4:
        _playStation4Enabled = value;
        break;
      case _SettingsSource.playStation5:
        _playStation5Enabled = value;
        break;
      case _SettingsSource.steam:
        _steamEnabled = value;
        break;
    }
  }

  void _setUseCustomPathValue(_SettingsSource source, bool value) {
    switch (source) {
      case _SettingsSource.battleNet:
        // Battle.net has no source-level custom folder; each game has one.
        break;
      case _SettingsSource.guildWars2:
        _guildWars2UseCustomPath = value;
        break;
      case _SettingsSource.hytale:
        _hytaleUseCustomPath = value;
        break;
      case _SettingsSource.minecraft:
        _minecraftUseCustomPath = value;
        break;
      case _SettingsSource.nintendoSwitch2:
        _nintendoSwitch2UseCustomPath = value;
        break;
      case _SettingsSource.playStation4:
      case _SettingsSource.playStation5:
        break;
      case _SettingsSource.steam:
        _steamUseCustomPath = value;
        break;
    }
  }

  void _setSourcePathError(_SettingsSource source, String? value) {
    switch (source) {
      case _SettingsSource.battleNet:
        _diabloPathError = value;
        break;
      case _SettingsSource.guildWars2:
        _guildWars2PathError = value;
        break;
      case _SettingsSource.hytale:
        _hytalePathError = value;
        break;
      case _SettingsSource.minecraft:
        _minecraftPathError = value;
        break;
      case _SettingsSource.nintendoSwitch2:
        _nintendoSwitch2PathError = value;
        break;
      case _SettingsSource.playStation4:
        _playStation4PathError = value;
        break;
      case _SettingsSource.playStation5:
        _playStation5PathError = value;
        break;
      case _SettingsSource.steam:
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

  String _automaticSourceName(SettingsFolderTarget target) {
    return switch (target) {
      SettingsFolderTarget.battleNetGameAutomatic => 'Battle.net',
      SettingsFolderTarget.hytaleAutomatic => 'Hytale',
      SettingsFolderTarget.minecraftAutomatic => 'Minecraft',
      SettingsFolderTarget.steamAutomatic => 'Steam',
      _ => 'automatic',
    };
  }

  void _showSteamApiKeyHelp() {
    _showHelpDialog(
      keyPrefix: 'steam-api-key-help',
      title: 'Steam Web API key',
      summary: 'Every Steam import needs this key.',
      sections: const [
        _HelpSection(
          title: 'Why Gaming Memories needs it',
          body: 'Steam returns game names and published screenshots only to requests that carry a Web API key. Without the key, albums keep their numeric app ID as a name and no online screenshot is imported.',
          steps: 'Sign in at the address below. Register a key and accept the Steam Web API terms.',
          address: 'https://steamcommunity.com/dev/apikey',
        ),
      ],
      footnote: 'Gaming Memories stores the key in its local settings file. Do not share it.',
    );
  }

  void _showSteamIgnoredAppsHelp() {
    _showHelpDialog(
      keyPrefix: 'steam-ignored-help',
      title: 'Ignored apps',
      summary: 'Every Steam import skips these app IDs.',
      sections: const [
        _HelpSection(
          title: 'When to use it',
          body: 'Some Steam app IDs are tools, launchers or games you do not want in the library. An ignored app ID gets no album, and its screenshots are never copied.',
          steps: 'The app ID is the number in the Steam store address of the game. Type it in the field, then select Add.',
        ),
      ],
      footnote: 'Remove an app ID from the list to import it again.',
    );
  }

  void _showSteamCustomAppsHelp() {
    _showHelpDialog(
      keyPrefix: 'steam-custom-help',
      title: 'Custom apps',
      summary:
          'A custom name replaces the name that Steam reports for an app ID.',
      sections: const [
        _HelpSection(
          title: 'When to use it',
          body: 'Non-Steam shortcuts, betas and delisted games have no store page, so Steam reports no name for them. A custom name gives their album a readable title.',
          steps: 'Type the app ID and the name you want, then select Add.',
        ),
      ],
      footnote: 'A custom name applies to new albums and to existing ones on the next import.',
    );
  }

  void _showHelpDialog({
    required String keyPrefix,
    required String title,
    required String summary,
    required List<Widget> sections,
    String? footnote,
  }) {
    showFDialog<void>(
      context: context,
      builder: (dialogContext, _, animation) => FDialog(
        animation: animation,
        semanticsLabel: title,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.theme.typography.display.sm),
                const SizedBox(height: 8),
                Text(
                  summary,
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 20),
                for (final (index, section) in sections.indexed) ...[
                  if (index > 0) const SizedBox(height: 18),
                  section,
                ],
                if (footnote case final value?) ...[
                  const SizedBox(height: 12),
                  Text(
                    value,
                    style: context.theme.typography.body.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerRight,
                  child: FButton(
                    key: ValueKey('$keyPrefix-close'),
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
            game.id: SourceSettings(
              enabled: _battleNetGameOn(game.id),
              useCustomPath: _battleNetGameCustom(game.id),
              sourcePath: _battleNetControllerFor(game.id).text.trim(),
            ),
        },
      ),
      guildWars2: SourceSettings(
        enabled: _guildWars2Enabled,
        useCustomPath: _guildWars2UseCustomPath,
        sourcePath: _guildWars2Controller.text.trim(),
      ),
      hytale: SourceSettings(
        enabled: _hytaleEnabled,
        useCustomPath: _hytaleUseCustomPath,
        sourcePath: _hytaleController.text.trim(),
        downloadCovers: _hytaleDownloadCovers,
      ),
      minecraft: SourceSettings(
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
      playStation4: SourceSettings(
        enabled: _playStation4Enabled,
        useCustomPath: true,
        sourcePath: _playStation4Controller.text.trim(),
      ),
      playStation5: SourceSettings(
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
    final sourceErrors = <String, String>{
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
        sourceErrors: sourceErrors,
      );
    });
    await _saveQueue;
    if (mounted) {
      final saved = widget.controller.settings;
      final validationErrors = widget.controller.sourceValidationErrors;
      setState(() {
        _diabloEnabled = saved.battleNet.enabled;
        _guildWars2Enabled = saved.guildWars2.enabled;
        _hytaleEnabled = saved.hytale.enabled;
        _minecraftEnabled = saved.minecraft.enabled;
        _nintendoSwitch2Enabled = saved.nintendoSwitch2.enabled;
        _playStation4Enabled = saved.playStation4.enabled;
        _playStation5Enabled = saved.playStation5.enabled;
        _steamEnabled = saved.steam.enabled;
        for (final source in _SettingsSource.values) {
          final error = validationErrors[_sourceName(source)];
          if (error != null) {
            _sourceActivationErrors[source] = error;
          } else if (_sourceEnabled(source)) {
            _sourceActivationErrors.remove(source);
          }
        }
        if (validationErrors.isNotEmpty) {
          _expandedSource = _SettingsSource.values.firstWhere(
            (source) => validationErrors.containsKey(_sourceName(source)),
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
  /// validate. Reverting the whole source would throw away edits to games
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
  /// The source-level error is deliberately quiet about games that are
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
          grantId: BattleNetSource.grantIdForGame(folder.game.id),
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
          BattleNetSource.grantIdForGame(folder.game.id),
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

  String? forSource(_SettingsSource source) => switch (source) {
    _SettingsSource.battleNet => battleNet,
    _SettingsSource.guildWars2 => guildWars2,
    _SettingsSource.hytale => hytale,
    _SettingsSource.minecraft => minecraft,
    _SettingsSource.nintendoSwitch2 => nintendoSwitch2,
    _SettingsSource.playStation4 => playStation4,
    _SettingsSource.playStation5 => playStation5,
    _SettingsSource.steam => steam,
  };
}

enum _SettingsSource {
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

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({
    required this.title,
    required this.description,
    required this.helpKey,
    required this.helpSemanticsLabel,
    required this.onHelp,
  });

  final String title;
  final String description;
  final Key helpKey;
  final String helpSemanticsLabel;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: context.theme.typography.body.lg.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            FButton.icon(
              key: helpKey,
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.xs,
              semanticsLabel: helpSemanticsLabel,
              onPress: onHelp,
              child: const Icon(FLucideIcons.circleHelp),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: context.theme.typography.body.xs.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
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
    required this.sortSources,
    required this.crossAxisAlignment,
    required this.children,
  });

  final bool sortSources;
  final CrossAxisAlignment crossAxisAlignment;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!sortSources) {
      return Column(crossAxisAlignment: crossAxisAlignment, children: children);
    }

    final sources =
        children
            .map((child) => (name: _sourceName(child), child: child))
            .where((entry) => entry.name != null)
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.name!.toLowerCase().compareTo(right.name!.toLowerCase()),
          );
    if (sources.isEmpty) {
      return Column(crossAxisAlignment: crossAxisAlignment, children: children);
    }

    final firstSource = children.indexWhere(
      (child) => _sourceName(child) != null,
    );
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        ...children.take(firstSource),
        for (var index = 0; index < sources.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          sources[index].child,
        ],
      ],
    );
  }

  String? _sourceName(Widget child) {
    if (child case _PlayStationSourceCard card) {
      return card.name;
    }
    final key = child.key;
    if (key case ValueKey<String> valueKey) {
      const prefix = 'source-sort-';
      if (valueKey.value.startsWith(prefix)) {
        return valueKey.value.substring(prefix.length);
      }
    }
    return null;
  }
}

class _PlayStationSourceCard extends StatelessWidget {
  const _PlayStationSourceCard({
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
    this.requirement,
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
  final String? requirement;
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
            _SourceHeader(
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
                requirement == null
                    ? 'Select the folder copied from your console.'
                    : 'Select the folder copied from your console. $requirement',
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

class _SourceHeader extends StatelessWidget {
  const _SourceHeader({
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
                    sourceName: folder.game.name,
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
    required this.sourceName,
    required this.automaticDescription,
    required this.status,
    required this.onAllow,
    this.error,
  });

  final Key buttonKey;
  final String sourceName;
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
            ? 'Access allowed to the automatically discovered $sourceName folder.'
            : unavailable
            ? 'The $sourceName folder is unavailable. Choose it again.'
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
