import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:oneanime/bean/danmaku/danmaku_module.dart';
import 'package:oneanime/utils/constans.dart';
import 'package:oneanime/utils/storage.dart';

/// Which font danmaku are drawn with.
class DanmakuFont {
  /// Follows the app wide "use system font" switch.
  static const String followApp = 'follow';

  /// The bundled MiSans.
  static const String appFont = 'misans';

  /// The platform default font.
  static const String system = 'system';

  /// The platform serif font (Noto Serif CJK on most Android devices).
  static const String serif = 'serif';

  /// Prefix of the value used for an imported font, followed by its family.
  static const String customPrefix = 'custom:';

  static String custom(String family) => '$customPrefix$family';

  static String? familyOf(String value, {required bool appUsesSystemFont}) {
    if (value.startsWith(customPrefix)) {
      return value.substring(customPrefix.length);
    }
    switch (value) {
      case appFont:
        return customAppFontFamily;
      case system:
        return null;
      case serif:
        return 'serif';
      default:
        return appUsesSystemFont ? null : customAppFontFamily;
    }
  }
}

/// Every user facing danmaku option, loaded from and saved to Hive.
class DanmakuSettings {
  static const List<String> borderStyleNames = ['无', '描边', '投影', '发光', '底框'];

  static const List<String> fontWeightNames = [
    '极细',
    '纤细',
    '细',
    '常规',
    '中等',
    '半粗',
    '粗',
    '特粗',
    '黑',
  ];

  static double get defaultFontSize =>
      (Platform.isIOS || Platform.isAndroid) ? 16.0 : 25.0;

  double fontSize;
  double opacity;
  int duration;
  double area;
  DanmakuBorderStyle borderStyle;
  double strokeWidth;
  int fontWeight;
  String font;
  bool colorful;
  bool hideTop;
  bool hideBottom;
  bool hideScroll;
  bool massive;
  double lineHeight;
  List<String> blockWords;

  DanmakuSettings({
    required this.fontSize,
    this.opacity = 1.0,
    this.duration = 8,
    this.area = 1.0,
    this.borderStyle = DanmakuBorderStyle.stroke,
    this.strokeWidth = 1.5,
    this.fontWeight = 4,
    this.font = DanmakuFont.followApp,
    this.colorful = true,
    this.hideTop = false,
    this.hideBottom = false,
    this.hideScroll = false,
    this.massive = false,
    this.lineHeight = 1.6,
    List<String>? blockWords,
  }) : blockWords = blockWords ?? [];

  factory DanmakuSettings.defaults() =>
      DanmakuSettings(fontSize: defaultFontSize);

  static Box get _setting => GStorage.setting;

  factory DanmakuSettings.load() {
    final Box s = _setting;
    // Older versions only had an on/off outline switch.
    final bool legacyBorder =
        s.get(SettingBoxKey.danmakuBorder, defaultValue: true);
    final int styleIndex = s.get(SettingBoxKey.danmakuBorderStyle,
        defaultValue: legacyBorder
            ? DanmakuBorderStyle.stroke.index
            : DanmakuBorderStyle.none.index);
    return DanmakuSettings(
      fontSize: (s.get(SettingBoxKey.danmakuFontSize,
              defaultValue: defaultFontSize) as num)
          .toDouble(),
      opacity:
          (s.get(SettingBoxKey.danmakuOpacity, defaultValue: 1.0) as num)
              .toDouble(),
      duration:
          (s.get(SettingBoxKey.danmakuDuration, defaultValue: 8) as num)
              .toInt(),
      area: (s.get(SettingBoxKey.danmakuArea, defaultValue: 1.0) as num)
          .toDouble(),
      borderStyle: DanmakuBorderStyle.values[
          styleIndex.clamp(0, DanmakuBorderStyle.values.length - 1)],
      strokeWidth:
          (s.get(SettingBoxKey.danmakuStrokeWidth, defaultValue: 1.5) as num)
              .toDouble(),
      fontWeight: (s.get(SettingBoxKey.danmakuFontWeight, defaultValue: 4)
              as num)
          .toInt()
          .clamp(0, 8),
      font: s.get(SettingBoxKey.danmakuFont,
          defaultValue: DanmakuFont.followApp),
      colorful: s.get(SettingBoxKey.danmakuColorful, defaultValue: true),
      hideTop: s.get(SettingBoxKey.danmakuHideTop, defaultValue: false),
      hideBottom: s.get(SettingBoxKey.danmakuHideBottom, defaultValue: false),
      hideScroll: s.get(SettingBoxKey.danmakuHideScroll, defaultValue: false),
      massive: s.get(SettingBoxKey.danmakuMassive, defaultValue: false),
      lineHeight:
          (s.get(SettingBoxKey.danmakuLineHeight, defaultValue: 1.6) as num)
              .toDouble(),
      blockWords: List<String>.from(
          s.get(SettingBoxKey.danmakuBlockWords, defaultValue: <String>[])),
    );
  }

