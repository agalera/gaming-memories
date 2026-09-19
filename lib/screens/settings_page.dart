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
  late final TextEditingController _steamIgnoredController;
  late final TextEditingController _steamCustomController;
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
    _steamIgnoredController = TextEditingController(
      text: steam.ignoredGames.join(', '),
    );
    _steamCustomController = TextEditingController(
      text: steam.customGames.entries
          .map((entry) => '${entry.key} = ${entry.value}')
          .join('\n'),
    );
    _diabloEnabled = widget.controller.settings.diabloIV.enabled;
    _steamEnabled = steam.enabled;
    _steamOnlineGallery = steam.onlineGallery;
    _steamDownloadCovers = steam.downloadCovers;
  }

  @override
  void dispose() {
    _outputController.dispose();
    _diabloController.dispose();
    _steamPathController.dispose();
    _steamUserController.dispose();
    _steamKeyController.dispose();
    _steamIgnoredController.dispose();
    _steamCustomController.dispose();
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
              _sectionTitle(context, 'Library'),
              const SizedBox(height: 10),
              FCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Screenshot library',
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
                        hint: '/path/to/screenshots',
                        onBrowse: () => _chooseDirectory(
                          controller: _outputController,
                          title: 'Choose the screenshot library',
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
                      FTextField(
                        control: FTextFieldControl.managed(
                          controller: _steamIgnoredController,
                        ),
                        label: const Text('Ignored app IDs'),
                        hint: '1234, 5678',
                        description: const Text(
                          'Separate app IDs with commas or new lines.',
                        ),
                        minLines: 2,
                        maxLines: 3,
                        enabled: _steamEnabled,
                      ),
                      const SizedBox(height: 16),
                      FTextField(
                        control: FTextFieldControl.managed(
                          controller: _steamCustomController,
                        ),
                        label: const Text('Custom game names'),
                        hint: '1234 = My Game',
                        description: const Text(
                          'Enter one app ID and game name on each line.',
                        ),
                        minLines: 3,
                        maxLines: 6,
                        enabled: _steamEnabled,
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

  Future<void> _save() async {
    final ignoredGames = _steamIgnoredController.text
        .split(RegExp(r'[,\n]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final customGames = <String, String>{};
    for (final line in _steamCustomController.text.split('\n')) {
      final separator = line.indexOf('=');
      if (separator < 1) {
        continue;
      }
      final appId = line.substring(0, separator).trim();
      final name = line.substring(separator + 1).trim();
      if (appId.isNotEmpty && name.isNotEmpty) {
        customGames[appId] = name;
      }
    }
    final next = AppSettings(
      outputPath: _outputController.text.trim(),
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
        ignoredGames: ignoredGames,
        customGames: customGames,
      ),
    );
    await widget.controller.saveSettings(next);
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
