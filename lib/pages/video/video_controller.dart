import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:mobx/mobx.dart';
import 'package:oneanime/pages/popular/popular_controller.dart';
import 'package:oneanime/request/video.dart';
import 'package:oneanime/pages/player/player_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:oneanime/request/danmaku.dart';
import 'package:oneanime/bean/danmaku/danmaku_module.dart';
import 'package:oneanime/bean/danmaku/danmaku_source.dart';
import 'package:oneanime/utils/storage.dart';
import 'package:hive/hive.dart';

part 'video_controller.g.dart';

class VideoController = _VideoController with _$VideoController;

abstract class _VideoController with Store {
  @observable
  List<String> token = [];

  /// Bumped by every danmaku load; a load holding a stale id lost the race to a
  /// newer episode and must not write into [danDanmakus].
  int _danmakuRequestId = 0;

  @observable
  Map<int, List<Danmaku>> danDanmakus = {};

  @observable
  bool playing = false;
  @observable
  bool isBuffering = true;
  @observable
  Duration currentPosition = Duration.zero;
  @observable
  Duration buffer = Duration.zero;
  @observable
  Duration duration = Duration.zero;

  // (弃用) 播放器状态监听 media_kit 的流监听似乎存在问题
  // late StreamSubscription<bool>? playingSubscription;
  // late StreamSubscription<Duration>? postionSubscription;
  // late StreamSubscription<Duration>? bufferSubscription;
  // late StreamSubscription<Duration>? durationSubscription;

  @observable
  int episode = 1;

  // 弹幕开关
  @observable
  bool danmakuOn = false;

  // 视频音量/亮度
  @observable
  double volume = 0;
  @observable
  double brightness = 0;

  // 播放器倍速
  @observable
  double playerSpeed = 1.0;

  String videoUrl = '';
  String videoCookie = '';
  String title = '';
  int link = 0;
  int offset = 0;

  @observable
  bool follow = false;

  Box setting = GStorage.setting;

  Future setPlaybackSpeed(double playerSpeed) async {
    final PlayerController playerController = Modular.get<PlayerController>();
    try {
      playerController.setRate(playerSpeed);
    } catch (e) {
      debugPrint(e.toString());
    }
    this.playerSpeed = playerSpeed;
  }

  bool _changingEpisode = false;

  Future changeEpisode(int episode) async {
    if (_changingEpisode || episode < 1 || episode > token.length) {
      return;
    }
    _changingEpisode = true;
    try {
      final PlayerController playerController = Modular.get<PlayerController>();
      final PopularController popularController =
          Modular.get<PopularController>();
      popularController.updateAnimeProgress(episode, title);
      var result =
          await VideoRequest.getVideoLink(token[token.length - episode]);
      videoUrl = result['link'];
      videoCookie = result['cookie'];
      playerController.videoUrl = videoUrl;
      playerController.videoCookie = videoCookie;
      this.episode = episode;
      playing = false;
      currentPosition = Duration.zero;
      buffer = Duration.zero;
      duration = Duration.zero;
      // Loading must not block the switch, so an enclosing try/catch cannot help.
      unawaited(getDanDanmaku(title, episode).catchError((e) {
        debugPrint('弹幕加载错误 ${e.toString()}');
      }));
      // The chosen speed carries over to the next episode.
      await playerController.init(0);
    } catch (e) {
      debugPrint('切换剧集失败 ${e.toString()}');
      SmartDialog.showToast('切换剧集失败，请稍后重试');
    } finally {
      _changingEpisode = false;
    }
  }

  void _addDanmakus(List<Danmaku> danmakus) {
    for (final danmaku in danmakus) {
      danDanmakus.putIfAbsent(danmaku.p.toInt(), () => []).add(danmaku);
    }
  }

  final ValueNotifier<DanmakuLoadState> danmakuLoadState =
      ValueNotifier(const DanmakuLoadState.done([], 0));

  /// A source picked in the player for the rest of this viewing, overriding
  /// the configured ones; null follows the settings.
  DanmakuSource? danmakuSourceOverride;

