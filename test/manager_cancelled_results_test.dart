// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 유형별 취소 탭·종목 필터·예약 회원·빈 결과·오류·계정 범위를 Mock으로 검증합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/service/match_updates_service.dart';
import 'package:bootcamp_project_gongin_admin_app/view/match/manager_result_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/login_notifier.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/manager_result_notifier.dart';

import 'manager_schedule_test.dart' show ScheduleLogin, jsonResponse;

Map<String, dynamic> cancelled() => {
  'g_code': 7,
  'g_name': '취소 구장',
  'g_num': 12,
  'r_date': '2026-10-30',
  'rs_time': '18:00',
  're_time': '20:00',
  'r_c_category': '2',
  'canceled_count': 2,
  'r_cancel_date': '2026-10-30T17:00:00',
  'members': [
    {'r_seq': 1, 'name': '회원 하나', 'current_team': '홈팀'},
    {'r_seq': 2, 'name': '회원 둘', 'current_team': '원정팀'},
  ],
};

Widget app(OperationsApi api, String kind) => ProviderScope(
  overrides: [
    loginProvider.overrideWith(ScheduleLogin.new),
    operationsApiProvider.overrideWithValue(api),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: ManagerResultsPanel(managerId: 'manager1', kind: kind),
    ),
  ),
);

void main() {
  for (final kind in ['pickup', 'team']) {
    testWidgets('$kind 결과와 취소를 분리하고 취소 사유·예약 회원·종목 필터를 표시한다', (tester) async {
      tester.view.physicalSize = const Size(1200, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final paths = <Uri>[];
      final client = MockClient((request) async {
        paths.add(request.url);
        if (request.url.path == '/match/manager/results') {
          return jsonResponse({'results': []});
        }
        expect(request.url.path, '/match/manage/cancel/manager1');
        expect(request.url.queryParameters['kind'], kind);
        return jsonResponse({
          'results': request.url.queryParameters['e_code'] == 'BASKETBALL'
              ? []
              : [
                  {...cancelled(), 'kind': kind},
                ],
        });
      });
      addTearDown(client.close);
      await tester.pumpWidget(app(OperationsApi(client: client), kind));
      await tester.pumpAndSettle();
      expect(paths.where((p) => p.path.contains('/manage/cancel/')), isEmpty);
      await tester.tap(find.text('취소 내역'));
      await tester.pumpAndSettle();
      expect(find.text('취소 구장'), findsWidgets);
      expect(find.text('우천·기상악화'), findsOneWidget);
      expect(find.text('회원 하나'), findsOneWidget);
      expect(find.text('현재 소속팀 · 홈팀'), findsOneWidget);
      expect(find.text('회원 둘'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '🏀 농구'));
      await tester.pumpAndSettle();
      expect(paths.last.queryParameters, {
        'kind': kind,
        'e_code': 'BASKETBALL',
      });
      expect(
        find.text('취소된 ${kind == 'team' ? '팀매칭' : '실력매칭'}이 없습니다.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('팀매칭 취소 예약 회원에 저장된 노쇼 패널티와 전후 점수를 표시한다', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MockClient((request) async {
      if (request.url.path == '/match/manager/results') {
        return jsonResponse({'results': []});
      }
      return jsonResponse({
        'results': [
          {
            ...cancelled(),
            'kind': 'team',
            'r_c_category': '3',
            'members': [
              {
                'r_seq': 1,
                'name': '차감 회원',
                'current_team': '홈팀',
                'attendance': false,
                'rating_before': 1500,
                'rating_after': 1470,
                'rating_change': -30,
                'penalty_applied': true,
              },
              {
                'r_seq': 2,
                'name': '하한 회원',
                'current_team': '원정팀',
                'attendance': false,
                'rating_before': 1010,
                'rating_after': 1000,
                'rating_change': -10,
                'penalty_applied': true,
              },
              {
                'r_seq': 3,
                'name': '미기록 회원',
                'current_team': '홈팀',
                'attendance': false,
              },
              {
                'r_seq': 4,
                'name': '출석 회원',
                'current_team': '원정팀',
                'attendance': true,
              },
            ],
          },
        ],
      });
    });
    addTearDown(client.close);
    await tester.pumpWidget(app(OperationsApi(client: client), 'team'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소 내역'));
    await tester.pumpAndSettle();
    expect(find.text('노쇼 패널티 -30점'), findsOneWidget);
    expect(find.text('1500점 → 1470점'), findsOneWidget);
    expect(find.text('노쇼 패널티 -10점'), findsOneWidget);
    expect(find.text('패널티 기록 없음'), findsOneWidget);
    expect(find.text('패널티 없음'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('취소 조회 실패는 빈 내역으로 숨기지 않고 재시도한다', (tester) async {
    var fails = true;
    final client = MockClient((request) async {
      if (request.url.path == '/match/manager/results') {
        return jsonResponse({'results': []});
      }
      return fails
          ? jsonResponse({'detail': '조회 실패'}, 500)
          : jsonResponse({'results': []});
    });
    addTearDown(client.close);
    await tester.pumpWidget(app(OperationsApi(client: client), 'team'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소 내역'));
    await tester.pumpAndSettle();
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('취소된 팀매칭이 없습니다.'), findsNothing);
    fails = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('취소된 팀매칭이 없습니다.'), findsOneWidget);
  });
  test('유형이 없거나 다른 서버 응답을 취소 내역에 섞지 않는다', () async {
    for (final kind in [null, 'pickup']) {
      final client = MockClient(
        (request) async => jsonResponse({
          'results': [
            {...cancelled(), 'kind': kind},
          ],
        }),
      );
      try {
        await expectLater(
          MatchUpdatesService(OperationsApi(client: client))
              .cancellations(managerId: 'manager1', kind: 'team'),
          throwsA(isA<OperationsApiException>()),
        );
      } finally {
        client.close();
      }
    }
  });
  test('다른 담당자의 취소 내역을 요청하지 않는다', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return jsonResponse({'results': []});
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
        managerCancelledResultsProvider((
          managerId: 'another',
          kind: 'team',
          sport: 'all',
        )).future,
      ),
      throwsA(isA<OperationsApiException>()),
    );
    expect(calls, 0);
  });
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
