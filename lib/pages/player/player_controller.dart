import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:mobx/mobx.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:oneanime/bean/danmaku/danmaku_module.dart';
import 'package:oneanime/bean/danmaku/danmaku_settings.dart';
import 'package:oneanime/utils/constans.dart';
import 'package:oneanime/utils/font_manager.dart';
import 'package:oneanime/utils/storage.dart';
import 'package:hive/hive.dart';
import 'package:oneanime/utils/utils.dart';
import 'package:oneanime/pages/video/video_controller.dart' as video_page;

part 'player_controller.g.dart';

/// How the picture is fitted into the player.
enum VideoFitMode {
  contain('自适应', BoxFit.contain, null),
  cover('填充裁剪', BoxFit.cover, null),
  fill('拉伸铺满', BoxFit.fill, null),
  ratio16x9('16:9', BoxFit.contain, 16 / 9),
  ratio4x3('4:3', BoxFit.contain, 4 / 3);

  const VideoFitMode(this.label, this.fit, this.aspectRatio);

  final String label;
  final BoxFit fit;
  final double? aspectRatio;
}

class PlayerController = _PlayerController with _$PlayerController;

abstract class _PlayerController with Store {
  String videoUrl = '';
  String videoCookie = '';
  bool playResume = false;
  Box setting = GStorage.setting;
  late Player mediaPlayer;
  late VideoController videoController;
  bool _hasPlayer = false;

  /// Created by the danmaku layer, which may not be built yet.
  DanmakuController? danmakuController;

  DanmakuSettings danmakuSettings = DanmakuSettings.load();

  final ValueNotifier<VideoFitMode> fitMode =
      ValueNotifier(VideoFitMode.contain);

  /// Minutes the sleep timer was set to, null when it is off.
  final ValueNotifier<int?> sleepMinutes = ValueNotifier(null);
  Timer? _sleepTimer;

  final List<StreamSubscription> _subscriptions = [];

  /// Bumped on every seek or reload so danmaku scheduled for the old
  /// position are dropped instead of drawn late.
  int _danmakuGeneration = 0;
  int _lastDanmakuSecond = -1;

  bool _completedHandled = false;
  String _lastError = '';
  DateTime _lastErrorAt = DateTime.fromMillisecondsSinceEpoch(0);

  // 当前播放器状态
  @observable
  late String dataStatus;

  video_page.VideoController get _page =>
      Modular.get<video_page.VideoController>();

  @action
  Future init(int offset) async {
    dataStatus = 'loading';
    playResume = setting.get(SettingBoxKey.playResume, defaultValue: false);
    final int fitIndex = setting.get(SettingBoxKey.videoFit, defaultValue: 0);
    fitMode.value = VideoFitMode
        .values[fitIndex.clamp(0, VideoFitMode.values.length - 1)];
    await _disposePlayer();
    debugPrint('VideoURL开始初始化');
    _completedHandled = false;
    _resetDanmakuFeed();
    mediaPlayer = await createVideoController(offset: offset);
    debugPrint('VideoURL初始化完成');
    dataStatus = 'loaded';
  }

