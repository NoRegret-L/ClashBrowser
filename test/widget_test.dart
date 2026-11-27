import 'package:clashbrowser/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bootstrap displays explicit offline state', (tester) async {
    await tester.pumpWidget(const ClashBrowser());
    expect(find.text('代理未就绪 · 浏览器网络已禁用'), findsOneWidget);
  });

  testWidgets('import and delete a local node without enabling network', (tester) async {
    await tester.pumpWidget(const ClashBrowser());
    await tester.enterText(find.byKey(const Key('yaml-input')),
      'proxies: [{name: Demo, type: http, server: proxy.example, port: 80}]');
    await tester.tap(find.text('导入节点'));
    await tester.pumpAndSettle();
    expect(find.text('已导入 1 个节点'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('代理未就绪 · 浏览器网络已禁用'), findsOneWidget);
    await tester.ensureVisible(find.text('删除配置'));
    await tester.tap(find.text('删除配置'));
    await tester.pumpAndSettle();
    expect(find.text('Demo'), findsNothing);
  });
}
