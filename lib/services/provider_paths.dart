import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'library_scanner.dart';

class ProviderPathResolver {
  const ProviderPathResolver({
    this.userHomeDirectory,
    this.allowEnvironmentHome = true,
  });

  final String? userHomeDirectory;
  final bool allowEnvironmentHome;

  List<String> steamUserdataCandidates() {
    return ProviderPaths.steamUserdataCandidates(
      userHomeDirectory: userHomeDirectory,
      allowEnvironmentHome: allowEnvironmentHome,
    );
  }

  String? steamUserdata() {
    return ProviderPaths.steamUserdata(
      userHomeDirectory: userHomeDirectory,
      allowEnvironmentHome: allowEnvironmentHome,
    );
  }

  String? hytaleScreenshots() {
    return ProviderPaths.hytaleScreenshots(
      userHomeDirectory: userHomeDirectory,
      allowEnvironmentHome: allowEnvironmentHome,
    );
  }

  List<String> minecraftScreenshots() {
    return ProviderPaths.minecraftScreenshots(
      userHomeDirectory: userHomeDirectory,
      allowEnvironmentHome: allowEnvironmentHome,
    );
  }
}

const _folderAccessChannel = MethodChannel('gaming-memories/folder-access');

Future<String?> platformUserHomeDirectory() async {
  if (!Platform.isMacOS) {
    return homeDirectory();
  }

  try {
    final path = await _folderAccessChannel.invokeMethod<String>(
      'userHomeDirectory',
    );
    return path?.trim().isEmpty == false ? path : null;
  } on PlatformException {
    return null;
  }
}

abstract final class ProviderPaths {
  static List<String> diabloIVScreenshots() {
    if (!Platform.isWindows) {
      return const [];
    }
    final home = homeDirectory();
    if (home == null) {
      return const [];
    }
    return [
      p.join(home, 'Pictures', 'Diablo IV'),
      p.join(home, 'Documents', 'Diablo IV', 'Screenshots'),
    ];
  }

  static String? guildWars2Screenshots() {
    if (!Platform.isWindows) {
      return null;
    }
    final home = homeDirectory();
    return home == null
        ? null
        : p.join(home, 'Documents', 'Guild Wars 2', 'Screens');
  }

  static String? hytaleScreenshots({
    String? userHomeDirectory,
    bool allowEnvironmentHome = true,
  }) {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return null;
    }
    final home =
        userHomeDirectory ?? (allowEnvironmentHome ? homeDirectory() : null);
    return home == null ? null : p.join(home, 'Pictures', 'Hytale Screenshots');
  }

  static List<String> minecraftScreenshots({
    String? userHomeDirectory,
    bool allowEnvironmentHome = true,
    String? operatingSystem,
    String? windowsAppDataDirectory,
  }) {
    final platform = operatingSystem ?? Platform.operatingSystem;
    if (platform == 'windows') {
      final appData =
          windowsAppDataDirectory ??
          (allowEnvironmentHome ? Platform.environment['APPDATA'] : null);
      return appData == null
          ? const []
          : [p.join(appData, '.minecraft', 'screenshots')];
    }

    final home =
        userHomeDirectory ?? (allowEnvironmentHome ? homeDirectory() : null);
    if (home == null) {
      return const [];
    }
    if (platform == 'macos') {
      return [
        p.join(
          home,
          'Library',
          'Application Support',
          'minecraft',
          'screenshots',
        ),
      ];
    }
    if (platform == 'linux') {
      return [
        p.join(home, '.minecraft', 'screenshots'),
        p.join(
          home,
          '.var',
          'app',
          'com.mojang.Minecraft',
          '.minecraft',
          'screenshots',
        ),
        p.join(
          home,
          '.var',
          'app',
          'com.mojang.Minecraft',
          'data',
          'minecraft',
          'screenshots',
        ),
      ];
    }
    return const [];
  }

  static String? steamUserdata({
    String? userHomeDirectory,
    bool allowEnvironmentHome = true,
  }) {
    final candidates = steamUserdataCandidates(
      userHomeDirectory: userHomeDirectory,
      allowEnvironmentHome: allowEnvironmentHome,
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  static List<String> steamUserdataCandidates({
    String? userHomeDirectory,
    bool allowEnvironmentHome = true,
  }) {
    if (Platform.isWindows) {
      return const [r'C:\Program Files (x86)\Steam\userdata'];
    }
    final home =
        userHomeDirectory ?? (allowEnvironmentHome ? homeDirectory() : null);
    if (home == null) {
      return const [];
    }
    if (Platform.isMacOS) {
      return [
        p.join(home, 'Library', 'Application Support', 'Steam', 'userdata'),
      ];
    }
    if (Platform.isLinux) {
      return [p.join(home, '.local', 'share', 'Steam', 'userdata')];
    }
    return const [];
  }
}
