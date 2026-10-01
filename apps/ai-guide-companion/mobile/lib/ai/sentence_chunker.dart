final class SentenceChunker {
  SentenceChunker({this.minimumRunes = 6, this.maximumRunes = 20})
    : assert(minimumRunes > 0),
      assert(maximumRunes >= minimumRunes);

  final int minimumRunes;
  final int maximumRunes;
  String _pending = '';

  List<String> add(String delta) {
    _pending += delta;
    final completed = <String>[];
    while (_pending.isNotEmpty) {
      final runes = _pending.runes.toList(growable: false);
      int? boundaryEnd;
      for (var index = 0; index < runes.length; index++) {
        if (index + 1 >= minimumRunes && _isBoundary(runes[index])) {
          boundaryEnd = index + 1;
          break;
        }
      }

      int? end;
      if (runes.length >= maximumRunes &&
          (boundaryEnd == null || boundaryEnd > maximumRunes)) {
        end = maximumRunes;
      } else if (boundaryEnd != null) {
        end = boundaryEnd;
      }
      if (end == null) break;

      final phrase = String.fromCharCodes(runes.take(end)).trim();
      _pending = String.fromCharCodes(runes.skip(end));
      if (phrase.isNotEmpty) completed.add(phrase);
    }
    return completed;
  }

  String flush() {
    final remaining = _pending.trim();
    _pending = '';
    return remaining;
  }

  static bool _isBoundary(int rune) =>
      rune == 0x3002 || // 。
      rune == 0xff0c || // ，
      rune == 0x3001 || // 、
      rune == 0xff1a || // ：
      rune == 0xff01 || // ！
      rune == 0xff1f || // ？
      rune == 0xff1b || // ；
      rune == 0x2c || // ,
      rune == 0x3a || // :
      rune == 0x21 || // !
      rune == 0x3f || // ?
      rune == 0x3b || // ;
      rune == 0x0a;
}
