enum FolderGrantAccess {
  readOnly,
  readWrite;

  factory FolderGrantAccess.fromJson(Object? value) {
    return value == readWrite.name ? readWrite : readOnly;
  }
}

class FolderGrant {
  const FolderGrant({
    required this.platform,
    required this.path,
    required this.access,
    required this.bookmark,
  });

  final String platform;
  final String path;
  final FolderGrantAccess access;
  final String bookmark;

  FolderGrant copyWith({
    String? platform,
    String? path,
    FolderGrantAccess? access,
    String? bookmark,
  }) {
    return FolderGrant(
      platform: platform ?? this.platform,
      path: path ?? this.path,
      access: access ?? this.access,
      bookmark: bookmark ?? this.bookmark,
    );
  }

  factory FolderGrant.fromJson(Map<String, Object?> json) {
    return FolderGrant(
      platform: json['platform'] as String? ?? '',
      path: json['path'] as String? ?? '',
      access: FolderGrantAccess.fromJson(json['access']),
      bookmark: json['bookmark'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'platform': platform,
    'path': path,
    'access': access.name,
    'bookmark': bookmark,
  };
}

enum AppThemeMode {
  system,
  light,
  dark;

  factory AppThemeMode.fromJson(Object? value) {
    for (final mode in values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return system;
  }
}

class SourceSettings {
  const SourceSettings({
    required this.enabled,
    required this.useCustomPath,
    required this.sourcePath,
    this.downloadCovers = false,
  });

  const SourceSettings.disabled()
    : enabled = false,
      useCustomPath = false,
      sourcePath = '',
      downloadCovers = false;

  final bool enabled;
  final bool useCustomPath;
  final String sourcePath;
  final bool downloadCovers;

  SourceSettings copyWith({
    bool? enabled,
    bool? useCustomPath,
    String? sourcePath,
    bool? downloadCovers,
  }) {
    return SourceSettings(
      enabled: enabled ?? this.enabled,
      useCustomPath: useCustomPath ?? this.useCustomPath,
      sourcePath: sourcePath ?? this.sourcePath,
      downloadCovers: downloadCovers ?? this.downloadCovers,
    );
  }

  factory SourceSettings.fromJson(Map<String, Object?> json) {
    final storedPath = json['sourcePath'] as String? ?? '';
    final hasLegacyCustomPath =
        storedPath.trim().isNotEmpty && storedPath.trim() != 'auto';

    return SourceSettings(
      enabled: json['enabled'] as bool? ?? false,
      useCustomPath: json['useCustomPath'] as bool? ?? hasLegacyCustomPath,
      sourcePath: hasLegacyCustomPath ? storedPath : '',
      downloadCovers: json['downloadCovers'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'useCustomPath': useCustomPath,
    'sourcePath': sourcePath,
    'downloadCovers': downloadCovers,
  };
}

class SteamSettings {
  const SteamSettings({
    required this.enabled,
    required this.useCustomPath,
    required this.userdataPath,
    required this.onlineGallery,
    required this.userId,
    required this.apiKey,
    required this.downloadCovers,
    required this.ignoredGames,
    required this.customGames,
  });

  const SteamSettings.disabled()
    : enabled = false,
      useCustomPath = false,
      userdataPath = '',
      onlineGallery = false,
      userId = '',
      apiKey = '',
      downloadCovers = false,
      ignoredGames = const [],
      customGames = const {};

  final bool enabled;
  final bool useCustomPath;
  final String userdataPath;
  final bool onlineGallery;
  final String userId;
  final String apiKey;
  final bool downloadCovers;
  final List<String> ignoredGames;
  final Map<String, String> customGames;

  SteamSettings copyWith({
    bool? enabled,
    bool? useCustomPath,
    String? userdataPath,
    bool? onlineGallery,
    String? userId,
    String? apiKey,
    bool? downloadCovers,
    List<String>? ignoredGames,
    Map<String, String>? customGames,
  }) {
    return SteamSettings(
      enabled: enabled ?? this.enabled,
      useCustomPath: useCustomPath ?? this.useCustomPath,
      userdataPath: userdataPath ?? this.userdataPath,
      onlineGallery: onlineGallery ?? this.onlineGallery,
      userId: userId ?? this.userId,
      apiKey: apiKey ?? this.apiKey,
      downloadCovers: downloadCovers ?? this.downloadCovers,
      ignoredGames: ignoredGames ?? this.ignoredGames,
      customGames: customGames ?? this.customGames,
    );
  }

  factory SteamSettings.fromJson(Map<String, Object?> json) {
    final ignored = json['ignoredGames'];
    final custom = json['customGames'];
    final storedPath = json['userdataPath'] as String? ?? '';
    final hasLegacyCustomPath =
        storedPath.trim().isNotEmpty && storedPath.trim() != 'auto';

    return SteamSettings(
      enabled: json['enabled'] as bool? ?? false,
      useCustomPath: json['useCustomPath'] as bool? ?? hasLegacyCustomPath,
      userdataPath: hasLegacyCustomPath ? storedPath : '',
      onlineGallery: json['onlineGallery'] as bool? ?? false,
      userId: json['userId'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      downloadCovers: json['downloadCovers'] as bool? ?? false,
      ignoredGames: ignored is List
          ? ignored.whereType<String>().toList(growable: false)
          : const [],
      customGames: custom is Map
          ? custom.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'useCustomPath': useCustomPath,
    'userdataPath': userdataPath,
    'onlineGallery': onlineGallery,
    'userId': userId,
    'apiKey': apiKey,
    'downloadCovers': downloadCovers,
    'ignoredGames': ignoredGames,
    'customGames': customGames,
  };
}

class NintendoSwitchSettings {
  const NintendoSwitchSettings({
    required this.enabled,
    required this.useCustomPath,
    required this.sourcePath,
    required this.ignoredFolders,
  });

  const NintendoSwitchSettings.disabled()
    : enabled = false,
      useCustomPath = false,
      sourcePath = '',
      ignoredFolders = defaultIgnoredFolders;

  static const defaultIgnoredFolders = ['Otra carpeta'];

  final bool enabled;
  final bool useCustomPath;
  final String sourcePath;
  final List<String> ignoredFolders;

  NintendoSwitchSettings copyWith({
    bool? enabled,
    bool? useCustomPath,
    String? sourcePath,
    List<String>? ignoredFolders,
  }) {
    return NintendoSwitchSettings(
      enabled: enabled ?? this.enabled,
      useCustomPath: useCustomPath ?? this.useCustomPath,
      sourcePath: sourcePath ?? this.sourcePath,
      ignoredFolders: ignoredFolders ?? this.ignoredFolders,
    );
  }

  factory NintendoSwitchSettings.fromJson(Map<String, Object?> json) {
    final storedPath = json['sourcePath'] as String? ?? '';
    final hasLegacyCustomPath =
        storedPath.trim().isNotEmpty && storedPath.trim() != 'auto';
    final ignored = json['ignoredFolders'];

    return NintendoSwitchSettings(
      enabled: json['enabled'] as bool? ?? false,
      useCustomPath: json['useCustomPath'] as bool? ?? hasLegacyCustomPath,
      sourcePath: hasLegacyCustomPath ? storedPath : '',
      ignoredFolders: ignored is List
          ? ignored.whereType<String>().toList(growable: false)
          : defaultIgnoredFolders,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'useCustomPath': useCustomPath,
    'sourcePath': sourcePath,
    'ignoredFolders': ignoredFolders,
  };
}

/// Battle.net is one source over several games, so it carries a master
/// switch plus a setting per game, keyed by [BattleNetGame.id].
class BattleNetSettings {
  const BattleNetSettings({required this.enabled, this.games = const {}});

  const BattleNetSettings.disabled() : enabled = false, games = const {};

  final bool enabled;
  final Map<String, SourceSettings> games;

  /// A game with nothing stored is on: the source should work as soon as
  /// the user enables Battle.net, and a game whose folder is not there is
  /// skipped anyway.
  SourceSettings game(String id) =>
      games[id] ??
      const SourceSettings(enabled: true, useCustomPath: false, sourcePath: '');

  BattleNetSettings copyWith({
    bool? enabled,
    Map<String, SourceSettings>? games,
  }) {
    return BattleNetSettings(
      enabled: enabled ?? this.enabled,
      games: games ?? this.games,
    );
  }

  BattleNetSettings withGame(String id, SourceSettings value) {
    return copyWith(games: Map.unmodifiable({...games, id: value}));
  }

  factory BattleNetSettings.fromJson(Map<String, Object?> json) {
    final gamesJson = json['games'];
    final games = <String, SourceSettings>{};
    if (gamesJson is Map) {
      for (final entry in gamesJson.entries) {
        final value = entry.value;
        if (value is Map) {
          games[entry.key.toString()] = SourceSettings.fromJson(
            value.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    }
    return BattleNetSettings(
      enabled: json['enabled'] as bool? ?? false,
      games: Map.unmodifiable(games),
    );
  }

  /// Reads a settings file from before the source was split per game. Only
  /// the master switch survives: the old path pointed at one games root, and
  /// there is no way to tell which game it was for.
  factory BattleNetSettings.fromLegacyJson(Map<String, Object?> json) {
    return BattleNetSettings(enabled: json['enabled'] as bool? ?? false);
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'games': {
      for (final entry in games.entries) entry.key: entry.value.toJson(),
    },
  };
}

/// Which uploader carries a publish to the remote host.
enum PublishTransportKind {
  /// rsync when a capable one is on PATH and the key needs no passphrase,
  /// SFTP otherwise.
  auto,
  rsync,
  sftp;

  factory PublishTransportKind.fromJson(Object? value) {
    for (final kind in values) {
      if (kind.name == value) {
        return kind;
      }
    }
    return auto;
  }
}

/// How a publish proves who it is to the remote host.
enum PublishCredentialKind {
  /// Whatever the system already knows: a running SSH agent, and the usual
  /// identity files under `~/.ssh`. Nothing to configure.
  automaticKey,

  /// One key file, named in the settings.
  manualKey,

  /// A password, asked for at publish time and never stored.
  password;

  factory PublishCredentialKind.fromJson(Object? value) {
    for (final kind in values) {
      if (kind.name == value) {
        return kind;
      }
    }
    return automaticKey;
  }
}

/// What a publish has to ask the user for before it can start.
enum PublishSecretKind {
  /// Nothing: an agent, or an unprotected key, answers for it.
  none,

  /// The passphrase of the key it is about to use.
  passphrase,

  /// The account password on the remote host.
  password,
}

/// What the rendered pages say about the site they belong to.
class PublishSiteSettings {
  const PublishSiteSettings({
    required this.title,
    required this.author,
    required this.url,
    required this.footerText,
  });

  const PublishSiteSettings.defaults()
    : title = '',
      author = '',
      url = '',
      footerText = '';

  final String title;
  final String author;

  /// The site's public base URL, used for the absolute `og:` links. A page
  /// leaves those tags out when this is empty.
  final String url;
  final String footerText;

  PublishSiteSettings copyWith({
    String? title,
    String? author,
    String? url,
    String? footerText,
  }) {
    return PublishSiteSettings(
      title: title ?? this.title,
      author: author ?? this.author,
      url: url ?? this.url,
      footerText: footerText ?? this.footerText,
    );
  }

  factory PublishSiteSettings.fromJson(Map<String, Object?> json) {
    return PublishSiteSettings(
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      url: json['url'] as String? ?? '',
      footerText: json['footerText'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'author': author,
    'url': url,
    'footerText': footerText,
  };
}

/// Where a publish goes and what it leaves behind.
class PublishTargetSettings {
  const PublishTargetSettings({
    required this.host,
    required this.port,
    required this.username,
    required this.remotePath,
    required this.fileMode,
    required this.directoryMode,
    required this.deleteRemoved,
    this.credential = PublishCredentialKind.automaticKey,
    this.keyPath = '',
  });

  const PublishTargetSettings.defaults()
    : host = '',
      port = defaultPort,
      username = '',
      remotePath = '',
      credential = PublishCredentialKind.automaticKey,
      keyPath = '',
      fileMode = defaultFileMode,
      directoryMode = defaultDirectoryMode,
      deleteRemoved = true;

  static const defaultPort = 22;

  /// The modes `chmod -R u=rwX,go=rX` leaves behind, which is what the site
  /// this feature replaces is served with.
  static const defaultFileMode = '644';
  static const defaultDirectoryMode = '755';

  final String host;
  final int port;
  final String username;
  final String remotePath;

  final PublishCredentialKind credential;

  /// The private key file, for [PublishCredentialKind.manualKey] alone. The
  /// other kinds ignore it.
  final String keyPath;

  /// Octal permissions, without a leading zero, as `chmod` takes them.
  final String fileMode;
  final String directoryMode;

  /// Whether a remote file the gallery no longer holds is removed, which is
  /// what `rsync --delete` does today.
  final bool deleteRemoved;

  PublishTargetSettings copyWith({
    String? host,
    int? port,
    String? username,
    String? remotePath,
    PublishCredentialKind? credential,
    String? keyPath,
    String? fileMode,
    String? directoryMode,
    bool? deleteRemoved,
  }) {
    return PublishTargetSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      remotePath: remotePath ?? this.remotePath,
      credential: credential ?? this.credential,
      keyPath: keyPath ?? this.keyPath,
      fileMode: fileMode ?? this.fileMode,
      directoryMode: directoryMode ?? this.directoryMode,
      deleteRemoved: deleteRemoved ?? this.deleteRemoved,
    );
  }

  factory PublishTargetSettings.fromJson(Map<String, Object?> json) {
    final port = json['port'];
    final keyPath = json['keyPath'] as String? ?? '';
    return PublishTargetSettings(
      host: json['host'] as String? ?? '',
      port: port is int && port > 0 && port <= 65535 ? port : defaultPort,
      username: json['username'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '',
      // A settings file from before the choice existed named a key or it named
      // nothing, which is exactly the difference between the two key kinds.
      credential: json.containsKey('credential')
          ? PublishCredentialKind.fromJson(json['credential'])
          : keyPath.trim().isEmpty
          ? PublishCredentialKind.automaticKey
          : PublishCredentialKind.manualKey,
      keyPath: keyPath,
      fileMode: json['fileMode'] as String? ?? defaultFileMode,
      directoryMode: json['directoryMode'] as String? ?? defaultDirectoryMode,
      deleteRemoved: json['deleteRemoved'] as bool? ?? true,
    );
  }

  Map<String, Object?> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'remotePath': remotePath,
    'credential': credential.name,
    'keyPath': keyPath,
    'fileMode': fileMode,
    'directoryMode': directoryMode,
    'deleteRemoved': deleteRemoved,
  };
}

/// Renders the library as a static site and uploads it. Nothing here holds a
/// secret: the key is a path, and its passphrase is asked for at publish time
/// and kept in memory only.
class PublishSettings {
  const PublishSettings({
    required this.enabled,
    this.transport = PublishTransportKind.auto,
    this.site = const PublishSiteSettings.defaults(),
    this.target = const PublishTargetSettings.defaults(),
    this.excluded = const [],
  });

  const PublishSettings.disabled()
    : enabled = false,
      transport = PublishTransportKind.auto,
      site = const PublishSiteSettings.defaults(),
      target = const PublishTargetSettings.defaults(),
      excluded = const [];

  final bool enabled;
  final PublishTransportKind transport;
  final PublishSiteSettings site;
  final PublishTargetSettings target;

  /// Album paths relative to the library folder, as `Steam` or `Steam/Hades`.
  /// An excluded album is neither rendered nor uploaded, and leaves the remote
  /// on the next publish.
  final List<String> excluded;

  PublishSettings copyWith({
    bool? enabled,
    PublishTransportKind? transport,
    PublishSiteSettings? site,
    PublishTargetSettings? target,
    List<String>? excluded,
  }) {
    return PublishSettings(
      enabled: enabled ?? this.enabled,
      transport: transport ?? this.transport,
      site: site ?? this.site,
      target: target ?? this.target,
      excluded: excluded ?? this.excluded,
    );
  }

  factory PublishSettings.fromJson(Map<String, Object?> json) {
    final siteJson = json['site'];
    final targetJson = json['target'];
    final excluded = json['excluded'];

    return PublishSettings(
      enabled: json['enabled'] as bool? ?? false,
      transport: PublishTransportKind.fromJson(json['transport']),
      site: siteJson is Map<String, Object?>
          ? PublishSiteSettings.fromJson(siteJson)
          : const PublishSiteSettings.defaults(),
      target: targetJson is Map<String, Object?>
          ? PublishTargetSettings.fromJson(targetJson)
          : const PublishTargetSettings.defaults(),
      excluded: excluded is List
          ? excluded.whereType<String>().toList(growable: false)
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'transport': transport.name,
    'site': site.toJson(),
    'target': target.toJson(),
    'excluded': excluded,
  };
}

class AppSettings {
  const AppSettings({
    required this.outputPath,
    this.battleNet = const BattleNetSettings.disabled(),
    this.guildWars2 = const SourceSettings.disabled(),
    this.hytale = const SourceSettings.disabled(),
    this.minecraft = const SourceSettings.disabled(),
    this.nintendoSwitch = const NintendoSwitchSettings.disabled(),
    this.nintendoSwitch2 = const NintendoSwitchSettings.disabled(),
    this.playStation4 = const SourceSettings.disabled(),
    this.playStation5 = const SourceSettings.disabled(),
    this.steam = const SteamSettings.disabled(),
    this.publish = const PublishSettings.disabled(),
    this.themeMode = AppThemeMode.system,
    this.folderGrants = const {},
  });

  const AppSettings.defaults()
    : outputPath = '',
      battleNet = const BattleNetSettings.disabled(),
      guildWars2 = const SourceSettings.disabled(),
      hytale = const SourceSettings.disabled(),
      minecraft = const SourceSettings.disabled(),
      nintendoSwitch = const NintendoSwitchSettings.disabled(),
      nintendoSwitch2 = const NintendoSwitchSettings.disabled(),
      playStation4 = const SourceSettings.disabled(),
      playStation5 = const SourceSettings.disabled(),
      steam = const SteamSettings.disabled(),
      publish = const PublishSettings.disabled(),
      themeMode = AppThemeMode.system,
      folderGrants = const {};

  final String outputPath;
  final BattleNetSettings battleNet;
  final SourceSettings guildWars2;
  final SourceSettings hytale;
  final SourceSettings minecraft;
  final NintendoSwitchSettings nintendoSwitch;
  final NintendoSwitchSettings nintendoSwitch2;
  final SourceSettings playStation4;
  final SourceSettings playStation5;
  final SteamSettings steam;
  final PublishSettings publish;
  final AppThemeMode themeMode;
  final Map<String, FolderGrant> folderGrants;

  AppSettings copyWith({
    String? outputPath,
    BattleNetSettings? battleNet,
    SourceSettings? guildWars2,
    SourceSettings? hytale,
    SourceSettings? minecraft,
    NintendoSwitchSettings? nintendoSwitch,
    NintendoSwitchSettings? nintendoSwitch2,
    SourceSettings? playStation4,
    SourceSettings? playStation5,
    SteamSettings? steam,
    PublishSettings? publish,
    AppThemeMode? themeMode,
    Map<String, FolderGrant>? folderGrants,
  }) {
    return AppSettings(
      outputPath: outputPath ?? this.outputPath,
      battleNet: battleNet ?? this.battleNet,
      guildWars2: guildWars2 ?? this.guildWars2,
      hytale: hytale ?? this.hytale,
      minecraft: minecraft ?? this.minecraft,
      nintendoSwitch: nintendoSwitch ?? this.nintendoSwitch,
      nintendoSwitch2: nintendoSwitch2 ?? this.nintendoSwitch2,
      playStation4: playStation4 ?? this.playStation4,
      playStation5: playStation5 ?? this.playStation5,
      steam: steam ?? this.steam,
      publish: publish ?? this.publish,
      themeMode: themeMode ?? this.themeMode,
      folderGrants: folderGrants ?? this.folderGrants,
    );
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final battleNetJson = json['battleNet'] ?? json['diabloIV'];
    final guildWars2Json = json['guildWars2'];
    final hytaleJson = json['hytale'];
    final minecraftJson = json['minecraft'];
    final nintendoSwitchJson = json['nintendoSwitch'];
    final nintendoSwitch2Json = json['nintendoSwitch2'];
    final playStation4Json = json['playStation4'];
    final playStation5Json = json['playStation5'];
    final steamJson = json['steam'];
    final publishJson = json['publish'];
    final grantsJson = json['folderGrants'];
    final grants = <String, FolderGrant>{};
    if (grantsJson is Map) {
      for (final entry in grantsJson.entries) {
        final value = entry.value;
        if (value is Map) {
          grants[entry.key.toString()] = FolderGrant.fromJson(
            value.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    }
    final legacyBattleNetGrant = grants.remove('source.diabloIV');
    if (legacyBattleNetGrant != null &&
        !grants.containsKey('source.battleNet')) {
      grants['source.battleNet'] = legacyBattleNetGrant;
    }

    return AppSettings(
      outputPath: json['outputPath'] as String? ?? '',
      battleNet: battleNetJson is! Map<String, Object?>
          ? const BattleNetSettings.disabled()
          : battleNetJson.containsKey('games')
          ? BattleNetSettings.fromJson(battleNetJson)
          : BattleNetSettings.fromLegacyJson(battleNetJson),
      guildWars2: guildWars2Json is Map<String, Object?>
          ? SourceSettings.fromJson(guildWars2Json)
          : const SourceSettings.disabled(),
      hytale: hytaleJson is Map<String, Object?>
          ? SourceSettings.fromJson(hytaleJson)
          : const SourceSettings.disabled(),
      minecraft: minecraftJson is Map<String, Object?>
          ? SourceSettings.fromJson(minecraftJson)
          : const SourceSettings.disabled(),
      nintendoSwitch: nintendoSwitchJson is Map<String, Object?>
          ? NintendoSwitchSettings.fromJson(nintendoSwitchJson)
          : const NintendoSwitchSettings.disabled(),
      nintendoSwitch2: nintendoSwitch2Json is Map<String, Object?>
          ? NintendoSwitchSettings.fromJson(nintendoSwitch2Json)
          : const NintendoSwitchSettings.disabled(),
      playStation4: playStation4Json is Map<String, Object?>
          ? SourceSettings.fromJson(playStation4Json)
          : const SourceSettings.disabled(),
      playStation5: playStation5Json is Map<String, Object?>
          ? SourceSettings.fromJson(playStation5Json)
          : const SourceSettings.disabled(),
      steam: steamJson is Map<String, Object?>
          ? SteamSettings.fromJson(steamJson)
          : const SteamSettings.disabled(),
      publish: publishJson is Map<String, Object?>
          ? PublishSettings.fromJson(publishJson)
          : const PublishSettings.disabled(),
      themeMode: AppThemeMode.fromJson(json['themeMode']),
      folderGrants: Map.unmodifiable(grants),
    );
  }

  Map<String, Object?> toJson() => {
    'version': 14,
    'outputPath': outputPath,
    'themeMode': themeMode.name,
    'battleNet': battleNet.toJson(),
    'guildWars2': guildWars2.toJson(),
    'hytale': hytale.toJson(),
    'minecraft': minecraft.toJson(),
    'nintendoSwitch': nintendoSwitch.toJson(),
    'nintendoSwitch2': nintendoSwitch2.toJson(),
    'playStation4': playStation4.toJson(),
    'playStation5': playStation5.toJson(),
    'steam': steam.toJson(),
    'publish': publish.toJson(),
    'folderGrants': {
      for (final entry in folderGrants.entries) entry.key: entry.value.toJson(),
    },
  };
}
