import 'package:flutter/material.dart';
import 'package:oneanime/bean/danmaku/danmaku_source.dart';

/// Turns danmaku sources on and off, orders them by priority, and picks
/// between using the first source that has the episode or merging them all.
class DanmakuSourceEditor extends StatefulWidget {
  const DanmakuSourceEditor({super.key});

  @override
  State<DanmakuSourceEditor> createState() => _DanmakuSourceEditorState();
}

class _DanmakuSourceEditorState extends State<DanmakuSourceEditor> {
  final DanmakuSourceSettings settings = DanmakuSourceSettings.load();

  void _update(VoidCallback change) {
    setState(change);
    settings.save();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            '弹幕来源',
            style: Theme.of(context)
                .textTheme
                .titleSmall!
                .copyWith(color: colors.primary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            settings.merge
                ? '同时加载所有开启的来源，重复的弹幕只保留一条'
                : '按顺序查找，用第一个有本集弹幕的来源；拖动右侧把手调整顺序',
            style: Theme.of(context)
                .textTheme
                .bodySmall!
                .copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (int from, int to) {
            _update(
                () => settings.order.insert(to, settings.order.removeAt(from)));
          },
          children: [
            for (final (int index, DanmakuSource source)
                in settings.order.indexed)
              CheckboxListTile(
                key: ValueKey(source),
                controlAffinity: ListTileControlAffinity.leading,
                value: settings.enabled.contains(source),
                title: Text(settings.merge
                    ? source.label
                    : '${index + 1}. ${source.label}'),
                subtitle: Text(source.description),
                secondary: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle),
                ),
                onChanged: (bool? value) {
                  _update(() {
                    if (value ?? false) {
                      settings.enabled.add(source);
                    } else {
                      settings.enabled.remove(source);
                    }
                  });
                },
              ),
          ],
        ),
        SwitchListTile(
          title: const Text('合并多个来源'),
          subtitle: const Text('弹幕更多，但加载会慢一些'),
          value: settings.merge,
          onChanged: (bool value) => _update(() => settings.merge = value),
        ),
      ],
    );
  }
}