  /// Loads from the configured sources in priority order: by default the
  /// first one that has the episode wins, or with merging on, all of them
  /// are combined with duplicates dropped (弹弹Play itself relays 巴哈姆特
  /// and Bilibili, so the same danmaku can arrive twice).
  Future<void> getDanDanmaku(String title, int episode) async {
    final int requestId = ++_danmakuRequestId;
    danDanmakus.clear();
    danmakuLoadState.value = const DanmakuLoadState.loading();

    final DanmakuSourceSettings config = DanmakuSourceSettings.load();
    final DanmakuSource? override = danmakuSourceOverride;
    final List<DanmakuSource> sources =
        override != null ? [override] : config.active;
    final List<DanmakuSource> used = [];
    final List<Danmaku> res = [];
    if (override == null && config.merge) {
      final List<List<Danmaku>> results = await Future.wait(
          sources.map((source) => _danmakuFrom(source, title, episode)));
      final Set<String> seen = {};
      for (int i = 0; i < sources.length; i++) {
        if (results[i].isEmpty) {
          continue;
        }
        used.add(sources[i]);
        for (final Danmaku danmaku in results[i]) {
          if (seen.add('${danmaku.p.round()}|${danmaku.m}')) {
            res.add(danmaku);
          }
        }
      }
    } else {
      for (final DanmakuSource source in sources) {
        final List<Danmaku> danmakus =
            await _danmakuFrom(source, title, episode);
        if (danmakus.isNotEmpty) {
          used.add(source);
          res.addAll(danmakus);
          break;
        }
      }
    }
    if (requestId != _danmakuRequestId) {
      return;
    }
    _addDanmakus(res);
    danmakuLoadState.value = DanmakuLoadState.done(used, res.length);
    debugPrint('当前弹幕库 ${danDanmakus.length} 来源 $used');
    if (res.isEmpty && danmakuOn) {
      SmartDialog.showToast(sources.isEmpty ? '所有弹幕来源都已关闭' : '没有找到本集的弹幕',
          displayType: SmartToastType.onlyRefresh);
    }
  }

  Future<List<Danmaku>> _danmakuFrom(
      DanmakuSource source, String title, int episode) {
    return switch (source) {
      DanmakuSource.baha => _bahaDanmaku(title, episode),
      DanmakuSource.bilibili => _biliDanmaku(title, episode),
      DanmakuSource.dandan => _dandanDanmaku(title, episode),
    };
  }

  Future<List<Danmaku>> _bahaDanmaku(String title, int episode) async {
    try {
      return await DanmakuRequest.getBahaDanmaku(title, episode);
    } catch (e) {
      debugPrint('巴哈姆特弹幕加载失败 ${e.toString()}');
      return [];
    }
  }

  Future<List<Danmaku>> _biliDanmaku(String title, int episode) async {
    try {
      return await DanmakuRequest.getBiliDanmaku(title, episode);
    } catch (e) {
      debugPrint('B站弹幕加载失败 ${e.toString()}');
      return [];
    }
  }

  Future<List<Danmaku>> _dandanDanmaku(String title, int episode) async {
    try {
      final int? animeId = await DanmakuRequest.getDandanAnimeId(title);
      List<Danmaku> res = await _danmakuOf(animeId, episode);
      if (res.isEmpty &&
          setting.get(SettingBoxKey.danmakuEnhance, defaultValue: true)) {
        res = await _danmakuOf(await _bgmAnimeId(title), episode);
      }
      return res;
    } on DanmakuAuthException catch (e) {
      debugPrint('弹弹Play 认证失败 ${e.reason}');
    } catch (e) {
      debugPrint('弹弹Play 弹幕加载失败 ${e.toString()}');
    }
    return [];
  }

  Future<List<Danmaku>> _danmakuOf(int? animeId, int episode) async {
    if (animeId == null) {
      return [];
    }
    return DanmakuRequest.getDanmaku(animeId, episode);
  }

  /// The 弹弹Play keyword search misses many of the traditional Chinese titles
  /// Anime1 uses, so resolve those on Bangumi.tv and let 弹弹Play map the
  /// subject onto its own anime id.
  Future<int?> _bgmAnimeId(String title) async {
    String simplified = title;
    try {
      simplified = await Modular.get<PopularController>().chineseTW2S(title);
    } catch (e) {
      debugPrint('内部翻译错误 ${e.toString()}');
    }
    final int? subjectId = await DanmakuRequest.getBgmSubjectId(simplified);
    if (subjectId == null) {
      return null;
    }
    return DanmakuRequest.getDandanAnimeIdByBgmId(subjectId);
  }
}
