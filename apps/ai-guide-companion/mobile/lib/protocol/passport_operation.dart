enum PassportOperationKind { offlinePlayback, conversation }

final class PassportOperationState {
  int? _operation;
  PassportOperationKind? _kind;

  int? get operation => _operation;
  PassportOperationKind? get kind => _kind;

  void start(int operation, PassportOperationKind kind) {
    _operation = operation;
    _kind = kind;
  }

  PassportOperationKind? cancel(int currentOperation) {
    if (_operation != currentOperation) return null;
    final kind = _kind;
    _operation = null;
    _kind = null;
    return kind;
  }

  void finish(int operation) {
    if (_operation != operation) return;
    _operation = null;
    _kind = null;
  }
}
