import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:oneanime/request/request.dart';
import 'package:oneanime/request/api.dart';
import 'package:flutter/material.dart' as material;
import 'package:oneanime/bean/danmaku/danmaku_module.dart';
import 'package:oneanime/utils/anime_title.dart';
import 'package:oneanime/utils/utils.dart';
import 'package:oneanime/utils/mortis.dart';

/// 弹弹Play rejected the app credentials, so no danmaku can load at all.
class DanmakuAuthException implements Exception {
  final String reason;

  DanmakuAuthException(this.reason);

  @override
  String toString() => 'DanmakuAuthException: $reason';
}

class DanmakuRequest {
  /// Request.get() reports network failures as a normal response carrying
  /// {'message': ...}, and the APIs may answer with HTML, so a response body is
  /// never cast directly.
  static Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        material.debugPrint('响应不是合法 JSON ${e.toString()}');
      }
    }
    return <String, dynamic>{};
  }

  static List<dynamic> _asJsonList(dynamic data) =>
      (data is List) ? data : <dynamic>[];

  static String _errorOf(Map<String, dynamic> json) =>
      (json['errorMessage'] ?? json['message'] ?? '').toString();

  /// 弹弹Play signs the path only, never the query string.
  static Future<Map<String, dynamic>> _dandanGet(String path,
      {Map<String, String>? query}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final res = await Request().get(Api.dandanAPIDomain + path,
        data: query,
        options: Options(
            // Status codes are checked here, so a rejected signature is not
            // reported as a generic "Server error" toast.
            validateStatus: (_) => true,
            extra: {
              'silent': true
            },
            headers: {
              'user-agent': Utils.getRandomUA(),
              'referer': '',
              'X-Auth': 1,
              'X-AppId': mortis['id'],
              'X-Timestamp': timestamp.toString(),
              'X-Signature': Utils.generateDandanSignature(path, timestamp),
            }));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw DanmakuAuthException(
          res.headers.value('x-error-message') ?? 'HTTP ${res.statusCode}');
    }
    return _asJsonMap(res.data);
  }

  /// 弹弹Play anime id for [title], or null when the keyword search misses.
  static Future<int?> getDandanAnimeId(String title) async {
    final jsonData =
        await _dandanGet(Api.dandanAPISearch, query: {'keyword': title});
    // 8692 is 刀剑神域, the earliest bangumi carried by Anime1.
    int? animeId;
    for (final anime in _asJsonList(jsonData['animes'])) {
      final id = _asJsonMap(anime)['animeId'];
      if (id is int && id >= 8692 && (animeId == null || id < animeId)) {
        animeId = id;
      }
    }
    if (animeId == null) {
      material.debugPrint('弹弹Play 搜索 $title 无结果 ${_errorOf(jsonData)}');
    }
    return animeId;
  }

  /// 弹弹Play anime id mapped from a Bangumi.tv subject, or null when 弹弹Play
  /// has not mapped that subject yet.
  static Future<int?> getDandanAnimeIdByBgmId(int subjectId) async {
    final jsonData =
        await _dandanGet(Api.dandanAPIBgmtv + subjectId.toString());
    final animeId = _asJsonMap(jsonData['bangumi'])['animeId'];
    if (animeId is! int) {
      material
          .debugPrint('弹弹Play 未收录 Bangumi 条目 $subjectId ${_errorOf(jsonData)}');
      return null;
    }
    return animeId;
  }

  /// Bangumi.tv subject id for [title], or null when the search misses.
  static Future<int?> getBgmSubjectId(String title) async {
    final res =
        await Request().get(Api.bangumiSearch + Uri.encodeComponent(title),
            data: {'type': '2', 'responseGroup': 'small'},
            options: Options(headers: {
              // UA format required by the Bangumi API docs.
              'user-agent':
                  'Predidit/oneAnime/${Api.version} (Android) (${Api.sourceUrl})',
              'referer': '',
            }));
    final list = _asJsonList(_asJsonMap(res.data)['list']);
    final id = list.isEmpty ? null : _asJsonMap(list.first)['id'];
    if (id is! int) {
      material.debugPrint('Bangumi 搜索 $title 无结果');
      return null;
    }
    return id;
  }

  static Future<Map<String, dynamic>> _bahaGet(
      String url, Map<String, String> query) async {
    final res = await Request().get(url,
        data: query,
        options: Options(validateStatus: (_) => true, extra: {
          'silent': true
        }, headers: {
          'user-agent': Utils.getRandomUA(),
          'referer': 'https://ani.gamer.com.tw/',
        }));
    if (res.statusCode != 200) {
      material.debugPrint('巴哈姆特请求失败 $url HTTP ${res.statusCode}');
      return <String, dynamic>{};
    }
    return _asJsonMap(res.data);
  }

  /// 巴哈姆特 video_sn of any episode of the anime titled [title]. Both sites
  /// use traditional Chinese titles but write seasons differently, and the
  /// search often misses on Anime1's season markers, so it is retried without
  /// them. A hit with another name or season is a different work and ignored.
  static Future<int?> _bahaAnyVideoSn(String title) async {
    final AnimeTitle target = AnimeTitle.parse(title);
    if (target.name.isEmpty) {
      return null;
    }
    final String bare = AnimeTitle.withoutSeason(title);
    for (final String keyword in {title, if (bare.isNotEmpty) bare}) {
      final jsonData = await _bahaGet(Api.bahaSearch, {'kw': keyword});
      int? best;
      int bestDistance = 1 << 30;
      for (final item in _asJsonList(jsonData['anime'])) {
        final anime = _asJsonMap(item);
        final videoSn = anime['video_sn'];
        final int? distance = target
            .distanceTo(AnimeTitle.parse((anime['title'] ?? '').toString()));
        if (videoSn is int && distance != null && distance < bestDistance) {
          best = videoSn;
          bestDistance = distance;
        }
      }
      if (best != null) {
        return best;
      }
    }
    material.debugPrint('巴哈姆特搜索 $title 无匹配');
    return null;
  }

  /// 巴哈姆特 video_sn of [episode]. Group "0" is the main (subtitled) release,
  /// other groups are dubs or alternative cuts.
  static Future<int?> _bahaEpisodeSn(int anyVideoSn, int episode) async {
    final jsonData =
        await _bahaGet(Api.bahaVideo, {'videoSn': anyVideoSn.toString()});
    final groups = _asJsonMap(
        _asJsonMap(_asJsonMap(jsonData['data'])['anime'])['episodes']);
    if (groups.isEmpty) {
      return null;
    }
    final List<dynamic> episodes =
        _asJsonList(groups['0'] ?? groups.values.first);
    for (final item in episodes) {
      final ep = _asJsonMap(item);
      if (ep['episode'] == episode && ep['videoSn'] is int) {
        return ep['videoSn'];
      }
    }
    material.debugPrint('巴哈姆特未找到第 $episode 集');
    return null;
  }

  /// Danmaku from 巴哈姆特動畫瘋, which needs no credentials. Empty when the
  /// anime or the episode is not carried there.
  static Future<List<Danmaku>> getBahaDanmaku(String title, int episode) async {
    final int? anySn = await _bahaAnyVideoSn(title);
    if (anySn == null) {
      return [];
    }
    final int? videoSn = await _bahaEpisodeSn(anySn, episode);
    if (videoSn == null) {
      return [];
    }
    final jsonData = await _bahaGet(
        Api.bahaDanmu, {'geo': 'TW,HK', 'videoSn': videoSn.toString()});
    final List<Danmaku> danmakus = [];
    for (final item in _asJsonList(_asJsonMap(jsonData['data'])['danmu'])) {
      final danmu = _asJsonMap(item);
      final text = danmu['text'];
      final time = danmu['time'];
      if (text is! String || text.isEmpty || time is! num) {
        continue;
      }
      final String color = (danmu['color'] ?? '').toString();
      danmakus.add(Danmaku(
        // Tenths of a second.
        p: time / 10,
        m: text,
        // 巴哈姆特 positions: 0 scrolling, 1 top, 2 bottom.
        mode: switch (danmu['position']) { 1 => 5, 2 => 4, _ => 1 },
        color: (color.startsWith('#')
                ? int.tryParse(color.substring(1), radix: 16)
                : null) ??
            0xFFFFFF,
      ));
    }
    material.debugPrint('巴哈姆特弹幕 $videoSn 共 ${danmakus.length} 条');
    return danmakus;
  }

  /// Danmaku for one episode. Episode ids are the anime id followed by the
  /// 4 digit episode number (anime 1758 episode 1 -> 17580001); the rule is
  /// undocumented but every episode list the API publishes agrees with it.
  static Future<List<Danmaku>> getDanmaku(int animeId, int episode) async {
    final int episodeId = animeId * 10000 + episode;
    final jsonData = await _dandanGet(
        Api.dandanAPIComment + episodeId.toString(),
        query: {'withRelated': 'true'});
    final comments = _asJsonList(jsonData['comments']);
    if (comments.isEmpty) {
      material.debugPrint('弹幕库 $episodeId 为空 ${_errorOf(jsonData)}');
    }
    final List<Danmaku> danmakus = [];
    for (final comment in comments) {
      try {
        danmakus.add(Danmaku.fromJson(Map<String, dynamic>.from(comment)));
      } catch (e) {
        material.debugPrint('弹幕解析失败 ${e.toString()}');
      }
    }
    return danmakus;
  }
}
