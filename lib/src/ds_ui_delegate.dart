import 'package:webview_flutter/webview_flutter.dart';

/// `DSBridgeController.customJavascriptDialogLabelTitles` 支持的文案 key。
abstract final class DSDialogLabelKeys {
  /// alert 标题。
  static const String alertTitle = 'alertTitle';

  /// alert 确定按钮。
  static const String alertBtn = 'alertBtn';

  /// confirm 标题。
  static const String confirmTitle = 'confirmTitle';

  /// confirm 取消按钮。
  static const String confirmCancelBtn = 'confirmCancelBtn';

  /// confirm 确定按钮。
  static const String confirmOkBtn = 'confirmOkBtn';

  /// prompt 取消按钮。
  static const String promptCancelBtn = 'promptCancelBtn';

  /// prompt 确定按钮。
  static const String promptOkBtn = 'promptOkBtn';
}

/// 允许宿主接管 JavaScript 弹窗，对应 `DWKWebView` 的 `DSUIDelegate`（`WKUIDelegate`）属性。
///
/// 每个回调都是可选的（类似 "respondsToSelector" 语义）：
/// 回调为 `null` 时使用内置的 Flutter 弹窗。
///
/// 注意：dsbridge 自身发起的 `prompt()` 调用（`_dsbridge=` 前缀）始终由桥接处理，
/// 不会传递到此代理。
class DSUIDelegate {
  const DSUIDelegate({
    this.onJavaScriptAlertDialog,
    this.onJavaScriptConfirmDialog,
    this.onJavaScriptTextInputDialog,
  });

  /// 接管 `alert()`。
  final Future<void> Function(JavaScriptAlertDialogRequest request)? onJavaScriptAlertDialog;

  /// 接管 `confirm()`，返回用户是否确认。
  final Future<bool> Function(JavaScriptConfirmDialogRequest request)? onJavaScriptConfirmDialog;

  /// 接管 `prompt()`，返回用户输入的文本。
  final Future<String> Function(JavaScriptTextInputDialogRequest request)?
      onJavaScriptTextInputDialog;
}

