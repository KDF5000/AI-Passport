import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/ai/sentence_chunker.dart';

void main() {
  test('emits complete sentences across streaming deltas', () {
    final chunker = SentenceChunker();

    expect(chunker.add('先去主剧'), isEmpty);
    expect(chunker.add('场。再看幻城剧场！还有'), ['先去主剧场。', '再看幻城剧场！']);
    expect(chunker.flush(), '还有');
  });

  test('supports western punctuation and newlines', () {
    final chunker = SentenceChunker();

    expect(chunker.add('Go left?\nThen right;'), ['Go left?', 'Then right;']);
    expect(chunker.flush(), isEmpty);
  });

  test('emits a phrase at a comma without waiting for a sentence', () {
    final chunker = SentenceChunker();

    expect(chunker.add('先去古文化街逛逛，后面继续生成'), ['先去古文化街逛逛，']);
    expect(chunker.flush(), '后面继续生成');
  });

  test('forces a phrase when streaming text has no punctuation', () {
    final chunker = SentenceChunker(maximumRunes: 10);
    const text = '这是一段持续生成但是暂时没有任何标点的内容';

    final phrases = chunker.add(text);
    final remaining = chunker.flush();

    expect(phrases, hasLength(2));
    expect(phrases.every((phrase) => phrase.runes.length == 10), isTrue);
    expect('${phrases.join()}$remaining', text);
  });
}
