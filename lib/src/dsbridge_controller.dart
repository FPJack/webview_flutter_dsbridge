import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'ds_call_info.dart';
import 'ds_dialog_presenter.dart';
import 'ds_internal_apis.dart';
import 'ds_javascript_object.dart';
import 'ds_ui_delegate.dart';
import 'ds_util.dart';

/// Flutter 调用 JavaScript 处理函数后的结果回调。
///
/// 当 JavaScript 端以 `responseCallback(value, false)` 回复时，可能会被多次调用。
typedef DSResponseCallback = void Function(Object? value);

/// iOS `DWKWebView` 的 Flutter 版本，基于 `webview_flutter` 的 [WebViewController] 实现。
///
/// ## 通信原理
///
/// 当 `window._dswk` 被设置或 UA 中包含 `_dsbridge` 时，`dsbridge.js` 会通过
/// `prompt("_dsbridge=" + method, args)` **同步**调用原生。本控制器：
///
/// 1. 在加载任何页面之前，给 UA 追加 `_dsbridge` 标记；
/// 2. 通过 [WebViewController.setOnJavaScriptTextInputDialog] 拦截 `prompt()`
///    （WKWebView 与 Android WebView 均支持），并返回 JSON 结果，
///    从而在双端都支持同步的 `dsBridge.call`；
/// 3. 通过 [WebViewController.runJavaScript] 执行
///    `window._handleMessageFromNative(...)` 调用 JS，以及执行 JS 异步回调（`window.dscbN`）。
///
/// 由于桥接接管了 alert / confirm / prompt 回调，自定义 JS 弹窗请使用 [dsUIDelegate]，
/// 修改 UA 请使用 [setUserAgent]，不要直接调用 `webViewController.setUserAgent`。
class DSBridgeController {
  /// 使用新建的 [WebViewController] 创建桥接。
  DSBridgeController({
    PlatformWebViewControllerCreationParams? creationParams,
    void Function(WebViewPermissionRequest request)? onPermissionRequest,
  }) : this.fromWebViewController(
          creationParams == null
              ? WebViewController(onPermissionRequest: onPermissionRequest)
              : WebViewController.fromPlatformCreationParams(
                  creationParams,
                  onPermissionRequest: onPermissionRequest,
                ),
        );

  /// 基于已有的 [webViewController] 创建桥接，例如已配置了导航代理、
  /// 平台特有设置，或需要与其他代码共享的控制器。
  ///
  /// 桥接会接管 [webViewController] 的以下设置：
  /// * JavaScript 模式（设置为 [JavaScriptMode.unrestricted]）；
  /// * alert / confirm / prompt 回调（请改用 [dsUIDelegate]）；
  /// * UA（在当前 UA 后追加 `_dsbridge` 标记，后续修改请使用 [setUserAgent]）。
  ///
  /// 页面必须在 [ready] 完成之后加载（本类的 `load*` 方法已自动等待）；
  /// 在此之前已加载的页面需要重新加载，桥接才能生效。
  DSBridgeController.fromWebViewController(WebViewController webViewController)
      : _webViewController = webViewController {
    // 注册内部 JavaScript 对象（`_dsb` 命名空间）。
    _javaScriptNamespaceInterfaces[DSInternalApis.namespace] = DSInternalApis(_onMessage);
    _ready = _setup();
  }

  /// dsbridge.js 通过 prompt 调用原生时使用的前缀。
  static const String _promptPrefix = '_dsbridge=';

  /// 追加到 UA 中的标记，dsbridge.js 据此判断是否走 prompt 通道。
  static const String _userAgentMarker = '_dsbridge';

  /// 异步回调脚本批量执行的时间间隔（毫秒）。
  static const int _jsBatchIntervalMs = 50;

  final WebViewController _webViewController;
  final DSDialogPresenter _dialogPresenter = DSDialogPresenter();

  /// 命名空间 -> 原生 JavaScript 对象。
  final Map<String, DSJavascriptObject> _javaScriptNamespaceInterfaces =
      <String, DSJavascriptObject>{};

  /// 调用 id -> Flutter 调用 JS 的结果回调。
  final Map<int, DSResponseCallback> _handlerMap = <int, DSResponseCallback>{};

  /// 页面完成 `dsinit` 之前排队的调用；初始化完成后置为 `null`。
  List<DSCallInfo>? _callInfoList = <DSCallInfo>[];

  late final Future<void> _ready;
  VoidCallback? _javascriptCloseWindowListener;
  int _callId = 0;
  bool _jsDialogBlock = true;
  bool _isDebug = false;
  bool _disposed = false;
  String? _defaultUserAgent;

