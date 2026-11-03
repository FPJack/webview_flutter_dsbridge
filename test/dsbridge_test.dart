import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_dsbridge/src/ds_internal_apis.dart';
import 'package:webview_flutter_dsbridge/src/ds_util.dart';
import 'package:webview_flutter_dsbridge/webview_flutter_dsbridge.dart';

void main() {
  group('DSUtil', () {
    test('parseNamespace splits on the last dot', () {
      expect(DSUtil.parseNamespace('testSyn'), ('', 'testSyn'));
      expect(DSUtil.parseNamespace('echo.syn'), ('echo', 'syn'));
      expect(DSUtil.parseNamespace('a.b.c'), ('a.b', 'c'));
    });

    test('json helpers are fault tolerant', () {
      expect(DSUtil.objToJsonString(<String, Object?>{'code': 0}), '{"code":0}');
      expect(DSUtil.objToJsonString(Object()), '{}');
      expect(DSUtil.jsonStringToObject('{"data":1}'), <String, Object?>{'data': 1});
      expect(DSUtil.jsonStringToObject('not json'), isNull);
      expect(DSUtil.jsonStringToObject(null), isNull);
    });

    test('toJsLiteral escapes JS line terminators', () {
      expect(DSUtil.toJsLiteral('a\u2028b\u2029'), r'"a\u2028b\u2029"');
    });
  });

  group('DSJavascriptObject', () {
    test('registers and looks up methods by type', () {
      final DSJavascriptObject object = DSJavascriptObject(
        syncMethods: <String, DSSyncMethod>{'syn': (Object? a) => a},
        asyncMethods: <String, DSAsyncMethod>{
          'asyn': (Object? a, DSCompletionHandler h) => h(a),
        },
      );
      expect(object.hasMethod('syn'), isTrue);
      expect(object.hasMethod('syn', DSMethodType.syn), isTrue);
      expect(object.hasMethod('syn', DSMethodType.asyn), isFalse);
      expect(object.hasMethod('asyn', DSMethodType.asyn), isTrue);
      expect(object.hasMethod('xx'), isFalse);

      object.unregisterMethod('syn');
      expect(object.hasMethod('syn'), isFalse);
    });

    test('DSMethodType.parse falls back to all', () {
      expect(DSMethodType.parse('syn'), DSMethodType.syn);
      expect(DSMethodType.parse(' asyn '), DSMethodType.asyn);
      expect(DSMethodType.parse(null), DSMethodType.all);
      expect(DSMethodType.parse('unknown'), DSMethodType.all);
    });
  });

  test('DSInternalApis forwards messages', () {
    final List<DSInternalApi> received = <DSInternalApi>[];
    final DSInternalApis apis = DSInternalApis((DSInternalApi type, Map<String, Object?> args) {
      received.add(type);
      return type == DSInternalApi.hasNativeMethod ? true : null;
    });
    expect(apis.syncMethod('hasNativeMethod')!(<String, Object?>{'name': 'x'}), isTrue);
    apis.syncMethod('dsinit')!(null);
    expect(received, <DSInternalApi>[DSInternalApi.hasNativeMethod, DSInternalApi.dsinit]);
  });
}

