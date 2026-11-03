import 'dart:async';

/// 异步原生方法的完成回调，对应 iOS 的 `JSCallback`。
///
/// * [value] 必须可被 JSON 序列化。
/// * [complete] 默认为 `true`；传 `false` 时 JS 端回调会被保留，
///   可多次回调（如进度通知）。
typedef DSCompletionHandler = void Function(Object? value, {bool complete});

/// 暴露给 JavaScript 的同步原生方法。
///
/// 由不带回调的 `dsBridge.call(name, args)` 触发。[args] 为 JS 传入并解析后的
/// JSON 参数（可能为 `null`），返回值必须可被 JSON 序列化。
/// 支持返回 [Future]：JS 调用方会一直阻塞到 Future 完成。
typedef DSSyncMethod = FutureOr<Object?> Function(Object? args);

/// 暴露给 JavaScript 的异步原生方法。
///
/// 由带回调的 `dsBridge.call(name, args, callback)` 触发。
typedef DSAsyncMethod = void Function(Object? args, DSCompletionHandler handler);

/// `dsBridge.hasNativeMethod(name, type)` 中的方法类型。
enum DSMethodType {
  /// 同步或异步均可。
  all('all'),

  /// 仅同步方法。
  syn('syn'),

  /// 仅异步方法。
  asyn('asyn');

  const DSMethodType(this.value);

  /// JS 端传递的原始字符串。
  final String value;

  /// 解析 JS 端传入的类型，无法识别时默认为 [DSMethodType.all]。
  static DSMethodType parse(Object? value) {
    final String text = value is String ? value.trim() : '';
    return DSMethodType.values.firstWhere(
      (DSMethodType e) => e.value == text,
      orElse: () => DSMethodType.all,
    );
  }
}

/// 同一命名空间下暴露给 JavaScript 的一组原生方法。
///
/// 对应通过 `-[DWKWebView addJavascriptObject:namespace:]` 注册的 "JavaScript 对象"。
/// 由于 Flutter 不支持运行时反射，需要显式注册方法：
///
/// ```dart
/// class JsApi extends DSJavascriptObject {
///   JsApi() {
///     registerSyncMethod('testSyn', testSyn);
///     registerAsyncMethod('testAsyn', testAsyn);
///   }
///
///   Object? testSyn(Object? args) => '$args [syn call]';
///
///   void testAsyn(Object? args, DSCompletionHandler handler) =>
///       handler('$args [asyn call]');
/// }
/// ```
///
/// 或者直接内联创建：
///
/// ```dart
/// DSJavascriptObject(
///   syncMethods: {'syn': (args) => args},
///   asyncMethods: {'asyn': (args, handler) => handler(args)},
/// );
/// ```
class DSJavascriptObject {
  DSJavascriptObject({
    Map<String, DSSyncMethod>? syncMethods,
    Map<String, DSAsyncMethod>? asyncMethods,
  }) {
    syncMethods?.forEach(registerSyncMethod);
    asyncMethods?.forEach(registerAsyncMethod);
  }

  final Map<String, DSSyncMethod> _syncMethods = <String, DSSyncMethod>{};
  final Map<String, DSAsyncMethod> _asyncMethods = <String, DSAsyncMethod>{};

  /// 注册同步方法，相当于 ObjC 的 `- (id)name:(id)args`。
  void registerSyncMethod(String name, DSSyncMethod method) {
    _syncMethods[name] = method;
  }

  /// 注册异步方法，相当于 ObjC 的
  /// `- (void)name:(id)args :(JSCallback)completionHandler`。
  void registerAsyncMethod(String name, DSAsyncMethod method) {
    _asyncMethods[name] = method;
  }

  /// 同时移除名为 [name] 的同步和异步方法。
  void unregisterMethod(String name) {
    _syncMethods.remove(name);
    _asyncMethods.remove(name);
  }

  /// 获取同步方法，不存在时返回 `null`。
  DSSyncMethod? syncMethod(String name) => _syncMethods[name];

  /// 获取异步方法，不存在时返回 `null`。
  DSAsyncMethod? asyncMethod(String name) => _asyncMethods[name];

  /// 判断是否存在指定类型的方法。
  bool hasMethod(String name, [DSMethodType type = DSMethodType.all]) {
    final bool syn = _syncMethods.containsKey(name);
    final bool asyn = _asyncMethods.containsKey(name);
    return switch (type) {
      DSMethodType.all => syn || asyn,
      DSMethodType.syn => syn,
      DSMethodType.asyn => asyn,
    };
  }
}

