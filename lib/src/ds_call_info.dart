/// 一次待派发的 Flutter -> JavaScript 调用，对应 iOS 的 `DSCallInfo`。
class DSCallInfo {
  const DSCallInfo({
    required this.method,
    required this.id,
    required this.args,
  });

  /// JS 方法名（可带命名空间，如 `syn.addValue`）。
  final String method;

  /// 调用 id，用于匹配 JS 返回值。
  final int id;

  /// 调用参数。
  final List<Object?> args;
}

