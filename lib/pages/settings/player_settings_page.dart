import 'package:flutter/material.dart';
import 'package:oneanime/bean/settings/settings.dart';
import 'package:oneanime/utils/storage.dart';
import 'package:hive/hive.dart';
import 'package:oneanime/bean/appbar/sys_app_bar.dart';
import 'package:oneanime/i18n/strings.g.dart';

class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  State<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  Box setting = GStorage.setting;
  late Translations i18n;

  static const List<double> longPressSpeeds = [1.5, 2.0, 2.5, 3.0, 4.0];
  static const List<int> skipOpChoices = [60, 75, 80, 85, 90, 100, 120];

  late double longPressSpeed;
  late int skipOpSeconds;

  @override
  void initState() {
    super.initState();
    longPressSpeed =
        (setting.get(SettingBoxKey.longPressSpeed, defaultValue: 2.0) as num)
            .toDouble();
    skipOpSeconds =
        (setting.get(SettingBoxKey.skipOpSeconds, defaultValue: 85) as num)
            .toInt();
  }

  Future<void> _pick<T>({
    required String title,
    required T value,
    required List<T> values,
    required String Function(T) label,
    required String key,
    required ValueChanged<T> onPicked,
  }) async {
    final T? result = await showDialog<T>(
      context: context,
      builder: (context) => SelectDialog<T>(
        title: title,
        value: value,
        values: [
          for (final T v in values) {'title': label(v), 'value': v}
        ],
      ),
    );
    if (result == null) {
      return;
    }
    await setting.put(key, result);
    setState(() => onPicked(result));
  }

  @override
  Widget build(BuildContext context) {
    i18n = Translations.of(context);
    final TextStyle subtitleStyle = Theme.of(context)
        .textTheme
        .labelMedium!
        .copyWith(color: Theme.of(context).colorScheme.outline);
    return Scaffold(
      appBar: SysAppBar(title: Text(i18n.my.playerSettings.title)),
      body: ListView(
        children: [
          SetSwitchItem(
            title: i18n.my.playerSettings.hardwareAcceleration,
            setKey: SettingBoxKey.HAenable,
            defaultVal: true,
            needReboot: false,
          ),
          SetSwitchItem(
            title: i18n.my.playerSettings.autoPlay,
            setKey: SettingBoxKey.autoPlay,
            defaultVal: true,
          ),
          SetSwitchItem(
            title: i18n.my.playerSettings.autoJump,
            subTitle: i18n.my.playerSettings.autoJumpSubtitle,
            setKey: SettingBoxKey.playResume,
            defaultVal: false,
          ),
          const SetSwitchItem(
            title: '自动连播',
            subTitle: '播放结束后自动播放下一话',
            setKey: SettingBoxKey.autoNext,
            defaultVal: true,
          ),
          const SetSwitchItem(
            title: '双击两侧快退 / 快进',
            subTitle: '开启后双击左右两侧快退 / 快进 10 秒，双击中间暂停；关闭后双击任意位置暂停',
            setKey: SettingBoxKey.doubleTapSeek,
            defaultVal: true,
          ),
          ListTile(
            title: const Text('长按倍速'),
            subtitle: Text('长按画面时临时以 ${longPressSpeed}x 播放',
                style: subtitleStyle),
            onTap: () => _pick<double>(
              title: '长按倍速',
              value: longPressSpeed,
              values: longPressSpeeds,
              label: (v) => '${v}x',
              key: SettingBoxKey.longPressSpeed,
              onPicked: (v) => longPressSpeed = v,
            ),
          ),
          ListTile(
            title: const Text('跳过片头时长'),
            subtitle: Text('点击播放器中的「跳过片头」将前进 $skipOpSeconds 秒',
                style: subtitleStyle),
            onTap: () => _pick<int>(
              title: '跳过片头时长',
              value: skipOpSeconds,
              values: skipOpChoices,
              label: (v) => '$v 秒',
              key: SettingBoxKey.skipOpSeconds,
              onPicked: (v) => skipOpSeconds = v,
            ),
          ),
        ],
      ),
    );
  }
}
