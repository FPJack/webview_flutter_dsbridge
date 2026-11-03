import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'dsbridge_controller.dart';

/// 展示由 [DSBridgeController] 驱动的网页。
///
/// 除了渲染 [WebViewWidget]，还会把自身的 [BuildContext] 绑定到控制器，
/// 以便展示内置的 JavaScript 弹窗。
class DSBridgeWebView extends StatefulWidget {
  const DSBridgeWebView({
    super.key,
    required this.controller,
    this.gestureRecognizers = const <Factory<OneSequenceGestureRecognizer>>{},
    this.layoutDirection = TextDirection.ltr,
  });

  /// 桥接控制器。
  final DSBridgeController controller;

  /// 透传给 [WebViewWidget] 的手势识别器。
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  /// 透传给 [WebViewWidget] 的布局方向。
  final TextDirection layoutDirection;

  @override
  State<DSBridgeWebView> createState() => _DSBridgeWebViewState();
}

class _DSBridgeWebViewState extends State<DSBridgeWebView> {
  @override
  void initState() {
    super.initState();
    widget.controller.attachContext(context);
  }

  @override
  void didUpdateWidget(covariant DSBridgeWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 控制器变更时，重新绑定 context。
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detachContext(context);
      widget.controller.attachContext(context);
    }
  }

  @override
  void dispose() {
    widget.controller.detachContext(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(
      controller: widget.controller.webViewController,
      gestureRecognizers: widget.gestureRecognizers,
      layoutDirection: widget.layoutDirection,
    );
  }
}

