/// 基于 `webview_flutter` 的 DSBridge Flutter 实现。
///
/// 兼容网页端 `dsbridge.js`（v3），API 与 iOS `DWKWebView` 一一对应。
library;

export 'package:webview_flutter/webview_flutter.dart'
    show
        JavaScriptAlertDialogRequest,
        JavaScriptConfirmDialogRequest,
        JavaScriptTextInputDialogRequest,
        NavigationDecision,
        NavigationDelegate,
        NavigationRequest,
        PlatformWebViewControllerCreationParams,
        WebViewController,
        WebViewPermissionRequest;

export 'src/ds_javascript_object.dart';
export 'src/ds_ui_delegate.dart';
export 'src/dsbridge_controller.dart';
export 'src/dsbridge_webview.dart';

