import 'package:flutter/material.dart';

import 'pages/dsbridge_demo_page.dart';
import 'pages/dsbridge_web_page.dart';

void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DSBridge Demo',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const HomePage(),
    );
  }
}

/// 示例入口列表。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const String flutterUrl = 'https://flutter.dev';

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DSBridge Demo')),
      body: ListView(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('DSBridge 双向通信示例'),
            subtitle: const Text('assets/web/test.html'),
            onTap: () => _push(context, const DSBridgeDemoPage()),
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Flutter 官网（使用网页标题）'),
            subtitle: const Text(flutterUrl),
            onTap: () => _push(context, const DSBridgeWebPage(url: flutterUrl)),
          ),
          ListTile(
            leading: const Icon(Icons.title),
            title: const Text('Flutter 官网（自定义标题）'),
            subtitle: const Text(flutterUrl),
            onTap: () => _push(
              context,
              const DSBridgeWebPage(url: flutterUrl, title: 'Flutter 官网'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('错误页示例'),
            subtitle: const Text('https://not-exist.flutter.invalid'),
            onTap: () => _push(
              context,
              const DSBridgeWebPage(url: 'https://not-exist.flutter.invalid'),
            ),
          ),
        ],
      ),
    );
  }
}
