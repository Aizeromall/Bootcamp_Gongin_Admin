// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 종목·유형별 실제 결과 조회, 개인 등급·변동 미보관, 작은 화면을 Mock으로 검증합니다.
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/match/manager_result_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/view/match/manager_schedule_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/login_notifier.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/manager_result_notifier.dart';

import 'package:bootcamp_project_gongin_admin_app/vm/manager_schedule_notifier.dart';

import 'manager_schedule_test.dart' show ScheduleLogin, jsonResponse;

Map<String, dynamic> resultRow(String code) => {
  'code': code,
  'kind': 'team',
  'ground': '결과 구장',
  'date': '2026-10-28',
  'time': '18:00',
  'home': '홈 팀',
  'away': '원정 팀',
  'home_score': 4,
  'away_score': 2,
  'stat_columns': [
    {'key': 'G', 'label': '골'},
    {'key': 'A', 'label': '도움'},
  ],
  'sides': [
    {
      'name': '홈 팀',
      'members': [
        {
          'name': '회원 하나',
          'current_tier': '비기너 1',
          'current_rating': 1520,
          'rating_change': null,
          'stats': {'G': 2, 'A': 1},
        },
      ],
    },
  ],
  'team_summary': [
    {
      'name': '홈 팀',
      'result': '승',
      'score': 4,
      'current_rating': 1510,
      'rating_change': null,
      'stats': {'G': 4},
    },
  ],
};
void main() {
  testWidgets('팀 결과에 현재 레벨·점수와 미보관 변동을 구분하고 종목 필터를 서버에 보낸다', (tester) async {
    tester.view.physicalSize = const Size(1200, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final paths = <Uri>[];
    final client = MockClient((request) async {
      paths.add(request.url);
      if (request.url.path == '/match/manager/results') {
        return jsonResponse({
          'results': [resultRow('9')],
        });
      }
      if (request.url.path == '/match/team_match/9') return jsonResponse({});
      expect(request.url.path, '/match/manager/results/9');
      return jsonResponse(resultRow('9'));
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginProvider.overrideWith(ScheduleLogin.new),
          operationsApiProvider.overrideWithValue(
            OperationsApi(client: client),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ManagerResultsPanel(managerId: 'manager1', kind: 'team'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('4 : 2'), findsOneWidget);
    expect(find.text('비기너 1'), findsOneWidget);
    expect(find.text('1520'), findsOneWidget);
    expect(find.text('변동 기록 없음'), findsWidgets);
    expect(find.text('+20'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '🏀 농구'));
    await tester.pumpAndSettle();
    expect(
      paths
          .where((uri) => uri.path == '/match/manager/results')
          .last
          .queryParameters,
      {'kind': 'team', 'e_code': 'BASKETBALL'},
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('작은 화면 결과 선택·복귀와 빈 결과·오류 재시도를 제공한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var mode = 'error';
    final client = MockClient((request) async {
      if (mode == 'error') return jsonResponse({'detail': '실패'}, 500);
      if (request.url.path == '/match/manager/results') {
        return jsonResponse({
          'results': mode == 'empty' ? [] : [resultRow('9')],
        });
      }
      return jsonResponse(resultRow('9'));
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginProvider.overrideWith(ScheduleLogin.new),
          operationsApiProvider.overrideWithValue(
            OperationsApi(client: client),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ManagerResultsPanel(managerId: 'manager1', kind: 'pickup'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    mode = 'empty';
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('등록된 경기 결과가 없습니다.'), findsOneWidget);
    mode = 'data';
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('결과 새로고침'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('결과 구장'));
    await tester.pumpAndSettle();
    expect(find.text('목록으로'), findsOneWidget);
    expect(find.text('4 : 2'), findsOneWidget);
    await tester.tap(find.text('목록으로'));
    await tester.pumpAndSettle();
    expect(find.text('결과 구장'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('결과 provider는 다른 계정의 결과를 요청하지 않는다', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return jsonResponse({});
    });
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        loginProvider.overrideWith(ScheduleLogin.new),
        operationsApiProvider.overrideWithValue(OperationsApi(client: client)),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(
        managerResultsProvider((
          managerId: 'other',
          kind: 'pickup',
          sport: 'all',
        )).future,
      ),
      throwsA(isA<OperationsApiException>()),
    );
    expect(calls, 0);
  });
  testWidgets('내 매치는 전체 조회 없이 선택 날짜의 경기만 종목별로 표시한다', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      if (request.url.path.startsWith('/match/schedule/')) {
        return jsonResponse({
          'm_id': 'manager1',
          'r_date': request.url.queryParameters['r_date'],
          'grounds': [],
        });
      }
      expect(request.url.path, '/match/operations');
      calls++;
      return jsonResponse({
        'results': [
          {
            'r_seq': 1,
            'g_code': 1,
            'g_name': '내일 축구장',
            'r_date': '2030-01-02',
            'rs_time': '18:00',
            'e_code': 'SOCCER',
            'status': 'attendance',
          },
          {
            'r_seq': 2,
            'g_code': 2,
            'g_name': '다음날 야구장',
            'r_date': '2030-01-02',
            'rs_time': '18:00',
            'e_code': 'BASEBALL',
            'status': 'attendance',
          },
        ],
        'teams': [],
      });
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          managerTodayProvider.overrideWithBuild(
            (ref, notifier) => DateTime(2030, 1, 2),
          ),
          loginProvider.overrideWith(ScheduleLogin.new),
          operationsApiProvider.overrideWithValue(
            OperationsApi(client: client),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ManagerSchedulePanel(managerId: 'manager1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('오늘 이후 전체'), findsNothing);
    expect(find.text('2030-01-02'), findsOneWidget);
    expect(find.text('내일 축구장'), findsOneWidget);
    expect(find.text('다음날 야구장'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '⚾ 야구'));
    await tester.pumpAndSettle();
    expect(find.text('내일 축구장'), findsNothing);
    expect(find.text('다음날 야구장'), findsOneWidget);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
