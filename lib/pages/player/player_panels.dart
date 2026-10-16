import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive/hive.dart';
import 'package:oneanime/bean/danmaku/danmaku_source.dart';
import 'package:oneanime/pages/player/player_controller.dart';
import 'package:oneanime/pages/settings/danmaku_style_editor.dart';
import 'package:oneanime/pages/video/video_controller.dart';
import 'package:oneanime/utils/storage.dart';

/// Playback and danmaku options, shown as a side panel in fullscreen and as
/// a bottom sheet otherwise.
class PlayerSettingsPanel extends StatefulWidget {
  const PlayerSettingsPanel({super.key});

  @override
  State<PlayerSettingsPanel> createState() => _PlayerSettingsPanelState();
}

class _PlayerSettingsPanelState extends State<PlayerSettingsPanel> {
  final VideoController videoController = Modular.get<VideoController>();
  final PlayerController playerController = Modular.get<PlayerController>();
  final Box setting = GStorage.setting;

  static const List<double> speeds = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
    3.0
  ];
  static const List<int?> sleepChoices = [null, 15, 30, 45, 60, 90];

  Widget _title(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall!.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _wrap(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(spacing: 8, runSpacing: 4, children: children),
    );
  }

  Widget _playbackTab() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _title('播放速度'),
        Observer(builder: (context) {
          return _wrap([
            for (final double s in speeds)
              ChoiceChip(
                label: Text('${s}x'),
                selected: videoController.playerSpeed == s,
                onSelected: (_) => videoController.setPlaybackSpeed(s),
              ),
          ]);
        }),
        _title('画面比例'),
        ValueListenableBuilder<VideoFitMode>(
          valueListenable: playerController.fitMode,
          builder: (context, mode, _) {
            return _wrap([
              for (final VideoFitMode m in VideoFitMode.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: mode == m,
                  onSelected: (_) => playerController.setFitMode(m),
                ),
            ]);
          },
        ),
        _title('定时关闭'),
        ValueListenableBuilder<int?>(
          valueListenable: playerController.sleepMinutes,
          builder: (context, minutes, _) {
            return _wrap([
              for (final int? m in sleepChoices)
                ChoiceChip(
                  label: Text(m == null ? '不开启' : '$m 分钟'),
                  selected: minutes == m,
                  onSelected: (_) => playerController.setSleepTimer(m),
                ),
            ]);
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('自动连播'),
          subtitle: const Text('播放结束后自动播放下一话'),
          value: setting.get(SettingBoxKey.autoNext, defaultValue: true),
          onChanged: (value) async {
            await setting.put(SettingBoxKey.autoNext, value);
            setState(() {});
          },
        ),
        SwitchListTile(
          title: const Text('双击两侧快退 / 快进'),
          subtitle: const Text('关闭后双击任意位置暂停'),
          value: setting.get(SettingBoxKey.doubleTapSeek, defaultValue: true),
          onChanged: (value) async {
            await setting.put(SettingBoxKey.doubleTapSeek, value);
            setState(() {});
          },
        ),
        ListTile(
          leading: const Icon(Icons.refresh_rounded),
          title: const Text('重新加载视频'),
          subtitle: const Text('画面卡住或加载失败时可以试试'),
          onTap: () {
            playerController.init(videoController.currentPosition.inSeconds);
          },
        ),
      ],
    );
  }

  /// Reloads the current episode from [source], or from the configured
  /// sources when null. The choice holds for later episodes too, until the
  /// player is closed.
  void _switchDanmakuSource(DanmakuSource? source) {
    setState(() => videoController.danmakuSourceOverride = source);
    playerController.clearDanmaku();
    videoController
        .getDanDanmaku(videoController.title, videoController.episode)
        .catchError((Object e) {
      debugPrint('切换弹幕来源失败 ${e.toString()}');
    });
  }

  Widget _danmakuTab() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ValueListenableBuilder<DanmakuLoadState>(
          valueListenable: videoController.danmakuLoadState,
          builder: (context, state, _) {
            return Observer(builder: (context) {
              return SwitchListTile(
                title: const Text('显示弹幕'),
                subtitle: Text(state.summary),
                value: videoController.danmakuOn,
                onChanged: (value) {
                  playerController.clearDanmaku();
                  videoController.danmakuOn = value;
                },
              );
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final DanmakuSource? source in [
                null,
                ...DanmakuSource.values,
              ])
                ChoiceChip(
                  label: Text(source?.label ?? '自动'),
                  tooltip: source?.description ?? '按弹幕设置里的来源和顺序',
                  selected: videoController.danmakuSourceOverride == source,
                  onSelected: (_) => _switchDanmakuSource(source),
                ),
            ],
          ),
        ),
        DanmakuStyleEditor(
          settings: playerController.danmakuSettings,
          onChanged: () => playerController.applyDanmakuSettings(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [Tab(text: '播放'), Tab(text: '弹幕')],
          ),
          Expanded(
            child: TabBarView(
              children: [_playbackTab(), _danmakuTab()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every episode of the current anime as a grid of buttons.
class EpisodePanel extends StatelessWidget {
  const EpisodePanel({super.key, this.onSelected});

  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final VideoController videoController = Modular.get<VideoController>();
    return Observer(builder: (context) {
      final int count = videoController.token.length;
      final int current = videoController.episode;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('选集 (共 $count 话)',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 96,
                mainAxisExtent: 44,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: count,
              itemBuilder: (context, index) {
                final int episode = index + 1;
                final Widget label = Text('第 $episode 话');
                if (episode == current) {
                  return FilledButton(
                    onPressed: onSelected,
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                    child: label,
                  );
                }
                return FilledButton.tonal(
                  style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () {
                    onSelected?.call();
                    videoController.changeEpisode(episode);
                  },
                  child: label,
                );
              },
            ),
          ),
        ],
      );
    });
  }
}
