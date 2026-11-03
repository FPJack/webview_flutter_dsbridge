import 'package:flutter/material.dart';
import 'package:webview_flutter_dsbridge/webview_flutter_dsbridge.dart';

/// 通用网页容器：内部使用 [DSBridgeWebView] 渲染。
///
/// * [url]：要加载的网页地址；
/// * [title]：页面标题，为空时使用网页自身的 `document.title`；
/// * 顶部展示加载进度条；
/// * 主框架加载失败时展示错误页，可点击重试。
class DSBridgeWebPage extends StatefulWidget {
  const DSBridgeWebPage({
    super.key,
    required this.url,
    this.title,
    this.hideAppBar = false,
    this.onControllerCreated,
  });

  /// 网页地址。
  final String url;

  /// 标题，为 `null` 或空字符串时使用网页标题。
  final String? title;

  /// 是否隐藏导航栏，默认显示。
  ///
  /// 隐藏后进度条显示在页面顶部，网页内容避开状态栏区域；
  /// 可通过系统返回键、错误页的“返回”按钮或网页调用 `window.close()` 关闭页面。
  final bool hideAppBar;

  /// 控制器创建后回调，可用于注册 JavaScript 对象等（在加载页面之前调用）。
  final void Function(DSBridgeController controller)? onControllerCreated;

  @override
  State<DSBridgeWebPage> createState() => _DSBridgeWebPageState();
}

class _DSBridgeWebPageState extends State<DSBridgeWebPage> {
  /// iOS 上导航被取消（如快速跳转）时的错误码，不视为加载失败。
  static const int _iosCancelledErrorCode = -999;

  late final DSBridgeController _controller;

  /// 加载进度 0 ~ 100，同一轮加载内只增不减。
  int _progress = 0;

  /// 加载轮次，每开始新一轮加载 +1，用于让进度条从 0 重新开始而不是“倒退”动画。
  int _loadCycle = 0;

  /// 网页自身的标题。
  String? _webTitle;

  /// 错误信息，不为 `null` 时展示错误页。
  String? _errorMessage;

  /// 加载失败的地址，重试时使用。
  String? _failedUrl;

  @override
  void initState() {
    super.initState();
    _controller = DSBridgeController()
      ..setJavascriptCloseWindowListener(_closePage);
    _controller.webViewController.setNavigationDelegate(
      NavigationDelegate(
        onProgress: _onProgress,
        onPageStarted: (String url) {
          if (mounted) {
            setState(() {
              // 只有上一轮已完成时才开始新一轮；同一轮内（如重定向）不重置进度，
              // 否则已上报的进度会被清零，出现进度条倒退。
              if (_progress >= 100) {
                _startNewCycle();
              }
              _errorMessage = null;
              _failedUrl = null;
            });
          }
        },
        onPageFinished: (String url) {
          if (mounted) {
            setState(() => _progress = 100);
          }
          _updateWebTitle();
        },
        onUrlChange: (_) => _updateWebTitle(),
        onWebResourceError: (error) {
          // 只处理主框架错误，忽略子资源（图片、脚本等）加载失败。
          if (error.isForMainFrame == false || error.errorCode == _iosCancelledErrorCode) {
            return;
          }
          if (!mounted) {
            return;
          }
          setState(() {
            _progress = 100;
            _errorMessage = error.description.isEmpty
                ? '错误码：${error.errorCode}'
                : error.description;
            _failedUrl = error.url;
          });
        },
      ),
    );
    widget.onControllerCreated?.call(_controller);
    _load(widget.url);
  }

