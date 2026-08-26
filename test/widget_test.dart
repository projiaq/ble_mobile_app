import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app boots to scan page', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AiotApp()));
    await tester.pumpAndSettle();

    expect(find.text('现场总览'), findsOneWidget);
    expect(find.text('客户模式'), findsOneWidget);
    // 自动扫描(测试环境无 BLE)→ 出错但页面正常渲染,扫描按钮仍在
    expect(find.widgetWithText(FilledButton, '扫描'), findsOneWidget);
  });
}