  Future<void> _disposePlayer() async {
    for (final StreamSubscription s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    if (_hasPlayer) {
      _hasPlayer = false;
      try {
        await mediaPlayer.dispose();
        debugPrint('释放旧的 player');
      } catch (e) {
        debugPrint('释放 player 失败 ${e.toString()}');
      }
    }
  }

  void dispose() {
    cancelSleepTimer();
    _resetDanmakuFeed();
    _disposePlayer();
  }

  Future<Player> createVideoController({int offset = 0}) async {
    var httpHeaders = {
      'user-agent': Utils.getRandomUA(),
      'referer': HttpString.baseUrl,
      'Cookie': videoCookie,
    };
    bool hAenable = setting.get(SettingBoxKey.HAenable, defaultValue: true);
    bool aotoPlay = setting.get(SettingBoxKey.autoPlay, defaultValue: true);
    mediaPlayer = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    _hasPlayer = true;

    var pp = mediaPlayer.platform as NativePlayer;
    // media-kit 默认启用硬盘作为双重缓存，这可以维持大缓存的前提下减轻内存压力
    // media-kit 内部硬盘缓存目录按照 Linux 配置，这导致该功能在其他平台上被损坏
    // 该设置可以在所有平台上正确启用双重缓存
    await pp.setProperty("demuxer-cache-dir", await Utils.getPlayerTempPath());
    await pp.setProperty("af", "scaletempo2=max-speed=8");
    // 网络抖动时自动重连, 避免播放到一半直接中断
    await pp.setProperty("stream-lavf-o",
        "reconnect=1,reconnect_streamed=1,reconnect_delay_max=5");
    if (Platform.isAndroid) {
      await pp.setProperty("volume-max", "100");
      await pp.setProperty("ao", "opensles");
    }

    await mediaPlayer.setAudioTrack(
      AudioTrack.auto(),
    );

    videoController = VideoController(
      mediaPlayer,
      configuration: (Platform.isAndroid && hAenable)
          ? const VideoControllerConfiguration(
              vo: 'mediacodec_embed',
              hwdec: 'mediacodec',
              androidAttachSurfaceAfterVideoParameters: false,
            )
          : VideoControllerConfiguration(
              enableHardwareAcceleration: hAenable,
              hwdec: hAenable ? null : 'no',
              androidAttachSurfaceAfterVideoParameters: false,
            ),
    );
    mediaPlayer.setPlaylistMode(PlaylistMode.none);
    _listen(mediaPlayer);

    await mediaPlayer.open(
      Media(videoUrl,
          start: Duration(seconds: offset), httpHeaders: httpHeaders),
      play: aotoPlay,
    );
    final double speed = _page.playerSpeed;
    if (speed != 1.0) {
      await mediaPlayer.setRate(speed);
    }
    return mediaPlayer;
  }

  void _listen(Player player) {
    final video_page.VideoController page = _page;
    _subscriptions.addAll([
      player.stream.playing.listen((playing) {
        page.playing = playing;
        if (playing) {
          danmakuController?.resume();
        } else {
          danmakuController?.pause();
        }
      }),
      player.stream.buffering.listen((buffering) {
        page.isBuffering = buffering;
      }),
      player.stream.position.listen(_onPosition),
      player.stream.buffer.listen((buffer) {
        page.buffer = buffer;
      }),
      player.stream.duration.listen((duration) {
        page.duration = duration;
      }),
      player.stream.completed.listen(_onCompleted),
      player.stream.error.listen(_onError),
    ]);
  }

  void _onPosition(Duration position) {
    final video_page.VideoController page = _page;
    // The stream ticks far faster than the UI needs; every update rebuilds
    // the controls.
    if ((position - page.currentPosition).abs() >=
            const Duration(milliseconds: 200) ||
        position.inSeconds != page.currentPosition.inSeconds) {
      page.currentPosition = position;
    }
    _feedDanmaku(position);
  }

  void _onCompleted(bool completed) {
    if (!completed || _completedHandled) {
      return;
    }
    final video_page.VideoController page = _page;
    if (!setting.get(SettingBoxKey.autoNext, defaultValue: true) ||
        page.episode >= page.token.length) {
      return;
    }
    _completedHandled = true;
    SmartDialog.showToast('即将播放第 ${page.episode + 1} 话',
        displayType: SmartToastType.onlyRefresh);
    page.changeEpisode(page.episode + 1);
  }

  void _onError(String error) {
    if (error.isEmpty) {
      return;
    }
    final DateTime now = DateTime.now();
    if (error == _lastError &&
        now.difference(_lastErrorAt) < const Duration(seconds: 5)) {
      return;
    }
    _lastError = error;
    _lastErrorAt = now;
    debugPrint('播放器错误 $error $videoUrl');
    SmartDialog.showToast('播放出错: $error',
        displayType: SmartToastType.onlyRefresh);
  }

  void _resetDanmakuFeed() {
    _danmakuGeneration++;
    _lastDanmakuSecond = -1;
    danmakuController?.clear();
  }

  /// Hands the danmaku of every second the playhead entered to the danmaku
  /// layer, each delayed to its own offset inside that second.
  void _feedDanmaku(Duration position) {
    final int second = position.inSeconds;
    if (second == _lastDanmakuSecond) {
      return;
    }
    final int last = _lastDanmakuSecond;
    _lastDanmakuSecond = second;
    final video_page.VideoController page = _page;
    final DanmakuController? controller = danmakuController;
    if (controller == null || !page.danmakuOn || !mediaPlayer.state.playing) {
      return;
    }
    // After a jump only the current second is shown; replaying everything in
    // between would flood the screen.
    final int from =
        (last < 0 || second < last || second - last > 2) ? second : last + 1;
    final double rate = mediaPlayer.state.rate <= 0 ? 1 : mediaPlayer.state.rate;
    final int generation = _danmakuGeneration;
    for (int s = from; s <= second; s++) {
      final List<Danmaku>? danmakus = page.danDanmakus[s];
      if (danmakus == null) {
        continue;
      }
      for (final Danmaku danmaku in danmakus) {
        final DanmakuContentItem? item = danmakuSettings.contentOf(danmaku);
        if (item == null) {
          continue;
        }
        final int delay =
            (((danmaku.p - second).clamp(0.0, 1.0)) * 1000 / rate).round();
        Future.delayed(Duration(milliseconds: delay), () {
          if (generation != _danmakuGeneration ||
              !page.danmakuOn ||
              !_hasPlayer ||
              !mediaPlayer.state.playing ||
              page.isBuffering) {
            return;
          }
          danmakuController?.addDanmaku(item);
        });
      }
    }
  }

  /// Pushes [danmakuSettings] to the danmaku layer, optionally saving them.
  Future<void> applyDanmakuSettings({bool save = true}) async {
    await FontManager.ensureLoaded(danmakuSettings.fontFamily);
    danmakuController?.updateOption(danmakuSettings.toOption());
    if (save) {
      await danmakuSettings.save();
    }
  }

  void reloadDanmakuSettings() {
    danmakuSettings = DanmakuSettings.load();
  }

  void clearDanmaku() {
    _resetDanmakuFeed();
  }

  Future<void> setFitMode(VideoFitMode mode) async {
    fitMode.value = mode;
    await setting.put(SettingBoxKey.videoFit, mode.index);
  }

  void setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepMinutes.value = minutes;
    if (minutes == null) {
      return;
    }
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      sleepMinutes.value = null;
      _sleepTimer = null;
      if (_hasPlayer) {
        pause();
      }
      SmartDialog.showToast('定时结束，已暂停播放');
    });
  }

  void cancelSleepTimer() => setSleepTimer(null);

  Function get setRate {
    return mediaPlayer.setRate;
  }

  bool get playing {
    return _hasPlayer && mediaPlayer.state.playing;
  }

  bool get buffering {
    return mediaPlayer.state.buffering;
  }

  Duration get position {
    return mediaPlayer.state.position;
  }

  Duration get buffer {
    return mediaPlayer.state.buffer;
  }

  Duration get duration {
    return mediaPlayer.state.duration;
  }

  bool get completed {
    return mediaPlayer.state.completed;
  }

  Future seek(Duration duration) async {
    if (!_hasPlayer) {
      return;
    }
    final Duration total = mediaPlayer.state.duration;
    Duration target = duration < Duration.zero ? Duration.zero : duration;
    if (total > Duration.zero && target > total) {
      target = total;
    }
    _resetDanmakuFeed();
    _page.currentPosition = target;
    await mediaPlayer.seek(target);
  }

  Future seekBy(Duration delta) async {
    if (!_hasPlayer) {
      return;
    }
    await seek(mediaPlayer.state.position + delta);
  }

  Future pause() async {
    danmakuController?.pause();
    if (_hasPlayer) {
      await mediaPlayer.pause();
    }
  }

  Future play() async {
    danmakuController?.resume();
    if (_hasPlayer) {
      await mediaPlayer.play();
    }
  }

  Future playOrPause() async {
    if (playing) {
      await pause();
    } else {
      await play();
    }
  }
}
