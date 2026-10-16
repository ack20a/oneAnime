import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:oneanime/request/request.dart';
import 'package:oneanime/utils/anime_title.dart';
import 'package:path_provider/path_provider.dart';

/// One anime that bangumi-data maps onto Bilibili.
class BangumiDataEntry {
  final List<AnimeTitle> titles;

  /// Bilibili media ids, mainland release first.
  final List<int> bilibiliMediaIds;

  const BangumiDataEntry(this.titles, this.bilibiliMediaIds);
}

/// The community maintained bangumi-data index
/// (https://github.com/bangumi-data/bangumi-data), used to find an anime on
/// Bilibili by title, since Bilibili's own search refuses anonymous clients.
///
/// The full index is about 8 MB, so only the Bilibili mappings are kept, in a
/// small cache file that is refreshed weekly.
class BangumiData {
  static const List<String> _sources = [
    'https://cdn.jsdelivr.net/npm/bangumi-data@0.3/dist/data.json',
    'https://unpkg.com/bangumi-data@0.3/dist/data.json',
  ];

  /// Mainland first, it carries far more danmaku than the regional releases.
  static const List<String> _bilibiliSites = [
    'bilibili',
    'bilibili_hk_mo_tw',
    'bilibili_tw',
    'bilibili_hk_mo',
  ];

  static const Duration _maxAge = Duration(days: 7);

  static Future<List<BangumiDataEntry>>? _entries;

  /// The entry whose title matches [title] exactly (ignoring spacing,
  /// punctuation and how the season is written), or null. Unlike a search
  /// result list, the index holds thousands of works, so a looser match would
  /// too easily land on a different one.
  static Future<BangumiDataEntry?> find(String title) async {
    final AnimeTitle target = AnimeTitle.parse(title);
    if (target.name.isEmpty) {
      return null;
    }
    for (final BangumiDataEntry entry in await _load()) {
      for (final AnimeTitle candidate in entry.titles) {
        if (target.distanceTo(candidate) == 0) {
          return entry;
        }
      }
    }
    debugPrint('bangumi-data 未收录 $title');
    return null;
  }

  static Future<List<BangumiDataEntry>> _load() {
    // A failed load is retried on the next episode rather than cached.
    return _entries ??= _readOrFetch().catchError((Object e) {
      debugPrint('加载 bangumi-data 失败 ${e.toString()}');
      return <BangumiDataEntry>[];
    }).then((entries) {
      if (entries.isEmpty) {
        _entries = null;
      }
      return entries;
    });
  }

  static Future<File> _cacheFile() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File('${dir.path}/bangumi_data_bilibili.json');
  }

  static Future<List<BangumiDataEntry>> _readOrFetch() async {
    File? cache;
    String? cached;
    try {
      cache = await _cacheFile();
      if (await cache.exists()) {
        cached = await cache.readAsString();
        final DateTime fetched = await cache.lastModified();
        if (DateTime.now().difference(fetched) < _maxAge) {
          return await Isolate.run(() => _parseCache(cached!));
        }
      }
    } catch (e) {
      debugPrint('读取 bangumi-data 缓存失败 ${e.toString()}');
    }

    final String? fresh = await _fetch();
    if (fresh != null) {
      try {
        await cache?.writeAsString(fresh);
      } catch (e) {
        debugPrint('写入 bangumi-data 缓存失败 ${e.toString()}');
      }
      return Isolate.run(() => _parseCache(fresh));
    }
    // Offline or blocked: a stale index still beats none.
    if (cached != null) {
      return Isolate.run(() => _parseCache(cached!));
    }
    return [];
  }

  /// The compact cache JSON, or null when every source failed.
  static Future<String?> _fetch() async {
    for (final String url in _sources) {
      final res = await Request().get(url,
          options: Options(
            validateStatus: (_) => true,
            extra: {'silent': true},
            receiveTimeout: const Duration(seconds: 60),
          ),
          extra: {'resType': ResponseType.bytes});
      final data = res.data;
      if (res.statusCode != 200 || data is! List<int>) {
        debugPrint('下载 bangumi-data 失败 $url HTTP ${res.statusCode}');
        continue;
      }
      try {
        return await Isolate.run(() => _compact(data));
      } catch (e) {
        debugPrint('解析 bangumi-data 失败 $url ${e.toString()}');
      }
    }
    return null;
  }

  /// Keeps only what the Bilibili lookup needs: [[titles...], [mediaIds...]].
  static String _compact(List<int> bytes) {
    final Map<String, dynamic> data = jsonDecode(utf8.decode(bytes));
    final List<List<List<Object>>> out = [];
    for (final item in data['items'] as List) {
      final List<int> ids = [];
      final List sites = item['sites'] ?? const [];
      for (final String site in _bilibiliSites) {
        for (final s in sites) {
          final int? id = int.tryParse('${s['id']}');
          if (s['site'] == site && id != null) {
            ids.add(id);
          }
        }
      }
      if (ids.isEmpty) {
        continue;
      }
      final Map translations = item['titleTranslate'] ?? const {};
      final List<String> titles = [
        for (final String lang in ['zh-Hant', 'zh-Hans'])
          for (final t in (translations[lang] as List? ?? const [])) '$t',
        '${item['title']}',
      ];
      out.add([titles, ids]);
    }
    return jsonEncode(out);
  }

  static List<BangumiDataEntry> _parseCache(String json) {
    return [
      for (final item in jsonDecode(json) as List)
        BangumiDataEntry(
          [for (final t in item[0] as List) AnimeTitle.parse('$t')],
          [for (final id in item[1] as List) id as int],
        ),
    ];
  }
}
