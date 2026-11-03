import 'dart:async';

import 'package:webview_flutter_dsbridge/webview_flutter_dsbridge.dart';

/// Native APIs without namespace, mirrors `JsApiTest` of the iOS demo.
///
/// Called from JavaScript via `dsBridge.call("testSyn", ...)`.
class JsApi extends DSJavascriptObject {
  JsApi() {
    registerSyncMethod('testSyn', testSyn);
    registerAsyncMethod('testAsyn', testAsyn);
    registerSyncMethod('testNoArgSyn', testNoArgSyn);
    registerAsyncMethod('testNoArgAsyn', testNoArgAsyn);
    registerAsyncMethod('callProgress', callProgress);
  }

  final Set<Timer> _timers = <Timer>{};

  Object? testSyn(Object? msg) => '$msg[ syn call]';

  void testAsyn(Object? msg, DSCompletionHandler handler) {
    handler('$msg [ asyn call]');
  }

  Object? testNoArgSyn(Object? args) => 'testNoArgSyn called [ syn call]';

  void testNoArgAsyn(Object? args, DSCompletionHandler handler) {
    handler('testNoArgAsyn called [ asyn call]');
  }

  /// Reports a countdown every second; the JS callback is kept alive with
  /// `complete: false` until the last value.
  void callProgress(Object? args, DSCompletionHandler handler) {
    int value = 10;
    handler(value--, complete: false);
    late final Timer timer;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (value != -1) {
        handler(value--, complete: false);
      } else {
        handler(0);
        timer.cancel();
        _timers.remove(timer);
      }
    });
    _timers.add(timer);
  }

  void dispose() {
    for (final Timer timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }
}

/// Native APIs under the `echo` namespace, mirrors `JsEchoApi`.
///
/// Called from JavaScript via `dsBridge.call("echo.syn", ...)`.
class JsEchoApi extends DSJavascriptObject {
  JsEchoApi() {
    registerSyncMethod('syn', (Object? args) => args);
    registerAsyncMethod('asyn', (Object? args, DSCompletionHandler handler) => handler(args));
  }
}

