import 'dart:async';
import 'dart:io';

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:hive/hive.dart';
import 'package:mobx/mobx.dart' show reaction, ReactionDisposer;
import 'package:oneanime/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:oneanime/pages/player/player_controller.dart';
import 'package:oneanime/pages/player/player_panels.dart';
import 'package:oneanime/pages/popular/popular_controller.dart';
import 'package:oneanime/pages/video/video_controller.dart';
import 'package:oneanime/i18n/strings.g.dart';
import 'package:oneanime/utils/storage.dart';
import 'package:oneanime/utils/utils.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// Controls, gestures and side panels drawn over the video.
class PlayerOverlay extends StatefulWidget {
  const PlayerOverlay({
    super.key,
    required this.isFullscreen,
    required this.onBack,
    required this.onToggleFullscreen,
    required this.focusNode,
  });

  final bool isFullscreen;
  final VoidCallback onBack;
  final VoidCallback onToggleFullscreen;
  final FocusNode focusNode;

  @override
  State<PlayerOverlay> createState() => PlayerOverlayState();
}

enum _Panel { settings, episodes }

class PlayerOverlayState extends State<PlayerOverlay> {
  final VideoController videoController = Modular.get<VideoController>();
  final PlayerController playerController = Modular.get<PlayerController>();
  final PopularController popularController = Modular.get<PopularController>();
  final Box setting = GStorage.setting;

  static const Duration _seekStep = Duration(seconds: 10);
  static const List<double> speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  bool controlsVisible = true;
  bool locked = false;
  Timer? _hideTimer;

  // 中央提示 (音量 / 亮度 / 倍速 / 进度)
  IconData? _hintIcon;
  String? _hintText;
  Timer? _hintTimer;

  // 双击快进快退的提示, -1 左侧 1 右侧
  int _doubleTapSide = 0;
  Timer? _doubleTapTimer;
  Offset _doubleTapPosition = Offset.zero;

  // 横向拖动进度
  Duration? _dragSeekTarget;
  Duration _dragSeekStart = Duration.zero;
  double _dragSeekDx = 0;
  bool _wasPlayingBeforeDrag = false;

  // 纵向拖动亮度 / 音量
  bool _verticalOnLeft = false;
  double _verticalStartValue = 0;
  double _verticalDy = 0;

  bool _longPressing = false;

  _Panel? _panel;

