// 앱 기본 동작 확인 테스트 : 로그인 화면이 열리고 역할 탭을 바꿀 수 있는지 확인
// (iPad 가로 크기로 화면을 맞춰서 소개 영역과 로그인 폼이 함께 보이는지 확인)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/app.dart';

void main() {
  testWidgets('로그인 화면 표시와 역할 탭 전환', (WidgetTester tester) async {
    // iPad Air 가로 크기 (논리 픽셀 1180 x 820)
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: AdminApp()));

    // 로그인 폼
    expect(find.text('아이디'), findsOneWidget);
    expect(find.text('비밀번호'), findsOneWidget);
    expect(find.text('본사 관리자 로그인'), findsOneWidget);

    // 매치 매니저 탭으로 전환하면 버튼 문구가 바뀜
    await tester.tap(find.text('매치 매니저').first);
    await tester.pump();
    expect(find.text('매치 매니저 로그인'), findsOneWidget);
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
