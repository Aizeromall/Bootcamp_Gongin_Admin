// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 실제 DB 없이 담당 일정·팀 상세 범위·날짜 변경·빈 결과·재시도를 검증합니다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/model/login_role.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/match/manager_schedule_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/login_notifier.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/manager_schedule_notifier.dart';

class ScheduleLogin extends LoginNotifier {
  @override
  StaffSession? build() =>
      const StaffSession(userId: 'manager1', role: LoginRole.manager);
  void change() => state = const AsyncData(
    StaffSession(userId: 'manager2', role: LoginRole.manager),
  );
}

http.Response jsonResponse(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> schedule(String date) => {
  'm_id': 'manager1',
  'r_date': date,
  'grounds': [
    {
      'g_code': 3,
      'g_name': '담당 구장',
      'g_num': 12,
      'slots': [
        {
          'rs_time': '08:00',
          're_time': '10:00',
          'slot_type': 'empty',
          'slot_type_name': '비어 있음',
        },
        {
          'rs_time': '10:00',
          're_time': '12:00',
          'slot_type': 'pickup',
          'slot_type_name': '실력매칭',
          'pickup': {'reservation_count': 4},
        },
        {
          'rs_time': '22:00',
          're_time': '24:00',
          'slot_type': 'team_match',
          'slot_type_name': '팀 대 팀 매칭',
          'rental': {'c_name': '팀장'},
          'team_match': {
            'team_code': 9,
            'home_t_name': '홈 팀',
            'away_t_name': '원정 팀',
          },
        },
      ],
    },
  ],
};
void main() {
  testWidgets('담당 일정의 팀 경기만 보여주고 해당 코드 상세만 조회한다', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final paths = <Uri>[];
    final client = MockClient((request) async {
      paths.add(request.url);
      if (request.url.path == '/match/schedule/manager1') {
        return jsonResponse(schedule(request.url.queryParameters['r_date']!));
      }
      if (request.url.path == '/match/operations') {
        return jsonResponse({
          'results': [
            {
              'g_code': 3,
              'g_name': '담당 구장',
              'r_seq': 5,
              'r_date': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 9))
                  .toIso8601String()
                  .substring(0, 10),
              'rs_time': '10:00',
              'status': 'completed',
              'count': 4,
            },
          ],
        });
      }
      expect(request.url.path, '/match/team_match/9');
      return jsonResponse({
        'team_code': 9,
        'status': 'finished',
        'status_name': '경기 종료',
        'home_team': {'t_name': '홈 팀'},
        'away_team': {'t_name': '원정 팀'},
        'result': {'home_score': 4, 'away_score': 2},
      });
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
            body: ManagerSchedulePanel(managerId: 'manager1', history: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('홈 팀 vs 원정 팀'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule:3|10:00|null')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule:3|08:00|null')), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '팀매칭'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule:3|10:00|null')), findsNothing);
    await tester.tap(find.text('홈 팀 vs 원정 팀'));
    await tester.pumpAndSettle();
    expect(find.text('4 : 2'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '실력매칭'));
    await tester.pumpAndSettle();
    expect(find.text('4 : 2'), findsNothing);
    expect(find.byKey(const ValueKey('schedule:3|10:00|null')), findsOneWidget);
    expect(find.text('홈 팀 vs 원정 팀'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '전체'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule:3|10:00|null')), findsOneWidget);
    expect(find.text('홈 팀 vs 원정 팀'), findsOneWidget);
    expect(paths.where((uri) => uri.path.contains('/schedule/')).length, 1);
    await tester.tap(find.text('홈 팀 vs 원정 팀'));
    await tester.pumpAndSettle();
    expect(find.text('22:00 ~ 24:00'), findsWidgets);
    expect(paths.where((uri) => uri.path == '/match/team_match'), isEmpty);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('목록으로'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('목록으로'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('다음 날짜'));
    await tester.pumpAndSettle();
    expect(
      paths
          .where((uri) => uri.path.contains('/schedule/'))
          .map((uri) => uri.queryParameters['r_date'])
          .toSet()
          .length,
      2,
    );
    expect(find.text('4 : 2'), findsNothing);
  });
  test('일정에 없는 코드의 상세 조회와 다른 계정의 일정 접근을 막는다', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return jsonResponse(schedule('2026-10-29'));
    });
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        loginProvider.overrideWith(ScheduleLogin.new),
        operationsApiProvider.overrideWithValue(OperationsApi(client: client)),
      ],
    );
    addTearDown(container.dispose);
    final query = (managerId: 'manager1', date: '2026-10-29');
    await expectLater(
      container.read(
        scheduledTeamMatchProvider((
          schedule: query,
          groundCode: '3',
          start: '22:00',
          code: 99,
        )).future,
      ),
      throwsA(isA<OperationsApiException>()),
    );
    expect(paths, ['/match/schedule/manager1']);
    (container.read(loginProvider.notifier) as ScheduleLogin).change();
    await expectLater(
      container.read(managerScheduleProvider(query).future),
      throwsA(isA<OperationsApiException>()),
    );
    expect(paths.length, 1);
  });
  testWidgets('오류 뒤 재시도로 빈 담당 일정을 표시한다', (tester) async {
    var fail = true;
    final client = MockClient(
      (request) async => fail
          ? jsonResponse({'detail': '조회 실패'}, 500)
          : jsonResponse({
              'm_id': 'manager1',
              'r_date': request.url.queryParameters['r_date'],
              'grounds': [],
            }),
    );
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
          home: Scaffold(body: ManagerSchedulePanel(managerId: 'manager1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('다시 시도'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('선택한 조건에 해당하는 매치가 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('날짜를 빠르게 바꿔도 늦은 이전 응답은 새 일정에 섞이지 않는다', () async {
    final old = Completer<http.Response>();
    final client = MockClient(
      (request) => request.url.queryParameters['r_date'] == '2026-10-29'
          ? old.future
          : Future.value(jsonResponse(schedule('2026-10-30'))),
    );
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        loginProvider.overrideWith(ScheduleLogin.new),
        operationsApiProvider.overrideWithValue(OperationsApi(client: client)),
      ],
    );
    addTearDown(container.dispose);
    final first = container.read(
      managerScheduleProvider((managerId: 'manager1', date: '2026-10-29'))
          .future,
    );
    final second = await container.read(
      managerScheduleProvider((managerId: 'manager1', date: '2026-10-30'))
          .future,
    );
    old.complete(jsonResponse(schedule('2026-10-29')));
    await first;
    expect(second.date, '2026-10-30');
  });
  test('예정·완료를 분리하고 날짜가 지난 결과 대기 팀 경기는 완료에서 제외한다', () async {
    for (final teamStatus in ['scheduled', 'finished', 'waiting_result']) {
      final client = MockClient((request) async {
        if (request.url.path.contains('/schedule/')) {
          return jsonResponse(schedule('2026-10-29'));
        }
        if (request.url.path == '/match/operations') {
          return jsonResponse({
            'results': [
              for (final status in [
                'attendance',
                'teams',
                'live',
                'review',
                'completed',
              ])
                {
                  'g_code': 4,
                  'g_name': status,
                  'r_date': '2026-10-29',
                  'rs_time': '10:00',
                  'status': status,
                },
              {
                'g_code': 4,
                'g_name': '다른 날짜',
                'r_date': '2026-10-28',
                'rs_time': '10:00',
                'status': 'completed',
              },
            ],
          });
        }
        return jsonResponse({
          'team_code': 9,
          'status': teamStatus,
          'team_start': teamStatus == 'waiting_result'
              ? '2020-01-01T22:00:00'
              : '2026-10-29T22:00:00',
        });
      });
      final container = ProviderContainer(
        overrides: [
          // 수정 일 : 2026-10-30 / 작업자 : 양태건
          // 날짜 경과와 무관하게 예정·완료 분류 계약을 검사합니다.
          managerTodayProvider.overrideWithBuild(
            (ref, notifier) => DateTime(2026, 10, 29),
          ),
          loginProvider.overrideWith(ScheduleLogin.new),
          operationsApiProvider.overrideWithValue(
            OperationsApi(client: client),
          ),
        ],
      );
      final upcoming = await container.read(
        managerMatchDayProvider((
          managerId: 'manager1',
          date: '2026-10-29',
          history: false,
        )).future,
      );
      final history = await container.read(
        managerMatchDayProvider((
          managerId: 'manager1',
          date: '2026-10-29',
          history: true,
        )).future,
      );
      expect(
        upcoming.entries
            .where((entry) => entry.operation != null)
            .map((entry) => entry.operation!['status']),
        ['attendance', 'teams'],
      );
      expect(
        history.entries
            .where((entry) => entry.operation != null)
            .map((entry) => entry.operation!['status']),
        ['completed'],
      );
      expect(
        upcoming.entries.where((entry) => entry.team != null).length,
        teamStatus == 'scheduled' ? 1 : 0,
      );
      expect(
        history.entries.where((entry) => entry.team != null).length,
        teamStatus == 'finished' ? 1 : 0,
      );
      container.dispose();
      client.close();
    }
  });
  test('내 매치의 어제 조회는 요청하지 않고 지난 매치의 어제 완료 기록은 유지한다', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.contains('/schedule/')) {
        return jsonResponse({
          'm_id': 'manager1',
          'r_date': '2026-10-28',
          'grounds': [],
        });
      }
      return jsonResponse({
        'results': [
          {
            'g_code': 1,
            'g_name': '어제 완료 구장',
            'r_date': '2026-10-28',
            'rs_time': '18:00',
            'status': 'completed',
          },
        ],
      });
    });
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        loginProvider.overrideWith(ScheduleLogin.new),
        managerTodayProvider.overrideWithBuild(
          (ref, notifier) => DateTime(2026, 10, 29),
        ),
        operationsApiProvider.overrideWithValue(OperationsApi(client: client)),
      ],
    );
    addTearDown(container.dispose);
    final current = await container.read(
      managerMatchDayProvider((
        managerId: 'manager1',
        date: '2026-10-28',
        history: false,
      )).future,
    );
    expect(current.entries, isEmpty);
    expect(paths, isEmpty);
    final history = await container.read(
      managerMatchDayProvider((
        managerId: 'manager1',
        date: '2026-10-28',
        history: true,
      )).future,
    );
    expect(history.entries.single.ground.name, '어제 완료 구장');
    expect(paths.length, 2);
  });
  testWidgets('내 매치는 오늘 이전 이동과 달력 선택을 막고 지난 매치는 허용한다', (tester) async {
    final client = MockClient(
      (request) async => jsonResponse(
        request.url.path.contains('/schedule/')
            ? {
                'm_id': 'manager1',
                'r_date': request.url.queryParameters['r_date'],
                'grounds': [],
              }
            : {'results': []},
      ),
    );
    addTearDown(client.close);
    for (final history in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            loginProvider.overrideWith(ScheduleLogin.new),
            managerTodayProvider.overrideWithBuild(
              (ref, notifier) => DateTime(2026, 10, 29),
            ),
            operationsApiProvider.overrideWithValue(
              OperationsApi(client: client),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ManagerSchedulePanel(
                managerId: 'manager1',
                history: history,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final previous = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '이전 날짜',
        ),
      );
      expect(previous.onPressed != null, history);
      await tester.tap(find.byTooltip('다음 날짜'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '이전 날짜',
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('이전 날짜'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-10-29'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .firstDate,
        history ? DateTime(2020) : DateTime(2026, 10, 29),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
