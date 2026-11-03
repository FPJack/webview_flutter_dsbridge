import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter_dsbridge/webview_flutter_dsbridge.dart';

import '../bridge/js_api.dart';

/// Loads `assets/web/test.html` and demonstrates both directions:
/// * JavaScript -> Flutter: buttons inside the web page.
/// * Flutter -> JavaScript: buttons in the bottom panel.
class DSBridgeDemoPage extends StatefulWidget {
  const DSBridgeDemoPage({super.key});

  static const String testPage = 'assets/web/test.html';

  @override
  State<DSBridgeDemoPage> createState() => _DSBridgeDemoPageState();
}

class _DSBridgeDemoPageState extends State<DSBridgeDemoPage> {
  late final DSBridgeController _controller;
  final JsApi _jsApi = JsApi();
  final JsApi _swiftApi = JsApi();
  final List<String> _logs = <String>[];

  @override
  void initState() {
    super.initState();
    _controller = DSBridgeController()
      ..setDebugMode(kDebugMode)
      ..addJavascriptObject(_jsApi)
      ..addJavascriptObject(JsEchoApi(), 'echo')
      // test.html also calls "swift.testSyn" / "swift.testAsyn".
      ..addJavascriptObject(_swiftApi, 'swift')
      ..customJavascriptDialogLabelTitles(const <String, String>{
        DSDialogLabelKeys.alertTitle: 'DSBridge',
      })
      ..setJavascriptCloseWindowListener(() => Navigator.of(context).maybePop());

    // Queued until the page calls `_dsb.dsinit`, then flushed automatically.
    _controller.callHandler(
      'addValue',
      arguments: <Object?>[1, 2],
      completionHandler: (Object? value) => _log('[queued] addValue(1,2) = $value'),
    );

    _controller.loadFlutterAsset(DSBridgeDemoPage.testPage);

  }

  @override
  void dispose() {
    _jsApi.dispose();
    _swiftApi.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _log(String message) {
    debugPrint('[Demo] $message');
    if (!mounted) {
      return;
    }
    setState(() => _logs.insert(0, message));
  }

  void _call(String method, [List<Object?>? arguments]) {
    _controller.callHandler(
      method,
      arguments: arguments,
      completionHandler: (Object? value) => _log('$method(${arguments?.join(', ') ?? ''}) => $value'),
    );
  }

  Future<void> _hasJavascriptMethod(String name) async {
    final bool exist = await _controller.hasJavascriptMethod(name);
    _log('hasJavascriptMethod("$name") => $exist');
  }

  Future<void> _callAsync() async {
    final Object? value = await _controller.callHandlerAsync('syn.getInfo');
    _log('await syn.getInfo => $value');
  }

  @override
  Widget build(BuildContext context) {
    final List<(String, VoidCallback)> actions = <(String, VoidCallback)>[
      ('addValue', () => _call('addValue', <Object?>[3, 4])),
      ('append', () => _call('append', <Object?>['I', 'love', 'you'])),
      ('startTimer', () => _call('startTimer')),
      ('syn.addValue', () => _call('syn.addValue', <Object?>[5, 6])),
      ('syn.getInfo', () => _call('syn.getInfo')),
      ('asyn.addValue', () => _call('asyn.addValue', <Object?>[5, 6])),
      ('asyn.getInfo', () => _call('asyn.getInfo')),
      ('await syn.getInfo', _callAsync),
      ('has syn.getInfo', () => _hasJavascriptMethod('syn.getInfo')),
      ('has asyn.addValue', () => _hasJavascriptMethod('asyn.addValue')),
      ('has xx', () => _hasJavascriptMethod('xx')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('DSBridge Demo'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.webViewController.reload(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(flex: 3, child: DSBridgeWebView(controller: _controller)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final (String label, VoidCallback onPressed) in actions)
                    OutlinedButton(onPressed: onPressed, child: Text(label)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              flex: 1,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _logs.length,
                itemBuilder: (BuildContext context, int index) => Text(
                  _logs[index],
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

