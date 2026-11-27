import 'package:flutter/material.dart';

void main() => runApp(const ClashBrowser());

class ClashBrowser extends StatelessWidget {
  const ClashBrowser({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ClashBrowser',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: Scaffold(
      appBar: AppBar(title: const Text('ClashBrowser')),
      body: const SafeArea(
        child: Center(child: Text('代理未就绪 · 浏览器网络已禁用')),
      ),
    ),
  );
}
