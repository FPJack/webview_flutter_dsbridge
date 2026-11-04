import 'package:flutter/cupertino.dart';

import 'ds_ui_delegate.dart';

/// 使用 iOS 风格（Cupertino）组件展示内置的 JavaScript 弹窗（alert / confirm / prompt），
/// 对应 `DWKWebView` 中 `UIAlertController` 的默认实现。
///
/// 仅当所属的 WebView 组件已挂载、且当前没有其他桥接弹窗显示时才会展示；
/// 否则返回 `null`，调用方可据此立即结束 JS 弹窗。
class DSDialogPresenter {
  BuildContext? _context;
  bool _isShowing = false;

  /// 自定义文案，key 见 [DSDialogLabelKeys]。
  Map<String, String> labelTitles = const <String, String>{};

  /// 绑定 WebView 组件的 [BuildContext]。
  void attach(BuildContext context) => _context = context;

  /// 若 [context] 为当前绑定的 context，则解除绑定。
  void detach(BuildContext context) {
    if (identical(_context, context)) {
      _context = null;
    }
  }

  /// 获取文案，未自定义时使用 [fallback]。
  String _label(String key, String fallback) => labelTitles[key] ?? fallback;

  /// 展示弹窗；无法展示时返回 `null`。
  Future<T?> _present<T>(WidgetBuilder builder) async {
    final BuildContext? context = _context;
    if (context == null || !context.mounted || _isShowing) {
      return null;
    }
    _isShowing = true;
    try {
      return await showCupertinoDialog<T>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: builder,
      );
    } finally {
      _isShowing = false;
    }
  }

  /// 展示 alert；无法展示时返回 `false`。
  Future<bool> alert(String message) async {
    final bool? result = await _present<bool>(
      (BuildContext context) => CupertinoAlertDialog(
        title: Text(_label(DSDialogLabelKeys.alertTitle, 'Alert')),
        content: Text(message),
        actions: <Widget>[
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_label(DSDialogLabelKeys.alertBtn, 'OK')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 展示 confirm；无法展示时返回 `null`。
  Future<bool?> confirm(String message) {
    return _present<bool>(
      (BuildContext context) => CupertinoAlertDialog(
        title: Text(_label(DSDialogLabelKeys.confirmTitle, 'Alert')),
        content: Text(message),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_label(DSDialogLabelKeys.confirmCancelBtn, 'Cancel')),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_label(DSDialogLabelKeys.confirmOkBtn, 'OK')),
          ),
        ],
      ),
    );
  }

  /// 展示 prompt；无法展示时返回 `null`。
  Future<String?> prompt(String message, String? defaultText) {
    return _present<String>(
      (BuildContext context) => _PromptDialog(
        message: message,
        defaultText: defaultText,
        cancelText: _label(DSDialogLabelKeys.promptCancelBtn, 'Cancel'),
        okText: _label(DSDialogLabelKeys.promptOkBtn, 'OK'),
      ),
    );
  }
}

/// prompt 输入弹窗，使用 StatefulWidget 管理输入框控制器的生命周期。
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.message,
    required this.defaultText,
    required this.cancelText,
    required this.okText,
  });

  final String message;
  final String? defaultText;
  final String cancelText;
  final String okText;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _textController =
      TextEditingController(text: widget.defaultText);

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_textController.text);

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.message),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          controller: _textController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(''),
          child: Text(widget.cancelText),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _submit,
          child: Text(widget.okText),
        ),
      ],
    );
  }
}

