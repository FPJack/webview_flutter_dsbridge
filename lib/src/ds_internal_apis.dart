import 'ds_javascript_object.dart';

/// 内部 API 类型，对应 iOS 的 `DSB_API_*` 枚举。
enum DSInternalApi {
  /// 查询原生方法是否存在。
  hasNativeMethod,

  /// 关闭页面。
  closePage,

  /// JS 方法的返回值。
  returnValue,

  /// JS 端 dsbridge 初始化完成。
  dsinit,

  /// 关闭 / 开启 JS 弹窗阻塞。
  disableJavascriptDialogBlock,
}

/// 将内部消息转发回控制器的处理函数。
typedef DSInternalMessageHandler = Object? Function(
  DSInternalApi type,
  Map<String, Object?> args,
);

/// 注册在 `_dsb` 命名空间下的内部 JavaScript 对象，对应 iOS 的 `InternalApis`。
///
/// 供 `dsbridge.js` 内部调用（`_dsb.dsinit`、`_dsb.returnValue` 等），
/// 开发者不应直接使用。
class DSInternalApis extends DSJavascriptObject {
  DSInternalApis(this._onMessage) {
    registerSyncMethod('hasNativeMethod', (Object? a) => _dispatch(DSInternalApi.hasNativeMethod, a));
    registerSyncMethod('closePage', (Object? a) => _dispatch(DSInternalApi.closePage, a));
    registerSyncMethod('returnValue', (Object? a) => _dispatch(DSInternalApi.returnValue, a));
    registerSyncMethod('dsinit', (Object? a) => _dispatch(DSInternalApi.dsinit, a));
    registerSyncMethod(
      'disableJavascriptDialogBlock',
      (Object? a) => _dispatch(DSInternalApi.disableJavascriptDialogBlock, a),
    );
  }

  /// 内部保留的命名空间。
  static const String namespace = '_dsb';

  final DSInternalMessageHandler _onMessage;

  /// 将参数统一转换为 Map 后转发给控制器。
  Object? _dispatch(DSInternalApi type, Object? args) {
    final Map<String, Object?> map =
        args is Map ? args.cast<String, Object?>() : const <String, Object?>{};
    return _onMessage(type, map);
  }
}