  Future<void> save() async {
    final Box s = _setting;
    await s.putAll({
      SettingBoxKey.danmakuFontSize: fontSize,
      SettingBoxKey.danmakuOpacity: opacity,
      SettingBoxKey.danmakuDuration: duration,
      SettingBoxKey.danmakuArea: area,
      SettingBoxKey.danmakuBorderStyle: borderStyle.index,
      SettingBoxKey.danmakuBorder: borderStyle != DanmakuBorderStyle.none,
      SettingBoxKey.danmakuStrokeWidth: strokeWidth,
      SettingBoxKey.danmakuFontWeight: fontWeight,
      SettingBoxKey.danmakuFont: font,
      SettingBoxKey.danmakuColorful: colorful,
      SettingBoxKey.danmakuHideTop: hideTop,
      SettingBoxKey.danmakuHideBottom: hideBottom,
      SettingBoxKey.danmakuHideScroll: hideScroll,
      SettingBoxKey.danmakuMassive: massive,
      SettingBoxKey.danmakuLineHeight: lineHeight,
      SettingBoxKey.danmakuBlockWords: blockWords,
    });
  }

  /// Resets the look of danmaku, leaving the block list alone.
  void resetStyle() {
    final DanmakuSettings d = DanmakuSettings.defaults();
    fontSize = d.fontSize;
    opacity = d.opacity;
    duration = d.duration;
    area = d.area;
    borderStyle = d.borderStyle;
    strokeWidth = d.strokeWidth;
    fontWeight = d.fontWeight;
    font = d.font;
    colorful = d.colorful;
    hideTop = d.hideTop;
    hideBottom = d.hideBottom;
    hideScroll = d.hideScroll;
    massive = d.massive;
    lineHeight = d.lineHeight;
  }

  String? get fontFamily => DanmakuFont.familyOf(font,
      appUsesSystemFont:
          _setting.get(SettingBoxKey.useSystemFont, defaultValue: false));

  DanmakuOption toOption() => DanmakuOption(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: fontFamily,
        area: area,
        duration: duration.toDouble(),
        // Top and bottom danmaku stay a bit shorter than scrolling ones.
        staticDuration: (duration * 0.6).clamp(3, 10).toDouble(),
        opacity: opacity,
        hideTop: hideTop,
        hideBottom: hideBottom,
        hideScroll: hideScroll,
        strokeWidth: strokeWidth,
        borderStyle: borderStyle,
        massiveMode: massive,
        lineHeight: lineHeight,
      );

  bool isBlocked(String text) {
    for (final String word in blockWords) {
      if (word.isNotEmpty && text.contains(word)) {
        return true;
      }
    }
    return false;
  }

  /// Converts a danmaku from 弹弹Play into what the danmaku layer draws, or
  /// null when the user filtered it out.
  DanmakuContentItem? contentOf(Danmaku danmaku) {
    if (isBlocked(danmaku.m)) {
      return null;
    }
    final DanmakuItemType type = switch (danmaku.mode) {
      4 => DanmakuItemType.bottom,
      5 => DanmakuItemType.top,
      _ => DanmakuItemType.scroll,
    };
    return DanmakuContentItem(
      danmaku.m,
      color: colorful ? Color(0xFF000000 | danmaku.color) : Colors.white,
      type: type,
    );
  }
}
