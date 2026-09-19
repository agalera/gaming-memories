import 'dart:io';

import 'package:flutter/services.dart';
import 'package:imclipboard/imclipboard.dart';
import 'package:path/path.dart' as p;

abstract interface class ScreenshotActionService {
  String get openLocationLabel;

  Future<void> openLocation(String path);

  Future<void> copyImage(String path);

  Future<void> copyPath(String path);
}

class NativeScreenshotActionService implements ScreenshotActionService {
  const NativeScreenshotActionService();

  @override
  String get openLocationLabel {
    if (Platform.isMacOS) {
      return 'Open in Finder';
    }
    if (Platform.isWindows) {
      return 'Open in File Explorer';
    }
    return 'Open in file manager';
  }

  @override
  Future<void> openLocation(String path) async {
    final (executable, arguments) = switch (Platform.operatingSystem) {
      'macos' => ('open', ['-R', path]),
      'windows' => ('explorer.exe', ['/select,', path]),
      'linux' => ('xdg-open', [p.dirname(path)]),
      _ => throw UnsupportedError(
        'The file manager is not available on this platform.',
      ),
    };
    final result = await Process.run(executable, arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        result.stderr.toString().trim(),
        result.exitCode,
      );
    }
  }

  @override
  Future<void> copyImage(String path) async {
    final supported = await const ImClipboard().writeEncodedImage(
      await File(path).readAsBytes(),
    );
    if (!supported) {
      throw UnsupportedError('The image clipboard is not available.');
    }
  }

  @override
  Future<void> copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
  }
}
