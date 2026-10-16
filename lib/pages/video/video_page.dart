import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:oneanime/pages/history/history_controller.dart';
import 'package:oneanime/pages/video/video_controller.dart';
import 'package:oneanime/pages/player/player_controller.dart';
import 'package:oneanime/pages/player/player_item.dart';
import 'package:oneanime/pages/player/player_overlay.dart';
import 'package:oneanime/bean/anime/anime_panel.dart';
import 'package:oneanime/utils/font_manager.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:hive/hive.dart';
import 'package:oneanime/utils/storage.dart';
import 'package:oneanime/utils/utils.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with WindowListener, WidgetsBindingObserver {
  Box setting = GStorage.setting;
  final FocusNode _focusNode = FocusNode();
  final VideoController videoController = Modular.get<VideoController>();
  final PlayerController playerController = Modular.get<PlayerController>();
  final HistoryController historyController = Modular.get<HistoryController>();

  /// Keeps the player, danmaku and controls alive while the layout switches
  /// between portrait and fullscreen.
  final GlobalKey _playerKey = GlobalKey();
  final GlobalKey<PlayerOverlayState> _overlayKey = GlobalKey();

  bool isPopping = false;

  /// Kept free for the episode panel, which cannot shrink below its header.
  static const double _minPanelExtent = 200;

  bool _windowFullscreen = false;
  Orientation? _syncedOrientation;

  /// Never stored on mobile, orientation is the single source of truth, so
  /// leaving fullscreen cannot feed back into the rotation that derives it.
  bool get isFullscreen => Utils.isDesktop()
      ? _windowFullscreen
      : MediaQuery.orientationOf(context) == Orientation.landscape;

  Future<void> _handleFullscreen() async {
    if (!Utils.isDesktop()) {
      await (isFullscreen ? Utils.verticalScreen() : Utils.landScape());
      return;
    }
    setState(() {
      _windowFullscreen = !_windowFullscreen;
    });
    await _applyFullscreen(_windowFullscreen);
  }

  Future<void> _applyFullscreen(bool fullscreen) async {
    if (!fullscreen) {
      playerController.clearDanmaku();
    }
    await Utils.setFullScreen(fullscreen);
  }

  /// The layout follows [MediaQuery] on its own; this only carries the
  /// imperative side effects, skipped unless the orientation really changed.
  void _syncFullscreenWithOrientation() {
    if (Utils.isDesktop() || !mounted) {
      return;
    }
    final Orientation orientation =
        MediaQueryData.fromView(View.of(context)).orientation;
    if (orientation == _syncedOrientation) {
      return;
    }
    _syncedOrientation = orientation;
    _applyFullscreen(orientation == Orientation.landscape);
  }

  /// Phones keep the rest of the app portrait; tablets get the orientation
  /// handed back instead of being forced upright.
  void _restoreSystemUi() {
    Utils.setFullScreen(false);
    if (Utils.isDesktop()) {
      return;
    }
    if (Utils.isTablet()) {
      Utils.unlockOrientation();
    } else {
      Utils.verticalScreen();
    }
  }

  /// 处理 Windows 重新前台
  @override
  void onWindowRestore() {
    playerController.clearDanmaku();
  }

  @override
  void didChangeMetrics() {
    _syncFullscreenWithOrientation();
  }

  /// 处理 Android/iOS 应用后台或熄屏
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      playerController.pause();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _syncFullscreenWithOrientation();
    });
    if (Utils.isDesktop()) {
      windowManager.addListener(this);
      if (setting.get(SettingBoxKey.alwaysOntop, defaultValue: true)) {
        windowManager.setAlwaysOnTop(true);
      }
    }
    init();
  }

  void init() async {
    videoController.danmakuOn =
        setting.get(SettingBoxKey.danmakuEnabledByDefault, defaultValue: false);
    playerController.reloadDanmakuSettings();
    // 播放器初始化
    videoController.playerSpeed = 1.0;
    playerController.videoUrl = videoController.videoUrl;
    playerController.videoCookie = videoController.videoCookie;
    await playerController.init(videoController.offset);
    videoController.offset = 0;
    // An imported font has to be registered before danmaku are drawn with it.
    await FontManager.ensureLoaded(playerController.danmakuSettings.fontFamily);
    await playerController.applyDanmakuSettings(save: false);
    try {
      await videoController.getDanDanmaku(
          videoController.title, videoController.episode);
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    try {
      historyController.updateHistory(
          videoController.link, videoController.currentPosition.inSeconds);
    } catch (e) {
      debugPrint(e.toString());
    }
    videoController.playing = false;
    videoController.currentPosition = Duration.zero;
    videoController.duration = Duration.zero;
    _restoreSystemUi();
    // Gesture brightness only applies while watching.
    ScreenBrightness()
        .resetApplicationScreenBrightness()
        .catchError((Object _) {});
    if (Utils.isDesktop()) {
      windowManager.setAlwaysOnTop(false);
      windowManager.removeListener(this);
    }
    playerController.danmakuController = null;
    playerController.dispose();
    super.dispose();
  }

  void onBackPressed() {
    if (_overlayKey.currentState?.dismissPanel() ?? false) {
      return;
    }
    // A tablet in landscape is always fullscreen, so there is nothing to leave.
    if (isFullscreen && !Utils.isTablet()) {
      _handleFullscreen();
      return;
    }
    if (!isPopping) {
      isPopping = true;
      _restoreSystemUi();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      final bool fullscreen = isFullscreen;
      final Widget player = playerBody(fullscreen);
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, _) {
          onBackPressed();
        },
        child: Scaffold(
          backgroundColor: fullscreen ? Colors.black : null,
          body: SafeArea(
            top: !fullscreen,
            bottom: !fullscreen,
            left: !fullscreen,
            right: !fullscreen,
            child: fullscreen
                ? SizedBox.expand(child: player)
                : LayoutBuilder(builder: (context, constraints) {
                    return Column(
                      children: [
                        SizedBox(
                            height: math.min(
                                constraints.maxWidth * 9 / 16,
                                math.max(0.0,
                                    constraints.maxHeight - _minPanelExtent)),
                            width: constraints.maxWidth,
                            child: player),
                        BangumiPanel(
                          title: videoController.title,
                          episodeLength: videoController.token.length,
                          currentEpisode: videoController.episode,
                          onChangeEpisode: videoController.changeEpisode,
                        ),
                      ],
                    );
                  }),
          ),
        ),
      );
    });
  }

  Widget playerBody(bool fullscreen) {
    return Focus(
      key: _playerKey,
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        return (_overlayKey.currentState?.handleKey(event) ?? false)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            const Positioned.fill(child: PlayerItem()),
            Positioned.fill(
              child: DanmakuScreen(
                createdController: (DanmakuController e) {
                  playerController.danmakuController = e;
                  debugPrint('弹幕控制器创建成功');
                },
                option: playerController.danmakuSettings.toOption(),
              ),
            ),
            Positioned.fill(
              child: PlayerOverlay(
                key: _overlayKey,
                isFullscreen: fullscreen,
                focusNode: _focusNode,
                onBack: onBackPressed,
                onToggleFullscreen: _handleFullscreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
