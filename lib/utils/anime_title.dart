/// An anime title split into its name and season, so titles from different
/// sites can be compared: Anime1 writes "黑色五葉草 第二季" or "II(第二季)"
/// where 巴哈姆特 writes "黑色五葉草 Season 2" or "冰劍的魔術師將要統一世界 2".
class AnimeTitle {
  /// Lowercased name without spacing, punctuation or season markers.
  final String name;

  /// 1 unless the title says otherwise.
  final int season;

  const AnimeTitle._(this.name, this.season);

  static final RegExp _seasonPattern = RegExp(
    r'第\s*([一二三四五六七八九十\d]+)\s*[季期]'
    r'|season\s*(\d+)'
    r'|(\d+)\s*(?:st|nd|rd|th)\s*season'
    // A bare number or roman numeral counts only as the last word, so names
    // such as "U-17" or "2丁目" keep their digits.
    r'|(?<=\s)(ii|iii|iv|v|vi|ⅱ|ⅲ|ⅳ|ⅴ|ⅵ|[2-9])(?=\s*(?:$|[(（\[【]))',
    caseSensitive: false,
  );

  static final RegExp _noise = RegExp(r'[\s\p{P}\p{S}]', unicode: true);

  static const Map<String, int> _romans = {
    'ii': 2, 'iii': 3, 'iv': 4, 'v': 5, 'vi': 6, //
    'ⅱ': 2, 'ⅲ': 3, 'ⅳ': 4, 'ⅴ': 5, 'ⅵ': 6,
  };

  static const String _cnDigits = '一二三四五六七八九';

  static int? _parseNumber(String text) {
    final int? arabic = int.tryParse(text);
    if (arabic != null) {
      return arabic;
    }
    final int? roman = _romans[text];
    if (roman != null) {
      return roman;
    }
    // Chinese numerals up to 99: 二, 十, 十二, 二十, 二十三.
    final int ten = text.indexOf('十');
    if (ten < 0) {
      return text.length == 1 ? _cnDigits.indexOf(text) + 1 : null;
    }
    final int tens = ten == 0 ? 1 : _cnDigits.indexOf(text[0]) + 1;
    final int ones =
        ten == text.length - 1 ? 0 : _cnDigits.indexOf(text[ten + 1]) + 1;
    return tens * 10 + ones;
  }

  factory AnimeTitle.parse(String title) {
    final String lower = title.toLowerCase();
    int season = 1;
    for (final RegExpMatch match in _seasonPattern.allMatches(lower)) {
      final String? number =
          match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4);
      final int? parsed = number == null ? null : _parseNumber(number);
      if (parsed != null && parsed > 0 && parsed > season) {
        season = parsed;
      }
    }
    final String name =
        lower.replaceAll(_seasonPattern, '').replaceAll(_noise, '');
    return AnimeTitle._(name, season);
  }

  /// The title without season markers, for a search that missed with them.
  static String withoutSeason(String title) => title
      .replaceAll(_seasonPattern, ' ')
      .replaceAll(RegExp(r'[(（\[【]\s*[)）\]】]'), ' ')
      .trim();

  /// How far [candidate] is from this title, or null when it names another
  /// anime or season. A candidate may add to the name (a "年齡限制版" tag,
  /// say). Dropping words usually means another work, except for a later
  /// season, where the season already pins it down and Anime1 likes to add
  /// the season's subtitle ("Dr.STONE 新石紀 STONE WARS(第二季)").
  int? distanceTo(AnimeTitle candidate) {
    if (name.isEmpty || candidate.name.isEmpty || candidate.season != season) {
      return null;
    }
    if (candidate.name.contains(name) ||
        (season > 1 && name.startsWith(candidate.name))) {
      return (candidate.name.length - name.length).abs();
    }
    return null;
  }
}
