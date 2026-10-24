import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/app.dart';

void main() {
  testWidgets('각 역할에서 해당 로그인 화면으로 진입한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GonginApp()));
    await tester.tap(find.text('본사 관리자'));
    await tester.pumpAndSettle();
    expect(find.text('본사 관리자 로그인'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('매니저'));
    await tester.pumpAndSettle();
    expect(find.text('매니저 로그인'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pump();
    expect(find.text('아이디를 입력해 주세요.'), findsOneWidget);
    expect(find.text('비밀번호를 입력해 주세요.'), findsOneWidget);
  });
}
