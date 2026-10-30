/// Recoverable cross-module failure. Callers must supply a fixed, safe message.
class EchoFailure implements Exception {
  const EchoFailure(this.code, this.safeMessage);
  final String code;
  final String safeMessage;
  @override
  String toString() => 'EchoFailure($code): $safeMessage';
}

Never invalidModel() => throw const EchoFailure('validation', '输入数据无效');

/// Converts parsing errors without disclosing the untrusted source payload.
T parseModel<T>(T Function() parse) {
  try {
    return parse();
  } on EchoFailure {
    rethrow;
  } on Object {
    return invalidModel();
  }
}

abstract interface class CancellationToken {
  bool get isCancelled;
}