  @override
  void didUpdateWidget(covariant DSBridgeWebPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _load(widget.url);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 加载地址，地址非法时直接展示错误页。
  Future<void> _load(String url) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      setState(() {
        _errorMessage = '无效的网址：$url';
        _failedUrl = null;
      });
      return;
    }
    setState(() {
      _errorMessage = null;
      _startNewCycle();
    });
    try {
      await _controller.loadRequest(uri);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _failedUrl = url;
        });
      }
    }
  }

  /// 开始新一轮加载（需在 setState 内调用）。
  void _startNewCycle() {
    _progress = 0;
    _loadCycle++;
  }

  /// 进度回调：同一轮加载内忽略比当前小的值，避免进度条来回跳动。
  ///
  /// WebView 在重定向、子请求时上报的进度可能回落（如 70 -> 10 -> 80），
  /// 直接使用会让进度条倒退。
  void _onProgress(int progress) {
    if (!mounted) {
      return;
    }
    if (_progress >= 100) {
      // 上一轮已结束，新的进度代表新一轮加载（如点击网页内链接）。
      if (progress < 100) {
        setState(() {
          _startNewCycle();
          _progress = progress;
        });
      }
      return;
    }
    if (progress > _progress) {
      setState(() => _progress = progress);
    }
  }

  /// 获取网页标题。
  Future<void> _updateWebTitle() async {
    final String? title = await _controller.webViewController.getTitle();
    if (mounted && title != _webTitle) {
      setState(() => _webTitle = title);
    }
  }

  /// 重试：优先重新加载失败的地址，否则加载初始地址。
  void _retry() {
    _load(_failedUrl ?? widget.url);
  }

  /// 返回键：网页可后退时先后退，否则关闭当前页面。
  Future<void> _handleBack() async {
    if (_errorMessage == null && await _controller.webViewController.canGoBack()) {
      await _controller.webViewController.goBack();
      return;
    }
    _closePage();
  }

  /// 关闭当前页面。
  ///
  /// 注意不能用 `maybePop`：本页 [PopScope.canPop] 为 `false`，
  /// `maybePop` 会再次被拦截并回调 [_handleBack]，导致页面无法关闭。
  void _closePage() {
    if (!mounted) {
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  String get _displayTitle {
    final String? custom = widget.title;
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return _webTitle ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final Widget progressBar = _progress < 100 && _errorMessage == null
        ? _ProgressBar(key: ValueKey<int>(_loadCycle), progress: _progress)
        : const SizedBox(height: 2);

    final Widget content = Stack(
      children: <Widget>[
        DSBridgeWebView(controller: _controller),
        if (_errorMessage != null)
          Positioned.fill(
            child: _ErrorView(
              message: _errorMessage!,
              onRetry: _retry,
              // 无导航栏时提供返回入口（iOS 没有系统返回键）。
              onClose: widget.hideAppBar ? _closePage : null,
            ),
          ),
        // 隐藏导航栏时，进度条叠加在网页顶部。
        if (widget.hideAppBar)
          Positioned(top: 0, left: 0, right: 0, child: progressBar),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        appBar: widget.hideAppBar
            ? null
            : AppBar(
                title: Text(_displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                actions: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _closePage,
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: progressBar,
                ),
              ),
        // 无导航栏时避开状态栏/刘海区域。
        body: widget.hideAppBar ? SafeArea(bottom: false, child: content) : content,
      ),
    );
  }
}

/// 网页加载进度条。
///
/// * 始终为确定进度模式：`LinearProgressIndicator(value: null)` 的不确定模式是来回扫动的动画，
///   看起来就像进度条倒退；
/// * 进度变化时平滑过渡；新一轮加载通过外部更换 key 从 0 重新开始，不会出现倒退动画。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({super.key, required this.progress});

  /// 0 ~ 100。
  final int progress;

  /// 刚开始加载时至少显示一小段，让用户感知正在加载。
  static const double _minValue = 0.05;

  @override
  Widget build(BuildContext context) {
    final double target = (progress / 100).clamp(_minValue, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (BuildContext context, double value, Widget? child) =>
          LinearProgressIndicator(value: value, minHeight: 2),
    );
  }
}

/// 网页加载失败时展示的错误页。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry, this.onClose});

  final String message;
  final VoidCallback onRetry;

  /// 不为 `null` 时额外展示“返回”按钮。
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('页面加载失败', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
              ),
              if (onClose != null) ...<Widget>[
                const SizedBox(height: 8),
                TextButton(onPressed: onClose, child: const Text('返回')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

