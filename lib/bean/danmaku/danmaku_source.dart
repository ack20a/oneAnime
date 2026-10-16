import 'package:hive/hive.dart';
import 'package:oneanime/utils/storage.dart';

enum DanmakuSource {
  baha('巴哈姆特', '繁体番名直接匹配，覆盖最广'),
  bilibili('哔哩哔哩', '通过 bangumi-data 对照表匹配，首次使用需下载约 1.5MB'),
  dandan('弹弹Play', '需要构建时配置 API 密钥，否则会跳过');

  const DanmakuSource(this.label, this.description);

  final String label;
  final String description;

  static DanmakuSource? byName(String name) {
    for (final DanmakuSource source in values) {
      if (source.name == name) {
        return source;
      }
    }
    return null;
  }
}

/// Which danmaku sources are used, in what order, and whether their danmaku
/// are combined or the first source that has the episode wins.
class DanmakuSourceSettings {
  /// Every source, in priority order.
  List<DanmakuSource> order;
  Set<DanmakuSource> enabled;
  bool merge;

  DanmakuSourceSettings({
    required this.order,
    required this.enabled,
    required this.merge,
  });

  static Box get _setting => GStorage.setting;

  List<DanmakuSource> get active => [
        for (final source in order)
          if (enabled.contains(source)) source
      ];

  factory DanmakuSourceSettings.load() {
    final List<DanmakuSource> order = [
      for (final name in _setting.get(SettingBoxKey.danmakuSourceOrder,
          defaultValue: const <String>[]) as List)
        if (DanmakuSource.byName('$name') case final DanmakuSource source)
          source,
    ];
    // Sources added in a later version join at the end.
    for (final DanmakuSource source in DanmakuSource.values) {
      if (!order.contains(source)) {
        order.add(source);
      }
    }
    final List? enabledNames = _setting.get(SettingBoxKey.danmakuSourceEnabled);
    final Set<DanmakuSource> enabled = enabledNames == null
        ? DanmakuSource.values.toSet()
        : {
            for (final name in enabledNames)
              if (DanmakuSource.byName('$name') case final DanmakuSource source)
                source,
          };
    return DanmakuSourceSettings(
      order: order,
      enabled: enabled,
      merge:
          _setting.get(SettingBoxKey.danmakuSourceMerge, defaultValue: false),
    );
  }

  Future<void> save() async {
    await _setting.put(SettingBoxKey.danmakuSourceOrder,
        [for (final source in order) source.name]);
    await _setting.put(SettingBoxKey.danmakuSourceEnabled,
        [for (final source in enabled) source.name]);
    await _setting.put(SettingBoxKey.danmakuSourceMerge, merge);
  }
}

/// Outcome of the latest danmaku load, for the player panel.
class DanmakuLoadState {
  final bool loading;

  /// Sources that contributed danmaku.
  final List<DanmakuSource> sources;
  final int count;

  const DanmakuLoadState.loading()
      : loading = true,
        sources = const [],
        count = 0;

  const DanmakuLoadState.done(this.sources, this.count) : loading = false;

  String get summary {
    if (loading) {
      return '正在加载弹幕…';
    }
    if (count == 0) {
      return '当前剧集没有找到弹幕';
    }
    return '本集共 $count 条弹幕，来自${sources.map((s) => s.label).join('、')}';
  }
}
