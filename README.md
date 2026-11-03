# webview_flutter_dsbridge

基于 `webview_flutter` 的 DSBridge Flutter 实现，兼容网页端 `dsbridge.js`（v3），API 与 iOS `DWKWebView` 一一对应，同时支持 iOS / Android。

## 原理

| 方向 | 实现 |
| --- | --- |
| JS → Flutter（同步/异步） | UA 追加 `_dsbridge` → `dsbridge.js` 走 `prompt("_dsbridge=method", args)`；通过 `setOnJavaScriptTextInputDialog` 拦截并返回 JSON |
| Flutter → JS | `runJavaScript("window._handleMessageFromNative(...)")`，JS 通过 `_dsb.returnValue` 回传 |
| 异步回调 | `window.dscbN(...)`，50ms 批量合并执行（同 iOS） |
| 启动队列 | 页面 `_dsb.dsinit` 之前的 `callHandler` 先缓存，初始化后统一派发 |

## 目录结构

```
lib/
  webview_flutter_dsbridge.dart          # 对外导出
  src/
    dsbridge_controller.dart     # DWKWebView
    dsbridge_webview.dart        # Widget，负责展示 + 绑定弹窗 context
    ds_javascript_object.dart    # JS 可调用的原生对象（替代 ObjC 反射）
    ds_internal_apis.dart        # InternalApis（_dsb 命名空间）
    ds_ui_delegate.dart          # DSUIDelegate + 弹窗文案 key
    ds_dialog_presenter.dart     # 默认 alert/confirm/prompt 弹窗
    ds_call_info.dart            # DSCallInfo
    ds_util.dart                 # JSBUtil
```

## API 对照

| iOS DWKWebView | DSBridgeController |
| --- | --- |
| `loadUrl:` | `loadUrl(url)`（另有 `loadRequest/loadHtmlString/loadFlutterAsset/loadFile`） |
| `callHandler:arguments:` / `callHandler:completionHandler:` / `callHandler:arguments:completionHandler:` | `callHandler(name, {arguments, completionHandler})`，另有 `callHandlerAsync` |
| `setJavascriptCloseWindowListener:` | `setJavascriptCloseWindowListener(cb)` |
| `addJavascriptObject:namespace:` | `addJavascriptObject(object, [namespace])` |
| `removeJavascriptObject:` | `removeJavascriptObject([namespace])` |
| `hasJavascriptMethod:methodExistCallback:` | `Future<bool> hasJavascriptMethod(name)` |
| `setDebugMode:` | `setDebugMode(bool)` |
| `disableJavascriptDialogBlock:` | `disableJavascriptDialogBlock(bool)` |
| `customJavascriptDialogLabelTitles:` | `customJavascriptDialogLabelTitles(map)`（key 见 `DSDialogLabelKeys`） |
| `DSUIDelegate` | `dsUIDelegate`（`DSUIDelegate` 对 alert/confirm/prompt 可选接管） |

## 使用

```dart
class JsApi extends DSJavascriptObject {
  JsApi() {
    registerSyncMethod('testSyn', (args) => '$args[ syn call]');
    registerAsyncMethod('testAsyn', (args, handler) => handler('$args [ asyn call]'));
  }
}

final controller = DSBridgeController()
  ..addJavascriptObject(JsApi())
  ..addJavascriptObject(JsEchoApi(), 'echo');
controller.loadUrl('https://example.com');

// Widget
DSBridgeWebView(controller: controller);

// 或基于已有的 WebViewController（如已配置 NavigationDelegate）
final webViewController = WebViewController()
  ..setNavigationDelegate(NavigationDelegate(onPageFinished: print));
final bridge = DSBridgeController.fromWebViewController(webViewController);
await bridge.ready; // 若直接用 webViewController.loadRequest，需先等待 ready

// Flutter -> JS
controller.callHandler('addValue', arguments: [3, 4], completionHandler: print);
```

注意：
* 同步方法可以返回 `Future`，JS 端会一直阻塞到结果返回；返回值需可 JSON 序列化。
* 异步方法 `handler(value, complete: false)` 可多次回调（如进度）。
* 桥接接管了 JS 弹窗和 UA，请勿直接在 `webViewController` 上覆盖这些设置，自定义 UA 请用 `controller.setUserAgent`。
* `_dsb` 命名空间为内部保留。

完整示例见 `demo/`（加载 `demo/assets/web/test.html`）。
