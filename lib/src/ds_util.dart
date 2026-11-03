import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 内部工具类，对应 iOS 的 `JSBUtil`。
abstract final class DSUtil {
  /// 日志前缀。
  static const String logTag = '[DSBridge]';

  /// 打印日志。
  static void log(String message) => debugPrint('$logTag $message');

  /// 将 [object] 编码为 JSON 字符串；无法编码时返回 `'{}'`
  /// （与 `JSBUtil.objToJsonString` 行为一致）。
  static String objToJsonString(Object? object) {
    try {
      return jsonEncode(object);
    } catch (e) {
      log('JSON encode failed: $e');
      return '{}';
    }
  }

  /// 解析 [jsonString]；解析失败时返回 `null`
  /// （与 `JSBUtil.jsonStringToObject` 行为一致）。
  static Object? jsonStringToObject(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(jsonString);
    } catch (e) {
      log('JSON decode failed: $e');
      return null;
    }
  }

  /// 将 [object] 编码为可安全嵌入 JavaScript 源码的 JSON 字面量。
  ///
  /// JSON 是 JavaScript（ES2019）的子集，但旧版引擎会把 U+2028 / U+2029
  /// 当作换行符，因此需要显式转义。
  static String toJsLiteral(Object? object) {
    return objToJsonString(object)
        .replaceAll('\u2028', r'\u2028')
        .replaceAll('\u2029', r'\u2029');
  }

  /// 按最后一个 `.` 拆分方法名：`"a.b.method"` -> `("a.b", "method")`。
  /// 没有命名空间时返回 `("", method)`。
  static (String namespace, String method) parseNamespace(String method) {
    final int index = method.lastIndexOf('.');
    if (index == -1) {
      return ('', method);
    }
    return (method.substring(0, index), method.substring(index + 1));
  }
}

