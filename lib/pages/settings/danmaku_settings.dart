import 'package:flutter/material.dart';
import 'package:oneanime/bean/danmaku/danmaku_settings.dart';
import 'package:oneanime/bean/settings/settings.dart';
import 'package:oneanime/pages/settings/danmaku_style_editor.dart';
import 'package:oneanime/utils/storage.dart';
import 'package:oneanime/bean/appbar/sys_app_bar.dart';
import 'package:oneanime/i18n/strings.g.dart';

class DanmakuSettingsPage extends StatefulWidget {
  const DanmakuSettingsPage({super.key});

  @override
  State<DanmakuSettingsPage> createState() => _DanmakuSettingsPageState();
}

class _DanmakuSettingsPageState extends State<DanmakuSettingsPage> {
  late Translations i18n;
  final DanmakuSettings danmakuSettings = DanmakuSettings.load();

  @override
  Widget build(BuildContext context) {
    i18n = Translations.of(context);
    return Scaffold(
      appBar: SysAppBar(title: Text(i18n.my.danmakuSettings.title)),
      body: ListView(
        children: [
          SetSwitchItem(
            title: i18n.my.danmakuSettings.defaultEnable,
            subTitle: i18n.my.danmakuSettings.defaultEnableSubtitle,
            setKey: SettingBoxKey.danmakuEnabledByDefault,
            defaultVal: false,
          ),
          SetSwitchItem(
            title: i18n.my.danmakuSettings.enhance,
            setKey: SettingBoxKey.danmakuEnhance,
            defaultVal: true,
          ),
          const Divider(height: 1),
          DanmakuStyleEditor(
            settings: danmakuSettings,
            onChanged: () => danmakuSettings.save(),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}