  // 异步回调脚本的批量执行（与 DWKWebView 策略一致）。
  final StringBuffer _jsCache = StringBuffer();
  int _lastCallTime = 0;
  bool _isPending = false;

  /// 允许宿主接管 JavaScript 的 alert / confirm / prompt 弹窗。
  /// 对应 `DWKWebView.DSUIDelegate`。
  DSUIDelegate? dsUIDelegate;

  /// 底层的 [WebViewController]，用于本类未封装的功能
  /// （导航代理、Cookie、滚动等）。
  ///
  /// 请勿在其上覆盖 JavaScript 弹窗回调或 UA，否则桥接将失效。
  WebViewController get webViewController => _webViewController;

  /// 控制器初始化完成、可以加载页面时完成。
  Future<void> get ready => _ready;

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  /// 开启 JS、接管弹窗回调并设置带标记的 UA。
  Future<void> _setup() async {
    await _webViewController.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _webViewController.setOnJavaScriptAlertDialog(_onJavaScriptAlertDialog);
    await _webViewController.setOnJavaScriptConfirmDialog(_onJavaScriptConfirmDialog);
    await _webViewController.setOnJavaScriptTextInputDialog(_onJavaScriptTextInputDialog);
    _defaultUserAgent = await _webViewController.getUserAgent();
    await _applyUserAgent(null);
  }

  /// 设置 UA，并确保包含 `_dsbridge` 标记；[userAgent] 为 `null` 时使用默认 UA。
  Future<void> _applyUserAgent(String? userAgent) {
    final String base = (userAgent ?? _defaultUserAgent ?? '').trim();
    final String value = base.contains(_userAgentMarker)
        ? base
        : (base.isEmpty ? _userAgentMarker : '$base $_userAgentMarker');
    return _webViewController.setUserAgent(value);
  }

  // ---------------------------------------------------------------------------
  // 页面加载（均会等待初始化完成）
  // ---------------------------------------------------------------------------

  /// 对应 `-[DWKWebView loadUrl:]`。
  Future<void> loadUrl(String url) => loadRequest(Uri.parse(url));

  /// 加载网络请求。
  Future<void> loadRequest(
    Uri uri, {
    LoadRequestMethod method = LoadRequestMethod.get,
    Map<String, String> headers = const <String, String>{},
    Uint8List? body,
  }) async {
    await _ready;
    return _webViewController.loadRequest(uri, method: method, headers: headers, body: body);
  }