  late final ReactionDisposer _playingReaction;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    try {
      FlutterVolumeController.updateShowSystemUI(false);
    } catch (_) {}
    // Controls stay up while paused and fade out once playback (re)starts.
    _playingReaction = reaction((_) => videoController.playing, (_) {
      if (mounted && _panel == null) {
        showControls();
      }
    });
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant PlayerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFullscreen != widget.isFullscreen) {
      // Side panels only exist in fullscreen; portrait uses bottom sheets.
      _panel = null;
      if (!widget.isFullscreen) {
        locked = false;
      }
    }
  }

  @override
  void dispose() {
    _playingReaction();
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _doubleTapTimer?.cancel();
    if (_longPressing) {
      _restoreSpeed();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- 显隐

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _panel != null) {
        return;
      }
      // Paused video keeps its controls, so the user can always find play.
      if (!playerController.playing && !locked) {
        return;
      }
      setState(() => controlsVisible = false);
    });
  }

  void showControls() {
    if (!controlsVisible) {
      setState(() => controlsVisible = true);
    }
    _scheduleHide();
  }

  void _toggleControls() {
    if (controlsVisible) {
      _hideTimer?.cancel();
      setState(() => controlsVisible = false);
    } else {
      showControls();
    }
  }

  void _showHint(IconData icon, String text, {bool sticky = false}) {
    _hintTimer?.cancel();
    setState(() {
      _hintIcon = icon;
      _hintText = text;
    });
    if (!sticky) {
      _hintTimer = Timer(const Duration(milliseconds: 900), _clearHint);
    }
  }

  void _clearHint() {
    _hintTimer?.cancel();
    if (mounted && _hintText != null) {
      setState(() {
        _hintIcon = null;
        _hintText = null;
      });
    }
  }

  // ---------------------------------------------------------------- 播放操作

  void togglePlay() {
    playerController.playOrPause();
    showControls();
  }

  void seekBy(Duration delta) {
    playerController.seekBy(delta);
    final bool forward = delta > Duration.zero;
    _showHint(forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
        '${forward ? '快进' : '快退'} ${delta.inSeconds.abs()} 秒');
  }

  void skipOp() {
    final int seconds =
        (setting.get(SettingBoxKey.skipOpSeconds, defaultValue: 85) as num)
            .toInt();
    seekBy(Duration(seconds: seconds));
  }

  Future<void> setSpeed(double speed) async {
    await videoController.setPlaybackSpeed(speed);
    _showHint(Icons.speed_rounded, '${speed}x');
  }

  void toggleDanmaku() {
    if (videoController.danDanmakus.isEmpty) {
      SmartDialog.showToast('当前剧集没有找到弹幕的说',
          displayType: SmartToastType.onlyRefresh);
      return;
    }
    playerController.clearDanmaku();
    videoController.danmakuOn = !videoController.danmakuOn;
    _showHint(
        videoController.danmakuOn
            ? Icons.subtitles_rounded
            : Icons.subtitles_off_rounded,
        videoController.danmakuOn ? '弹幕已开启' : '弹幕已关闭');
  }

  void nextEpisode() {
    if (videoController.episode >= videoController.token.length) {
      SmartDialog.showToast('已经是最新一集',
          displayType: SmartToastType.onlyRefresh);
      return;
    }
    SmartDialog.showToast('第 ${videoController.episode + 1} 话',
        displayType: SmartToastType.onlyRefresh);
    videoController.changeEpisode(videoController.episode + 1);
  }

  void _toggleFollow() {
    final Translations i18n = Translations.of(context);
    popularController.updateFollow(
        videoController.link, !(videoController.follow));
    videoController.follow = !videoController.follow;
    SmartDialog.showToast(
        videoController.follow
            ? i18n.toast.favoriteToast
            : i18n.toast.dismissFavorite,
        displayType: SmartToastType.onlyRefresh);
  }

  Future<double> _currentVolume() async {
    try {
      return (await FlutterVolumeController.getVolume()) ??
          videoController.volume;
    } catch (_) {
      return videoController.volume;
    }
  }

  Future<void> setVolume(double value) async {
    final double v = value.clamp(0.0, 1.0);
    videoController.volume = v;
    _showHint(v == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        '${(v * 100).round()}%');
    try {
      await FlutterVolumeController.setVolume(v);
    } catch (_) {}
  }

  Future<void> changeVolumeBy(double delta) async {
    await setVolume((await _currentVolume()) + delta);
  }

  Future<double> _currentBrightness() async {
    try {
      return await ScreenBrightness().application;
    } catch (_) {
      return videoController.brightness;
    }
  }

  Future<void> _setBrightness(double value) async {
    final double v = value.clamp(0.0, 1.0);
    videoController.brightness = v;
    _showHint(Icons.brightness_6_rounded, '${(v * 100).round()}%');
    try {
      await ScreenBrightness().setApplicationScreenBrightness(v);
    } catch (_) {}
  }

  void _restoreSpeed() {
    try {
      playerController.setRate(videoController.playerSpeed);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 键盘

  /// Handles a key press for the player; returns whether it was consumed.
  bool handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      togglePlay();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      seekBy(_seekStep);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      seekBy(-_seekStep);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      changeVolumeBy(0.1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      changeVolumeBy(-0.1);
    } else if (key == LogicalKeyboardKey.escape) {
      if (_panel != null) {
        setState(() => _panel = null);
      } else if (widget.isFullscreen) {
        widget.onToggleFullscreen();
      }
    } else if (key == LogicalKeyboardKey.keyF) {
      widget.onToggleFullscreen();
    } else if (key == LogicalKeyboardKey.keyD) {
      toggleDanmaku();
    } else if (key == LogicalKeyboardKey.keyN) {
      nextEpisode();
    } else {
      return false;
    }
    showControls();
    return true;
  }

  void handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      changeVolumeBy(-event.scrollDelta.dy / 1000);
    }
  }

  // ---------------------------------------------------------------- 面板

  void openSettings() {
    if (widget.isFullscreen) {
      _hideTimer?.cancel();
      setState(() {
        _panel = _Panel.settings;
        controlsVisible = false;
      });
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: const PlayerSettingsPanel(),
      ),
    ).whenComplete(() => widget.focusNode.requestFocus());
  }

  void openEpisodes() {
    if (widget.isFullscreen) {
      _hideTimer?.cancel();
      setState(() {
        _panel = _Panel.episodes;
        controlsVisible = false;
      });
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: EpisodePanel(onSelected: () => Navigator.pop(context)),
      ),
    );
  }

  /// Closes the fullscreen side panel; returns false if none was open.
  bool dismissPanel() {
    if (_panel == null) {
      return false;
    }
    _closePanel();
    return true;
  }

  void _closePanel() {
    setState(() => _panel = null);
    widget.focusNode.requestFocus();
    showControls();
  }

  // ---------------------------------------------------------------- 手势

  void _onDoubleTap(double width) {
    if (locked) {
      return;
    }
    final bool sideSeek =
        setting.get(SettingBoxKey.doubleTapSeek, defaultValue: true);
    final double x = _doubleTapPosition.dx;
    int side = 0;
    if (sideSeek) {
      if (x < width / 3) {
        side = -1;
      } else if (x > width * 2 / 3) {
        side = 1;
      }
    }
    if (side == 0) {
      togglePlay();
      return;
    }
    playerController.seekBy(side > 0 ? _seekStep : -_seekStep);
    _doubleTapTimer?.cancel();
    setState(() => _doubleTapSide = side);
    _doubleTapTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _doubleTapSide = 0);
      }
    });
  }

  void _onLongPressStart() {
    if (locked || !playerController.playing) {
      return;
    }
    final double speed =
        (setting.get(SettingBoxKey.longPressSpeed, defaultValue: 2.0) as num)
            .toDouble();
    _longPressing = true;
    try {
      playerController.setRate(speed);
    } catch (_) {}
    HapticFeedback.lightImpact();
    _showHint(Icons.fast_forward_rounded, '${speed}x 倍速播放中', sticky: true);
  }

  void _onLongPressEnd() {
    if (!_longPressing) {
      return;
    }
    _longPressing = false;
    _restoreSpeed();
    _clearHint();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (locked) {
      return;
    }
    _wasPlayingBeforeDrag = playerController.playing;
    _dragSeekStart = videoController.currentPosition;
    _dragSeekDx = 0;
    _dragSeekTarget = _dragSeekStart;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double width) {
    if (locked || _dragSeekTarget == null) {
      return;
    }
    _dragSeekDx += details.delta.dx;
    // A full swipe across the player covers two minutes.
    final int deltaMs = (_dragSeekDx / width * 120000).round();
    Duration target = _dragSeekStart + Duration(milliseconds: deltaMs);
    final Duration total = videoController.duration;
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (total > Duration.zero && target > total) {
      target = total;
    }
    _dragSeekTarget = target;
    final int diff = (target - _dragSeekStart).inSeconds;
    _showHint(
      diff >= 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
      '${Utils.durationToString(target)} / ${Utils.durationToString(total)}'
      '  (${diff >= 0 ? '+' : ''}$diff 秒)',
      sticky: true,
    );
  }

  Future<void> _onHorizontalDragEnd() async {
    final Duration? target = _dragSeekTarget;
    _dragSeekTarget = null;
    _clearHint();
    if (target == null) {
      return;
    }
    await playerController.seek(target);
    if (_wasPlayingBeforeDrag && !playerController.playing) {
      playerController.play();
    }
  }

  Future<void> _onVerticalDragStart(
      DragStartDetails details, double width) async {
    if (locked) {
      return;
    }
    _verticalOnLeft = details.localPosition.dx < width / 2;
    _verticalDy = 0;
    // Start from the last known value until the platform answers.
    _verticalStartValue = _verticalOnLeft
        ? videoController.brightness
        : videoController.volume;
    _verticalStartValue = _verticalOnLeft
        ? await _currentBrightness()
        : await _currentVolume();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double height) {
    if (locked) {
      return;
    }
    _verticalDy += details.delta.dy;
    // Swiping the whole player height spans the full range.
    final double value = _verticalStartValue - _verticalDy / (height * 0.9);
    if (_verticalOnLeft) {
      _setBrightness(value);
    } else {
      setVolume(value);
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final double width = constraints.maxWidth;
      final double height = constraints.maxHeight;
      final bool showBars = controlsVisible && !locked;
      return MouseRegion(
        cursor: (widget.isFullscreen && !controlsVisible)
            ? SystemMouseCursors.none
            : SystemMouseCursors.basic,
        onHover: (_) {
          if (Utils.isDesktop()) {
            showControls();
          }
        },
        child: Listener(
          onPointerSignal: handlePointerSignal,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTapDown: (details) =>
                      _doubleTapPosition = details.localPosition,
                  onDoubleTap: () => _onDoubleTap(width),
                  onLongPressStart: (_) => _onLongPressStart(),
                  onLongPressEnd: (_) => _onLongPressEnd(),
                  onLongPressCancel: _onLongPressEnd,
                  onHorizontalDragStart: _onHorizontalDragStart,
                  onHorizontalDragUpdate: (d) =>
                      _onHorizontalDragUpdate(d, width),
                  onHorizontalDragEnd: (_) => _onHorizontalDragEnd(),
                  onHorizontalDragCancel: _onHorizontalDragEnd,
                  onVerticalDragStart: (d) => _onVerticalDragStart(d, width),
                  onVerticalDragUpdate: (d) => _onVerticalDragUpdate(d, height),
                  onVerticalDragEnd: (_) => _clearHint(),
                ),
              ),
              // 缓冲
              Positioned.fill(
                child: IgnorePointer(
                  child: Observer(builder: (context) {
                    return videoController.isBuffering
                        ? const Center(child: _BufferingIndicator())
                        : const SizedBox.shrink();
                  }),
                ),
              ),
              // 双击快进快退提示
              if (_doubleTapSide != 0)
                Positioned(
                  key: const ValueKey('doubleTap'),
                  top: 0,
                  bottom: 0,
                  left: _doubleTapSide < 0 ? 0 : null,
                  right: _doubleTapSide > 0 ? 0 : null,
                  width: width / 3,
                  child: IgnorePointer(
                    child: _DoubleTapRipple(forward: _doubleTapSide > 0),
                  ),
                ),
              // 中央提示
              if (_hintText != null)
                Positioned(
                  key: const ValueKey('hint'),
                  top: height * 0.18,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: _HintPill(icon: _hintIcon, text: _hintText!),
                    ),
                  ),
                ),
              // 顶部栏
              Positioned(
                key: const ValueKey('topBar'),
                top: 0,
                left: 0,
                right: 0,
                child: _Fade(visible: showBars, child: _buildTopBar()),
              ),
              // 底部栏
              Positioned(
                key: const ValueKey('bottomBar'),
                bottom: 0,
                left: 0,
                right: 0,
                child: _Fade(visible: showBars, child: _buildBottomBar()),
              ),
              // 暂停时的中央播放按钮
              if (showBars)
                Center(
                  key: const ValueKey('play'),
                  child: Observer(builder: (context) {
                    if (videoController.playing ||
                        videoController.isBuffering) {
                      return const SizedBox.shrink();
                    }
                    return _RoundButton(
                      icon: Icons.play_arrow_rounded,
                      size: 64,
                      onPressed: togglePlay,
                    );
                  }),
                ),
              // 锁定按钮
              if (_isMobile && widget.isFullscreen)
                Positioned(
                  key: const ValueKey('lock'),
                  left: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _Fade(
                      visible: controlsVisible,
                      child: _RoundButton(
                        icon: locked
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        size: 22,
                        onPressed: () {
                          setState(() => locked = !locked);
                          _showHint(
                              locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                              locked ? '屏幕已锁定' : '屏幕已解锁');
                          showControls();
                        },
                      ),
                    ),
                  ),
                ),
              // 全屏侧边面板
              if (_panel != null) ...[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closePanel,
                    child: const ColoredBox(color: Color(0x33000000)),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: (width * 0.45).clamp(300.0, 420.0),
                  child: _SidePanel(
                    child: _panel == _Panel.settings
                        ? const PlayerSettingsPanel()
                        : EpisodePanel(onSelected: _closePanel),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _buildTopBar() {
    final bool fullscreen = widget.isFullscreen;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          fullscreen ? 12 : 0, fullscreen ? 8 : 0, fullscreen ? 12 : 4, 16),
      child: Row(
        children: [
          IconButton(
            color: Colors.white,
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: widget.onBack,
          ),
          Expanded(
            child: dtb.DragToMoveArea(
              child: SizedBox(
                height: 40,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Observer(builder: (context) {
                    return Text(
                      fullscreen
                          ? '${videoController.title}  第 ${videoController.episode} 话'
                          : '第 ${videoController.episode} 话',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fullscreen ? 16 : 14,
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          if (fullscreen)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: _Clock(),
            ),
          Observer(builder: (context) {
            return IconButton(
              color: Colors.white,
              tooltip: '追番',
              icon: Icon(videoController.follow
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded),
              onPressed: _toggleFollow,
            );
          }),
          IconButton(
            color: Colors.white,
            tooltip: '播放设置',
            icon: const Icon(Icons.tune_rounded),
            onPressed: openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final bool fullscreen = widget.isFullscreen;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const TextStyle timeStyle = TextStyle(color: Colors.white, fontSize: 12);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(fullscreen ? 20 : 8, 20,
          fullscreen ? 20 : 8, fullscreen ? 8 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Observer(builder: (context) {
              return ProgressBar(
                timeLabelLocation: TimeLabelLocation.none,
                progress: videoController.currentPosition,
                buffered: videoController.buffer,
                total: videoController.duration,
                barHeight: 3,
                thumbRadius: 6,
                thumbGlowRadius: 16,
                progressBarColor: scheme.primary,
                thumbColor: scheme.primary,
                bufferedBarColor: Colors.white38,
                baseBarColor: Colors.white24,
                onDragStart: (_) => _hideTimer?.cancel(),
                onDragEnd: _scheduleHide,
                onSeek: (duration) {
                  playerController.seek(duration);
                  _scheduleHide();
                },
              );
            }),
          ),
          Row(
            children: [
              Observer(builder: (context) {
                return IconButton(
                  color: Colors.white,
                  icon: Icon(videoController.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  onPressed: togglePlay,
                );
              }),
              Observer(builder: (context) {
                if (videoController.episode >= videoController.token.length) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  color: Colors.white,
                  tooltip: '下一话',
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: nextEpisode,
                );
              }),
              Observer(builder: (context) {
                return Text(
                  '${Utils.durationToString(videoController.currentPosition)} / ${Utils.durationToString(videoController.duration)}',
                  style: timeStyle,
                );
              }),
              const Spacer(),
              _TextAction(
                text: '跳过片头',
                onPressed: skipOp,
              ),
              Observer(builder: (context) {
                return IconButton(
                  color: Colors.white,
                  tooltip: '弹幕开关',
                  icon: Icon(videoController.danmakuOn
                      ? Icons.subtitles_rounded
                      : Icons.subtitles_off_outlined),
                  onPressed: toggleDanmaku,
                );
              }),
              Observer(builder: (context) {
                final double speed = videoController.playerSpeed;
                return PopupMenuButton<double>(
                  tooltip: '播放速度',
                  initialValue: speed,
                  onOpened: () => _hideTimer?.cancel(),
                  onCanceled: _scheduleHide,
                  onSelected: (value) {
                    setSpeed(value);
                    _scheduleHide();
                  },
                  itemBuilder: (context) => [
                    for (final double s in speeds)
                      PopupMenuItem<double>(
                        value: s,
                        child: Text('${s}x'),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 12),
                    child: Text(
                      speed == 1.0 ? '倍速' : '${speed}x',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                );
              }),
              if (fullscreen)
                _TextAction(text: '选集', onPressed: openEpisodes),
              IconButton(
                color: Colors.white,
                tooltip: fullscreen ? '退出全屏' : '全屏',
                icon: Icon(fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded),
                onPressed: widget.onToggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wall clock for the fullscreen top bar, refreshed on the minute.
class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  void _scheduleTick() {
    final DateTime now = DateTime.now();
    _timer = Timer(Duration(seconds: 60 - now.second), () {
      if (!mounted) {
        return;
      }
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}',
      style: const TextStyle(color: Colors.white70, fontSize: 13),
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: child,
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.text, required this.onPressed});

  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(40, 40),
        textStyle: const TextStyle(fontSize: 13),
      ),
      onPressed: onPressed,
      child: Text(text),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onPressed,
    this.size = 24,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.all(size / 3),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.icon, required this.text});

  final IconData? icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
          ],
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}

class _BufferingIndicator extends StatelessWidget {
  const _BufferingIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.black38,
        shape: BoxShape.circle,
      ),
      child: const SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
      ),
    );
  }
}

class _DoubleTapRipple extends StatelessWidget {
  const _DoubleTapRipple({required this.forward});

  final bool forward;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: forward ? Alignment.centerRight : Alignment.centerLeft,
          radius: 1.2,
          colors: const [Color(0x40FFFFFF), Color(0x00FFFFFF)],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
            color: Colors.white,
            size: 36,
          ),
          Text(
            forward ? '+10 秒' : '-10 秒',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData base = Theme.of(context);
    final ThemeData dark = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: base.colorScheme.primary,
      fontFamily: base.textTheme.bodyMedium?.fontFamily,
    );
    return Theme(
      data: dark,
      child: Material(
        color: const Color(0xF2141414),
        child: SafeArea(
          left: false,
          child: child,
        ),
      ),
    );
  }
}
