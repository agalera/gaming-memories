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
  late bool _diabloEnabled;

  @override
  void initState() {
    super.initState();
    _outputController = TextEditingController(
      text: widget.controller.settings.outputPath,
    );
    _diabloController = TextEditingController(
      text: widget.controller.settings.diabloIV.sourcePath,
    );
    _diabloEnabled = widget.controller.settings.diabloIV.enabled;
  }

  @override
  void dispose() {
    _outputController.dispose();
    _diabloController.dispose();
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
    final next = AppSettings(
      outputPath: _outputController.text.trim(),
      diabloIV: ProviderSettings(
        enabled: _diabloEnabled,
        sourcePath: _diabloController.text.trim(),
      ),
    );
    await widget.controller.saveSettings(next);
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