  /// 加载 HTML 字符串。
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    await _ready;
    return _webViewController.loadHtmlString(html, baseUrl: baseUrl);
  }

  /// 加载 Flutter 资源文件（如 `assets/web/index.html`）。
  Future<void> loadFlutterAsset(String key) async {
    await _ready;
    return _webViewController.loadFlutterAsset(key);
  }

  /// 加载本地文件（绝对路径）。
  Future<void> loadFile(String absoluteFilePath) async {
    await _ready;
    return _webViewController.loadFile(absoluteFilePath);
  }

  /// 设置自定义 UA，会自动追加 `dsbridge.js` 所需的 `_dsbridge` 标记。
  /// 传入 `null` 恢复默认 UA。
  Future<void> setUserAgent(String? userAgent) async {
    await _ready;
    return _applyUserAgent(userAgent);
  }

  // ---------------------------------------------------------------------------
  // 对外桥接 API（与 DWKWebView 一一对应）
  // ---------------------------------------------------------------------------

  /// 调用 JS 端通过 `dsBridge.register` / `dsBridge.registerAsyn` 注册的方法。
  ///
  /// 覆盖 ObjC 的三个重载：
  /// * `callHandler:arguments:`
  /// * `callHandler:completionHandler:`
  /// * `callHandler:arguments:completionHandler:`
  ///
  /// 页面初始化 dsbridge 之前发起的调用会先排队，在 `dsinit` 时统一派发。
  void callHandler(
    String methodName, {
    List<Object?>? arguments,
    DSResponseCallback? completionHandler,
  }) {
    if (_disposed) {
      return;
    }
    final DSCallInfo callInfo = DSCallInfo(
      id: _callId++,
      method: methodName,
      args: arguments ?? const <Object?>[],
    );
    if (completionHandler != null) {
      _handlerMap[callInfo.id] = completionHandler;
    }
    final List<DSCallInfo>? queue = _callInfoList;
    if (queue != null) {
      queue.add(callInfo);
    } else {
      _dispatchJavascriptCall(callInfo);
    }
  }

  /// [callHandler] 的 [Future] 版本，以 JS 返回的第一个值完成。
  Future<Object?> callHandlerAsync(String methodName, {List<Object?>? arguments}) {
    final Completer<Object?> completer = Completer<Object?>();
    callHandler(
      methodName,
      arguments: arguments,
      completionHandler: (Object? value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
    );
    return completer.future;
  }

  /// 设置 JS 关闭当前页面的监听
  /// （dsbridge.js 会把 `window.close()` 重定向到 `_dsb.closePage`）。
  void setJavascriptCloseWindowListener(VoidCallback? callback) {
    _javascriptCloseWindowListener = callback;
  }

  /// 以 [namespace] 为命名空间向 dsBridge 添加原生 JavaScript 对象。
  /// [namespace] 为 `null` 或空字符串时，表示没有命名空间。
  void addJavascriptObject(DSJavascriptObject? object, [String? namespace]) {
    final String key = namespace ?? '';
    if (object == null) {
      return;
    }
    if (key == DSInternalApis.namespace) {
      DSUtil.log('Namespace "${DSInternalApis.namespace}" is reserved.');
      return;
    }
    _javaScriptNamespaceInterfaces[key] = object;
  }

  /// 移除指定 [namespace] 下的原生 JavaScript 对象。
  void removeJavascriptObject([String? namespace]) {
    final String key = namespace ?? '';
    if (key == DSInternalApis.namespace) {
      DSUtil.log('Namespace "${DSInternalApis.namespace}" is reserved.');
      return;
    }
    _javaScriptNamespaceInterfaces.remove(key);
  }

  /// 检测 JS 端是否存在指定的处理函数。
  ///
  /// 对应 `hasJavascriptMethod:methodExistCallback:`。
  /// 该 Future 在页面完成 dsbridge 初始化后才会完成。
  Future<bool> hasJavascriptMethod(String handlerName) {
    final Completer<bool> completer = Completer<bool>();
    callHandler(
      '_hasJavascriptMethod',
      arguments: <Object?>[handlerName],
      completionHandler: (Object? value) {
        if (!completer.isCompleted) {
          completer.complete(value == true || value == 1);
        }
      },
    );
    return completer.future;
  }

  /// 设置调试模式：调试模式下错误会在页面中弹窗提示，
  /// 原生处理函数抛出的异常会通过 [FlutterError.reportError] 上报。
  void setDebugMode(bool debug) {
    _isDebug = debug;
  }

  /// [disable] 为 `true` 时，JS 弹窗不再阻塞 JS 线程：立即返回结果，同时仍会展示弹窗。
  void disableJavascriptDialogBlock(bool disable) {
    _jsDialogBlock = !disable;
  }

  /// 自定义内置 JS 弹窗的按钮/标题文案，支持的 key 见 [DSDialogLabelKeys]。
  void customJavascriptDialogLabelTitles(Map<String, String>? dic) {
    if (dic != null) {
      _dialogPresenter.labelTitles = Map<String, String>.unmodifiable(dic);
    }
  }

  /// 释放资源，释放后不可再使用该控制器。
  void dispose() {
    _disposed = true;
    _handlerMap.clear();
    _callInfoList = null;
    _jsCache.clear();
    _javascriptCloseWindowListener = null;
  }

  // ---------------------------------------------------------------------------
  // Widget 绑定（供 DSBridgeWebView 使用）
  // ---------------------------------------------------------------------------

  /// 绑定用于展示内置弹窗的 [BuildContext]。
  void attachContext(BuildContext context) => _dialogPresenter.attach(context);

  /// 解除绑定 [BuildContext]。
  void detachContext(BuildContext context) => _dialogPresenter.detach(context);

  // ---------------------------------------------------------------------------
  // JavaScript -> Flutter
  // ---------------------------------------------------------------------------

  /// prompt 回调：带 `_dsbridge=` 前缀的是桥接调用，其余按普通弹窗处理。
  Future<String> _onJavaScriptTextInputDialog(JavaScriptTextInputDialogRequest request) async {
    final String prompt = request.message;
    if (prompt.startsWith(_promptPrefix)) {
      return _call(prompt.substring(_promptPrefix.length), request.defaultText);
    }

    if (!_jsDialogBlock) {
      unawaited(_showPrompt(request));
      return '';
    }
    return _showPrompt(request);
  }

  /// 优先交给 [dsUIDelegate] 处理，否则展示内置 prompt 弹窗。
  Future<String> _showPrompt(JavaScriptTextInputDialogRequest request) async {
    final Future<String> Function(JavaScriptTextInputDialogRequest)? delegate =
        dsUIDelegate?.onJavaScriptTextInputDialog;
    if (delegate != null) {
      return delegate(request);
    }
    return await _dialogPresenter.prompt(request.message, request.defaultText) ?? '';
  }

  /// alert 回调。
  Future<void> _onJavaScriptAlertDialog(JavaScriptAlertDialogRequest request) async {
    if (!_jsDialogBlock) {
      unawaited(_showAlert(request));
      return;
    }
    return _showAlert(request);
  }

  /// 优先交给 [dsUIDelegate] 处理，否则展示内置 alert 弹窗。
  Future<void> _showAlert(JavaScriptAlertDialogRequest request) async {
    final Future<void> Function(JavaScriptAlertDialogRequest)? delegate =
        dsUIDelegate?.onJavaScriptAlertDialog;
    if (delegate != null) {
      return delegate(request);
    }
    await _dialogPresenter.alert(request.message);
  }

  /// confirm 回调。
  Future<bool> _onJavaScriptConfirmDialog(JavaScriptConfirmDialogRequest request) async {
    if (!_jsDialogBlock) {
      unawaited(_showConfirm(request));
      return true;
    }
    return _showConfirm(request);
  }

  /// 优先交给 [dsUIDelegate] 处理，否则展示内置 confirm 弹窗。
  Future<bool> _showConfirm(JavaScriptConfirmDialogRequest request) async {
    final Future<bool> Function(JavaScriptConfirmDialogRequest)? delegate =
        dsUIDelegate?.onJavaScriptConfirmDialog;
    if (delegate != null) {
      return delegate(request);
    }
    return await _dialogPresenter.confirm(request.message) ?? false;
  }

  /// 处理 JS 端的 `dsBridge.call`，返回 JSON 格式的结果。
  Future<String> _call(String rawMethod, String? argStr) async {
    final String fullName = rawMethod.trim();
    final (String namespace, String method) = DSUtil.parseNamespace(fullName);
    final Map<String, Object?> result = <String, Object?>{'code': -1, 'data': ''};

    final DSJavascriptObject? object = _javaScriptNamespaceInterfaces[namespace];
    if (object == null || _disposed) {
      DSUtil.log("Js bridge called, but can't find a corresponded JavascriptObject, "
          'please check your code! method: $fullName');
      return DSUtil.objToJsonString(result);
    }

    final Object? decoded = DSUtil.jsonStringToObject(argStr);
    final Map<Object?, Object?>? args = decoded is Map ? decoded : null;
    final Object? arg = args?['data'];
    final Object? callbackStub = args?['_dscbstub'];

    if (callbackStub is String) {
      // 带回调桩的为异步调用，只匹配异步方法（与 iOS 行为一致）。
      final DSAsyncMethod? asyncMethod = object.asyncMethod(method);
      if (asyncMethod != null) {
        try {
          asyncMethod(arg, _createCompletionHandler(callbackStub));
          result['code'] = 0;
        } catch (e, st) {
          _reportHandlerError('async method "$fullName"', e, st);
        }
        return DSUtil.objToJsonString(result);
      }
    } else {
      // 同步调用，JS 线程会阻塞直到返回。
      final DSSyncMethod? syncMethod = object.syncMethod(method);
      if (syncMethod != null) {
        try {
          final Object? ret = await syncMethod(arg);
          result['code'] = 0;
          if (ret != null) {
            result['data'] = ret;
          }
        } catch (e, st) {
          _reportHandlerError('sync method "$fullName"', e, st);
        }
        return DSUtil.objToJsonString(result);
      }
    }

    // 未找到对应实现。
    final String error =
        'Error! \n Method $fullName is not invoked, since there is not a implementation for it';
    if (_isDebug) {
      _evaluateJavascript('window.alert(${DSUtil.toJsLiteral(error)});');
    }
    DSUtil.log(error);
    return DSUtil.objToJsonString(result);
  }

  /// 为异步调用创建完成回调，结果通过执行 `window[callbackStub](data)` 回传给 JS。
  DSCompletionHandler _createCompletionHandler(String callbackStub) {
    final String cb = DSUtil.toJsLiteral(callbackStub);
    return (Object? value, {bool complete = true}) {
      if (_disposed) {
        return;
      }
      final String payload = DSUtil.toJsLiteral(<String, Object?>{
        'code': 0,
        'data': value ?? '',
      });
      // complete 为 true 时删除 JS 端回调，否则保留以便多次回调。
      final String del = complete ? 'delete window[$cb];' : '';
      _enqueueJavascript('try{window[$cb]($payload.data);$del}catch(e){};');
    };
  }

  /// 将 [_jsBatchIntervalMs] 内到达的回调脚本合并执行，
  /// 避免频繁调用平台通道（例如 2000 次连续调用的压力测试）。
  void _enqueueJavascript(String js) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    _jsCache.write(js);
    if (now - _lastCallTime < _jsBatchIntervalMs) {
      if (!_isPending) {
        _isPending = true;
        _flushJavascript(_jsBatchIntervalMs);
      }
    } else {
      _flushJavascript(0);
    }
  }

  /// 延迟 [delayMs] 毫秒后执行缓存的脚本。
  void _flushJavascript(int delayMs) {
    Timer(Duration(milliseconds: delayMs), () {
      if (_disposed || _jsCache.isEmpty) {
        return;
      }
      final String js = _jsCache.toString();
      _jsCache.clear();
      _isPending = false;
      _lastCallTime = DateTime.now().millisecondsSinceEpoch;
      _evaluateJavascript(js);
    });
  }

  /// 执行 JS 脚本，不等待结果，失败仅打印日志。
  void _evaluateJavascript(String js) {
    if (_disposed) {
      return;
    }
    _webViewController.runJavaScript(js).catchError((Object e) {
      DSUtil.log('runJavaScript failed: $e');
    });
  }

  /// 上报处理函数异常：调试模式走 [FlutterError.reportError]，否则仅打印日志。
  void _reportHandlerError(String where, Object error, StackTrace stack) {
    if (_isDebug) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'webview_flutter_dsbridge',
        context: ErrorDescription('while invoking $where'),
      ));
    } else {
      DSUtil.log('Exception while invoking $where: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Flutter -> JavaScript
  // ---------------------------------------------------------------------------

  /// 派发初始化前排队的调用，之后的调用直接派发。
  void _dispatchStartupQueue() {
    final List<DSCallInfo>? queue = _callInfoList;
    if (queue == null) {
      return;
    }
    _callInfoList = null;
    queue.forEach(_dispatchJavascriptCall);
  }

  /// 通过 `window._handleMessageFromNative` 调用 JS 方法。
  void _dispatchJavascriptCall(DSCallInfo info) {
    final String json = DSUtil.toJsLiteral(<String, Object?>{
      'method': info.method,
      'callbackId': info.id,
      'data': DSUtil.objToJsonString(info.args),
    });
    _evaluateJavascript('window._handleMessageFromNative($json);');
  }

  // ---------------------------------------------------------------------------
  // 内部 API（`_dsb` 命名空间）
  // ---------------------------------------------------------------------------

  /// 处理 dsbridge.js 发来的内部消息，对应 `-[DWKWebView onMessage:type:]`。
  Object? _onMessage(DSInternalApi type, Map<String, Object?> msg) {
    switch (type) {
      case DSInternalApi.hasNativeMethod:
        return _hasNativeMethod(msg);
      case DSInternalApi.closePage:
        _javascriptCloseWindowListener?.call();
        return null;
      case DSInternalApi.returnValue:
        _returnValue(msg);
        return null;
      case DSInternalApi.dsinit:
        _dispatchStartupQueue();
        return null;
      case DSInternalApi.disableJavascriptDialogBlock:
        disableJavascriptDialogBlock(msg['disable'] == true);
        return null;
    }
  }

  /// 响应 JS 端 `dsBridge.hasNativeMethod(name, type)`。
  bool _hasNativeMethod(Map<String, Object?> args) {
    final Object? name = args['name'];
    if (name is! String) {
      return false;
    }
    final (String namespace, String method) = DSUtil.parseNamespace(name.trim());
    final DSJavascriptObject? object = _javaScriptNamespaceInterfaces[namespace];
    return object?.hasMethod(method, DSMethodType.parse(args['type'])) ?? false;
  }

  /// 接收 JS 方法的返回值，并回调给 [callHandler] 的调用方。
  void _returnValue(Map<String, Object?> args) {
    final Object? rawId = args['id'];
    if (rawId is! num) {
      return;
    }
    final int id = rawId.toInt();
    final DSResponseCallback? handler = _handlerMap[id];
    if (handler == null) {
      return;
    }
    try {
      handler(args['data']);
    } catch (e, st) {
      _reportHandlerError('JavaScript response callback (id: $id)', e, st);
    }
    // complete 为 true 表示 JS 端不会再回调，移除处理函数。
    if (args['complete'] == true) {
      _handlerMap.remove(id);
    }
  }
}

