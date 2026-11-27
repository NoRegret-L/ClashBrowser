import 'package:clashbrowser/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bootstrap displays explicit offline state', (tester) async {
    await tester.pumpWidget(const ClashBrowser());
    expect(find.text('代理未就绪 · 浏览器网络已禁用'), findsOneWidget);
  });
}
