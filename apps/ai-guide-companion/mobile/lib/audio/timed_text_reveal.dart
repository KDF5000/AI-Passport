final class TimedTextReveal {
  TimedTextReveal(
    String text, {
    required this.totalSteps,
    this.minimumChunkRunes = 3,
  }) : assert(totalSteps > 0),
       assert(minimumChunkRunes > 0),
       _runes = text.runes.toList(growable: false);

  final int totalSteps;
  final int minimumChunkRunes;
  final List<int> _runes;
  int _emitted = 0;

  String takeStep(int completedSteps) {
    if (_emitted >= _runes.length) return '';
    final boundedSteps = completedSteps.clamp(0, totalSteps);
    final target = boundedSteps == totalSteps
        ? _runes.length
        : (_runes.length * boundedSteps / totalSteps).floor();
    final due = target - _emitted;
    if (due < minimumChunkRunes && boundedSteps < totalSteps) return '';
    final chunk = String.fromCharCodes(_runes.sublist(_emitted, target));
    _emitted = target;
    return chunk;
  }
}
