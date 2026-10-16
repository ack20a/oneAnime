import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:oneanime/bean/danmaku/danmaku_settings.dart';
import 'package:oneanime/utils/font_manager.dart';

/// Every danmaku look option, shared by the settings page and the in-player
/// panel. [settings] is edited in place; [onChanged] fires after each edit.
class DanmakuStyleEditor extends StatefulWidget {
  const DanmakuStyleEditor({
    super.key,
    required this.settings,
    required this.onChanged,
    this.showPreview = true,
    this.showBlockWords = true,
  });

  final DanmakuSettings settings;
  final VoidCallback onChanged;
  final bool showPreview;
  final bool showBlockWords;

  @override
  State<DanmakuStyleEditor> createState() => _DanmakuStyleEditorState();
}

class _DanmakuStyleEditorState extends State<DanmakuStyleEditor> {
  List<CustomFont> customFonts = [];
  final GlobalKey<DanmakuPreviewState> _previewKey = GlobalKey();

  DanmakuSettings get s => widget.settings;

  @override
  void initState() {
    super.initState();
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    final List<CustomFont> fonts = await FontManager.list();
    for (final CustomFont font in fonts) {
      await FontManager.load(font);
    }
    if (mounted) {
      setState(() {
        customFonts = fonts;
      });
      _previewKey.currentState?.refresh();
    }
  }

  Future<void> _update(VoidCallback change) async {
    setState(change);
    await FontManager.ensureLoaded(s.fontFamily);
    _previewKey.currentState?.refresh();
    widget.onChanged();
  }

  Future<void> _importFont() async {
    try {
      final CustomFont? font = await FontManager.pickAndImport();
      if (font == null) {
        return;
      }
      await _loadFonts();
      await _update(() => s.font = DanmakuFont.custom(font.family));
      SmartDialog.showToast('已导入字体 ${font.name}');
    } on FormatException catch (e) {
      SmartDialog.showToast(e.message);
    } catch (e) {
      SmartDialog.showToast('导入字体失败 ${e.toString()}');
    }
  }

  Future<void> _deleteFont(CustomFont font) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除字体'),
        content: Text('确定要删除字体「${font.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await FontManager.delete(font);
    if (s.font == DanmakuFont.custom(font.family)) {
      await _update(() => s.font = DanmakuFont.followApp);
    }
    await _loadFonts();
  }

  Future<void> _addBlockWord() async {
    final TextEditingController controller = TextEditingController();
    final String? word = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加屏蔽词'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '包含该词的弹幕将不再显示'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    final String trimmed = (word ?? '').trim();
    if (trimmed.isEmpty || s.blockWords.contains(trimmed)) {
      return;
    }
    await _update(() => s.blockWords = [...s.blockWords, trimmed]);
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall!.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _chips<T>({
    required List<T> values,
    required String Function(T) label,
    required T selected,
    required ValueChanged<T> onSelected,
    void Function(T)? onLongPress,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final T value in values)
            GestureDetector(
              onLongPress:
                  onLongPress == null ? null : () => onLongPress(value),
              child: ChoiceChip(
                label: Text(label(value)),
                selected: value == selected,
                onSelected: (_) => onSelected(value),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slider({
    required String title,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
    bool enabled = true,
  }) {
    final TextStyle? labelStyle = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(title, style: labelStyle)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(valueLabel,
                textAlign: TextAlign.end, style: labelStyle),
          ),
        ],
      ),
    );
  }

  Widget _switch(String title, bool value, ValueChanged<bool> onChanged,
      {String? subtitle}) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> fontValues = [
      DanmakuFont.followApp,
      DanmakuFont.appFont,
      DanmakuFont.system,
      DanmakuFont.serif,
      for (final CustomFont font in customFonts) DanmakuFont.custom(font.family),
    ];
    String fontLabel(String value) {
      switch (value) {
        case DanmakuFont.followApp:
          return '跟随应用';
        case DanmakuFont.appFont:
          return 'MiSans';
        case DanmakuFont.system:
          return '系统默认';
        case DanmakuFont.serif:
          return '系统衬线';
      }
      for (final CustomFont font in customFonts) {
        if (DanmakuFont.custom(font.family) == value) {
          return font.name;
        }
      }
      return '未知字体';
    }

