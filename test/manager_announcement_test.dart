// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 매니저 공지 조회·상세·검색·빈 결과·재시도를 Mock HTTP로 검증합니다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/headquarters/announcement_panel.dart';

import 'package:bootcamp_project_gongin_admin_app/view/dashboard/dashboard_page.dart';
import 'package:bootcamp_project_gongin_admin_app/model/login_role.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/login_notifier.dart';

import 'dashboard_test.dart' show DashboardLogin, FakeApi;

void main() {
  testWidgets('매니저 사이드바의 공지사항 메뉴가 조회 화면을 연다', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginProvider.overrideWith(DashboardLogin.new),
          operationsApiProvider.overrideWithValue(FakeApi()),
        ],
        child: MaterialApp(
          home: DashboardPage(
            role: LoginRole.manager,
            userId: 'test',
            onLogout: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('education-nav-3')));
    await tester.pumpAndSettle();
    expect(find.text('공IN · 공지사항'), findsOneWidget);
    expect(find.byType(AnnouncementPanel), findsOneWidget);
    expect(find.text('+ 공지 작성'), findsNothing);
  });

  testWidgets('매니저 API로 공지 상세를 표시하고 작성 기능 없이 검색한다', (tester) async {
    final paths = <Uri>[];
    final client = MockClient((request) async {
      paths.add(request.url);
      expect(request.method, 'GET');
      expect(request.url.path, '/announce/manager');
      final empty = request.url.queryParameters['keyword'] == '없는 공지';
      return http.Response(
        jsonEncode({
          'total': empty ? 0 : 1,
          'results': empty
              ? []
              : [
                  {
                    'a_seq': 1,
                    'a_title': '매니저 운영 안내',
                    'a_classify': '운영',
                    'a_detail': '출석 확인 안내 내용',
                    'h_name': '운영 담당자',
                    'a_date': '2026-10-30',
                    'a_target': ['매니저'],
                  },
                ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationsApiProvider.overrideWithValue(
            OperationsApi(client: client),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AnnouncementPanel(staffId: 'manager1', manager: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('+ 공지 작성'), findsNothing);
    await tester.tap(find.text('매니저 운영 안내'));
    await tester.pumpAndSettle();
    expect(find.text('출석 확인 안내 내용'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '없는 공지');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('조회된 공지가 없습니다.'), findsOneWidget);
    expect(paths.last.queryParameters['keyword'], '없는 공지');
  });

  testWidgets('공지 오류를 빈 결과로 숨기지 않고 다시 조회한다', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        calls == 1 ? '{}' : '{"total":0,"results":[]}',
        calls == 1 ? 500 : 200,
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationsApiProvider.overrideWithValue(
            OperationsApi(client: client),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AnnouncementPanel(staffId: 'manager1', manager: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('조회된 공지가 없습니다.'), findsNothing);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('조회된 공지가 없습니다.'), findsOneWidget);
    expect(calls, 2);
  });
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
