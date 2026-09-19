import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

class ConfigStore {
  const ConfigStore({required this.filePath});

  final String filePath;

  Future<AppSettings> load() async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const AppSettings.defaults();
    }

    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, Object?>) {
      throw const FormatException('The settings file must contain an object.');
    }

    return AppSettings.fromJson(value);
  }

  Future<void> save(AppSettings settings) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );
  }
}
