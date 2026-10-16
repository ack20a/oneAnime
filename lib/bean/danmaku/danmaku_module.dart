class Danmaku {
  /// Seconds into the episode.
  double p;

  /// Text.
  String m;

  /// 弹弹Play mode: 1 scrolling, 4 bottom, 5 top.
  int mode;

  /// RGB colour without alpha.
  int color;

  Danmaku({
    required this.p,
    required this.m,
    this.mode = 1,
    this.color = 0xFFFFFF,
  });

  /// [json] 'p' is "time,mode,color,user".
  factory Danmaku.fromJson(Map<String, dynamic> json) {
    List<String> parts = json['p'].split(',');
    double pValue = double.parse(parts[0]);
    String mValue = json['m'];
    int mode = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
    int color = parts.length > 2 ? int.tryParse(parts[2]) ?? 0xFFFFFF : 0xFFFFFF;
    return Danmaku(
      p: pValue,
      m: mValue,
      mode: mode,
      color: color & 0xFFFFFF,
    );
  }
}
