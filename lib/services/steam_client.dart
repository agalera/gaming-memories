import 'dart:convert';
import 'dart:io';

import 'file_cache.dart';

class SteamPublishedScreenshot {
  const SteamPublishedScreenshot({
    required this.appId,
    required this.fileUrl,
    required this.createdAt,
    required this.shortcutName,
  });

  final String appId;
  final String fileUrl;
  final DateTime createdAt;
  final String shortcutName;
}

abstract interface class SteamApi {
  Future<String?> gameName(String appId, String apiKey);
  Future<String?> appIdForName(String name, String apiKey);
  Future<List<SteamPublishedScreenshot>> publishedScreenshots(
    String userId,
    String apiKey,
  );
  Future<List<int>> download(String url);
  Future<List<int>?> gameCover(String appId);
}

class SteamClient implements SteamApi {
  SteamClient({required this.cache, HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  static const _appListUrl =
      'https://api.steampowered.com/IStoreService/GetAppList/v1/';
  static const _publishedUrl =
      'https://api.steampowered.com/IPublishedFileService/GetUserFiles/v1/';
  static const _detailsUrl = 'https://store.steampowered.com/api/appdetails';
  static const _legacyCoverUrl =
      'https://cdn.cloudflare.steamstatic.com/steam/apps';
  static const _appListAge = Duration(days: 7);
  static const _appDetailsAge = Duration(days: 30);
  static const _appDetailsMissAge = Duration(days: 1);

  final ByteCache cache;
  final HttpClient _httpClient;
  Map<String, String>? _appsById;
  Map<String, String>? _idsByName;

  @override
  Future<String?> gameName(String appId, String apiKey) async {
    try {
      await _loadAppList(apiKey);
    } on Exception {
      // The public store lookup below supplies a fallback for API failures.
    }
    return _appsById?[appId] ?? (await _appDetails(appId))?.name;
  }

  @override
  Future<String?> appIdForName(String name, String apiKey) async {
    await _loadAppList(apiKey);
    return _idsByName?[name];
  }

  @override
  Future<List<SteamPublishedScreenshot>> publishedScreenshots(
    String userId,
    String apiKey,
  ) async {
    if (apiKey.trim().isEmpty) {
      throw const FormatException('Steam API key is required.');
    }
    if (userId.trim().isEmpty) {
      throw const FormatException('Steam user ID is required.');
    }

    final results = <SteamPublishedScreenshot>[];
    var page = 1;
    var total = 1;
    while (results.length < total) {
      final uri = Uri.parse(_publishedUrl).replace(
        queryParameters: {
          'key': apiKey,
          'steamid': userId,
          'filetype': '4',
          'numperpage': '100',
          'page': '$page',
        },
      );
      final decoded = jsonDecode(utf8.decode(await _get(uri))) as Map;
      final response = decoded['response'] as Map? ?? const {};
      total = (response['total'] as num?)?.toInt() ?? 0;
      final details = response['publishedfiledetails'] as List? ?? const [];
      for (final value in details.whereType<Map>()) {
        final epoch = (value['time_created'] as num?)?.toInt() ?? 0;
        results.add(
          SteamPublishedScreenshot(
            appId: '${(value['consumer_appid'] as num?)?.toInt() ?? 0}',
            fileUrl: value['file_url'] as String? ?? '',
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              epoch * 1000,
              isUtc: true,
            ).toLocal(),
            shortcutName: value['shortcutname'] as String? ?? '',
          ),
        );
      }
      if (details.isEmpty) {
        break;
      }
      page++;
    }
    return results;
  }

  @override
  Future<List<int>> download(String url) => _get(Uri.parse(url));

  @override
  Future<List<int>?> gameCover(String appId) async {
    final cached = await _appDetails(appId, cachedOnly: true);
    if (cached?.coverUrl.isNotEmpty ?? false) {
      final bytes = await _tryGet(Uri.parse(cached!.coverUrl));
      if (bytes != null) {
        return bytes;
      }
    }

    final legacy = await _tryGet(
      Uri.parse('$_legacyCoverUrl/$appId/header.jpg'),
    );
    if (legacy != null) {
      return legacy;
    }

    final fresh = await _appDetails(appId, forceRefresh: true);
    if (fresh == null || fresh.coverUrl.isEmpty) {
      return null;
    }
    return _tryGet(Uri.parse(fresh.coverUrl));
  }

  Future<void> _loadAppList(String apiKey) async {
    if (_appsById != null) {
      return;
    }

    var payload = await cache.get('steam-app-list', _appListAge);
    if (payload == null) {
      if (apiKey.trim().isEmpty) {
        return;
      }

      final apps = <Object?>[];
      var lastAppId = '0';
      while (true) {
        final query = <String, String>{'key': apiKey, 'max_results': '50000'};
        if (lastAppId != '0') {
          query['last_appid'] = lastAppId;
        }
        final uri = Uri.parse(_appListUrl).replace(queryParameters: query);
        final decoded = jsonDecode(utf8.decode(await _get(uri))) as Map;
        final response = decoded['response'] as Map? ?? const {};
        final page = response['apps'] as List? ?? const [];
        apps.addAll(page);
        final next = '${response['last_appid'] ?? 0}';
        if (page.isEmpty || next == '0' || next == lastAppId) {
          break;
        }
        lastAppId = next;
      }
      payload = utf8.encode(jsonEncode(apps));
      await cache.set('steam-app-list', payload);
    }

    final values = jsonDecode(utf8.decode(payload)) as List;
    final byId = <String, String>{};
    final byName = <String, String>{};
    for (final value in values.whereType<Map>()) {
      final id = '${value['appid'] ?? ''}';
      final name = value['name'] as String? ?? '';
      if (id.isNotEmpty && name.isNotEmpty) {
        byId[id] = name;
        byName.putIfAbsent(name, () => id);
      }
    }
    _appsById = byId;
    _idsByName = byName;
  }

  Future<_SteamAppDetails?> _appDetails(
    String appId, {
    bool cachedOnly = false,
    bool forceRefresh = false,
  }) async {
    final key = 'steam-app-$appId';
    if (!forceRefresh) {
      final cached = await cache.get(key, _appDetailsAge);
      if (cached != null) {
        final decoded = jsonDecode(utf8.decode(cached)) as Map;
        return _SteamAppDetails.fromJson(decoded);
      }
      final miss = await cache.get('$key-miss', _appDetailsMissAge);
      if (miss != null || cachedOnly) {
        return null;
      }
    }

    final uri = Uri.parse(_detailsUrl)
        .replace(queryParameters: {'appids': appId});
    final decoded = jsonDecode(utf8.decode(await _get(uri))) as Map;
    final entry = decoded[appId] as Map?;
    if (entry == null || entry['success'] != true) {
      await cache.set('$key-miss', const [1]);
      return null;
    }
    final data = entry['data'] as Map? ?? const {};
    final details = _SteamAppDetails(
      name: data['name'] as String? ?? '',
      coverUrl: data['header_image'] as String? ?? '',
    );
    await cache.set(key, utf8.encode(jsonEncode(details.toJson())));
    return details;
  }

  Future<List<int>> _get(Uri uri) async {
    final request = await _httpClient.getUrl(uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'github.com/fmartingr/gaming-memories',
    );
    final response = await request.close();
    final bytes = await response.fold<List<int>>(<int>[], (all, next) {
      all.addAll(next);
      return all;
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Steam request failed with status ${response.statusCode}.',
        uri: uri,
      );
    }
    return bytes;
  }

  Future<List<int>?> _tryGet(Uri uri) async {
    try {
      return await _get(uri);
    } on HttpException {
      return null;
    }
  }
}

class _SteamAppDetails {
  const _SteamAppDetails({required this.name, required this.coverUrl});

  final String name;
  final String coverUrl;

  factory _SteamAppDetails.fromJson(Map json) {
    return _SteamAppDetails(
      name: json['name'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
    );
  }

  Map<String, String> toJson() => {'name': name, 'coverUrl': coverUrl};
}
