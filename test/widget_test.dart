import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/app.dart';

void main() {
  testWidgets('역할 선택 없이 공통 로그인과 입력 검증을 표시한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GonginApp()));
    expect(find.text('담당자 로그인'), findsOneWidget);
    expect(find.text('본사 관리자'), findsNothing);
    expect(find.text('매니저'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pump();
    expect(find.text('아이디를 입력해 주세요.'), findsOneWidget);
    expect(find.text('비밀번호를 입력해 주세요.'), findsOneWidget);
  });
}