    final bool hasStroke = s.borderStyle != DanmakuBorderStyle.none &&
        s.borderStyle != DanmakuBorderStyle.background;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showPreview)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DanmakuPreview(key: _previewKey, settings: s),
          ),
        _section('字体'),
        _chips<String>(
          values: fontValues,
          label: fontLabel,
          selected: fontValues.contains(s.font) ? s.font : DanmakuFont.followApp,
          onSelected: (value) => _update(() => s.font = value),
          onLongPress: (value) {
            for (final CustomFont font in customFonts) {
              if (DanmakuFont.custom(font.family) == value) {
                _deleteFont(font);
              }
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _importFont,
                icon: const Icon(Icons.add),
                label: const Text('导入字体'),
              ),
              Expanded(
                child: Text(
                  '支持 ttf / otf，长按自定义字体可删除',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ],
          ),
        ),
        _slider(
          title: '字重',
          valueLabel: DanmakuSettings.fontWeightNames[s.fontWeight],
          value: s.fontWeight.toDouble(),
          min: 0,
          max: 8,
          divisions: 8,
          onChanged: (v) => _update(() => s.fontWeight = v.round()),
        ),
        _section('样式'),
        _chips<DanmakuBorderStyle>(
          values: DanmakuBorderStyle.values,
          label: (v) => DanmakuSettings.borderStyleNames[v.index],
          selected: s.borderStyle,
          onSelected: (value) => _update(() => s.borderStyle = value),
        ),
        _slider(
          title: '边框粗细',
          valueLabel: s.strokeWidth.toStringAsFixed(1),
          value: s.strokeWidth,
          min: 0.5,
          max: 4.0,
          divisions: 7,
          enabled: hasStroke,
          onChanged: (v) => _update(() => s.strokeWidth = v),
        ),
        _slider(
          title: '字号',
          valueLabel: s.fontSize.toStringAsFixed(0),
          value: s.fontSize,
          min: 10,
          max: 40,
          divisions: 30,
          onChanged: (v) => _update(() => s.fontSize = v.roundToDouble()),
        ),
        _slider(
          title: '不透明度',
          valueLabel: '${(s.opacity * 100).round()}%',
          value: s.opacity,
          min: 0.1,
          max: 1.0,
          divisions: 18,
          onChanged: (v) =>
              _update(() => s.opacity = (v * 20).round() / 20),
        ),
        _slider(
          title: '行距',
          valueLabel: s.lineHeight.toStringAsFixed(1),
          value: s.lineHeight,
          min: 1.2,
          max: 2.4,
          divisions: 12,
          onChanged: (v) =>
              _update(() => s.lineHeight = (v * 10).round() / 10),
        ),
        _slider(
          title: '滚动时长',
          valueLabel: '${s.duration}s',
          value: s.duration.toDouble(),
          min: 4,
          max: 16,
          divisions: 12,
          onChanged: (v) => _update(() => s.duration = v.round()),
        ),
        _section('显示区域'),
        _chips<double>(
          values: const [0.25, 0.5, 0.75, 1.0],
          label: (v) => v == 1.0 ? '全屏' : '${(v * 100).round()}%',
          selected: s.area,
          onSelected: (value) => _update(() => s.area = value),
        ),
        _section('弹幕类型'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('滚动'),
                selected: !s.hideScroll,
                onSelected: (v) => _update(() => s.hideScroll = !v),
              ),
              FilterChip(
                label: const Text('顶部'),
                selected: !s.hideTop,
                onSelected: (v) => _update(() => s.hideTop = !v),
              ),
              FilterChip(
                label: const Text('底部'),
                selected: !s.hideBottom,
                onSelected: (v) => _update(() => s.hideBottom = !v),
              ),
            ],
          ),
        ),
        _switch('彩色弹幕', s.colorful, (v) => _update(() => s.colorful = v),
            subtitle: '关闭后所有弹幕显示为白色'),
        _switch('海量弹幕', s.massive, (v) => _update(() => s.massive = v),
            subtitle: '轨道占满时叠加显示，而不是丢弃'),
        if (widget.showBlockWords) ...[
          _section('屏蔽词'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final String word in s.blockWords)
                  InputChip(
                    label: Text(word),
                    onDeleted: () => _update(() => s.blockWords =
                        s.blockWords.where((w) => w != word).toList()),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('添加'),
                  onPressed: _addBlockWord,
                ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _update(s.resetStyle),
              icon: const Icon(Icons.restart_alt),
              label: const Text('恢复默认样式'),
            ),
          ),
        ),
      ],
    );
  }
}

/// A strip of looping sample danmaku over a busy background, drawn with the
/// real danmaku layer so it matches playback exactly.
class DanmakuPreview extends StatefulWidget {
  const DanmakuPreview({super.key, required this.settings});

  final DanmakuSettings settings;

  @override
  State<DanmakuPreview> createState() => DanmakuPreviewState();
}

class DanmakuPreviewState extends State<DanmakuPreview> {
  static const List<(String, int, DanmakuItemType)> _samples = [
    ('前方高能！！！', 0xFFFFFF, DanmakuItemType.scroll),
    ('这一集作画太神了', 0xFFFFFF, DanmakuItemType.scroll),
    ('awsl', 0xFE0302, DanmakuItemType.scroll),
    ('名场面打卡', 0xFFFF00, DanmakuItemType.top),
    ('233333', 0x00CD00, DanmakuItemType.scroll),
    ('BGM 一响 DNA 动了', 0x4266BE, DanmakuItemType.scroll),
    ('第一次看，好看！', 0x222222, DanmakuItemType.scroll),
    ('下集预告也太好笑了', 0xFFFFFF, DanmakuItemType.bottom),
  ];

  DanmakuController? _controller;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 650), (_) => _emit());
  }

  void _emit() {
    final DanmakuController? controller = _controller;
    if (controller == null || !mounted) {
      return;
    }
    final (text, color, type) = _samples[_index % _samples.length];
    _index++;
    controller.addDanmaku(DanmakuContentItem(
      text,
      color: widget.settings.colorful ? Color(0xFF000000 | color) : Colors.white,
      type: type,
    ));
  }

  void refresh() {
    _controller?.updateOption(_previewOption());
  }

  DanmakuOption _previewOption() =>
      // The strip is short, so always let it use its full height.
      widget.settings.toOption().copyWith(area: 1.0);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 132,
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Bright, busy and dark patches, the backgrounds that make
                  // danmaku hard to read.
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFFFFFF),
                      Color(0xFFFFE082),
                      Color(0xFF81D4FA),
                      Color(0xFF37474F),
                      Color(0xFFF8BBD0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DanmakuScreen(
                createdController: (controller) => _controller = controller,
                option: _previewOption(),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 6,
              child: Text(
                '预览',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
