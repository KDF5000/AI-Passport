import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/audio/timed_text_reveal.dart';

void main() {
  test('reveals text proportionally instead of all at once', () {
    final reveal = TimedTextReveal(
      '一二三四五六七八九十',
      totalSteps: 10,
      minimumChunkRunes: 2,
    );

    expect(reveal.takeStep(1), isEmpty);
    expect(reveal.takeStep(2), '一二');
    expect(reveal.takeStep(4), '三四');
    expect(reveal.takeStep(6), '五六');
    expect(reveal.takeStep(8), '七八');
    expect(reveal.takeStep(10), '九十');
    expect(reveal.takeStep(10), isEmpty);
  });

  test('flushes the final short chunk when audio finishes', () {
    final reveal = TimedTextReveal('导游回答', totalSteps: 3, minimumChunkRunes: 3);

    expect(reveal.takeStep(2), isEmpty);
    expect(reveal.takeStep(3), '导游回答');
  });

  test('keeps unicode characters intact', () {
    final reveal = TimedTextReveal(
      '河南🏯欢迎你',
      totalSteps: 2,
      minimumChunkRunes: 1,
    );

    expect(reveal.takeStep(1), '河南🏯');
    expect(reveal.takeStep(2), '欢迎你');
  });
}
