// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 결과·취소 내역을 경기일로 필터하고 날짜 이동·달력·전체 복귀를 검증합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/model/manager_result_model.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/match/manager_result_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/login_notifier.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/manager_schedule_notifier.dart';

import 'manager_schedule_test.dart' show ScheduleLogin, jsonResponse;
import 'manager_results_panel_test.dart' show resultRow;

void main() {
  test('한국 경기일 변환과 날짜 없음 처리', () {
    expect(managerGameDate('2026-10-30'), '2026-10-30');
    expect(managerGameDate('2026-10-29T18:00:00Z'), '2026-10-30');
    expect(managerGameDate(null), isNull);
    expect(managerGameDate('—'), isNull);
  });
  for (final kind in ['pickup', 'team']) {
    testWidgets('$kind 경기 결과와 취소 내역의 날짜 선택·이동·전체 복귀', (tester) async {
      tester.view.physicalSize = const Size(1200, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var listCalls = 0, cancelCalls = 0;
      final results = [
        {
          ...resultRow('9'),
          'kind': kind,
          'date': '2026-10-29',
          'ground': '어제 구장',
        },
        {
          ...resultRow('10'),
          'kind': kind,
          'date': '2026-10-30',
          'ground': '오늘 구장',
        },
        {
          ...resultRow('11'),
          'kind': kind,
          'date': null,
          'recorded_at': '2026-10-30T12:00:00',
          'ground': '일자 미기록',
        },
      ];
      final client = MockClient((request) async {
        if (request.url.path == '/match/manager/results') {
          listCalls++;
          return jsonResponse({'results': results});
        }
        if (request.url.path.startsWith('/match/manager/results/')) {
          return jsonResponse(
            results.firstWhere(
              (r) => r['code'] == request.url.pathSegments.last,
            ),
          );
        }
        if (request.url.path.startsWith('/match/team_match/')) {
          return jsonResponse({});
        }
        expect(request.url.path, '/match/manage/cancel/manager1');
        expect(request.url.queryParameters['kind'], kind);
        cancelCalls++;
        return jsonResponse({
          'results': [
            for (final day in ['29', '30'])
              {
                'kind': kind,
                'g_code': day,
                'g_name': '취소 $day일 구장',
                'r_date': '2026-10-$day',
                'rs_time': '18:00',
                're_time': '20:00',
                'r_c_category': '2',
                'canceled_count': 2,
                'r_cancel_date': day == '29'
                    ? '2026-10-30T10:00:00'
                    : '2026-10-29T10:00:00',
              },
          ],
        });
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            loginProvider.overrideWith(ScheduleLogin.new),
            managerTodayProvider.overrideWithBuild(
              (ref, notifier) => DateTime(2026, 10, 30),
            ),
            operationsApiProvider.overrideWithValue(
              OperationsApi(client: client),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ManagerResultsPanel(managerId: 'manager1', kind: kind),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('result:9')), findsOneWidget);
      expect(find.byKey(const ValueKey('result:10')), findsOneWidget);
      expect(find.byKey(const ValueKey('result:11')), findsOneWidget);
      await tester.tap(find.text('오늘'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('result:10')), findsOneWidget);
      expect(find.byKey(const ValueKey('result:9')), findsNothing);
      expect(find.byKey(const ValueKey('result:11')), findsNothing);
      await tester.tap(find.byTooltip('이전 경기일'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('result:9')), findsOneWidget);
      expect(find.byKey(const ValueKey('result:10')), findsNothing);
      await tester.tap(find.byTooltip('다음 경기일'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('다음 경기일'));
      await tester.pumpAndSettle();
      expect(find.text('선택한 경기일의 결과가 없습니다.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('result-date-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('29').last);
      await tester.pumpAndSettle();
      final ok = MaterialLocalizations.of(
        tester.element(find.byType(DatePickerDialog)),
      ).okButtonLabel;
      await tester.tap(find.text(ok));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('result:9')), findsOneWidget);
      await tester.tap(find.text('전체 기록'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('result:11')), findsOneWidget);
      expect(listCalls, 1);
      await tester.tap(find.text('오늘'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소 내역'));
      await tester.pumpAndSettle();
      expect(find.text('취소 30일 구장'), findsWidgets);
      expect(find.text('취소 29일 구장'), findsNothing);
      await tester.tap(find.byTooltip('이전 경기일'));
      await tester.pumpAndSettle();
      expect(find.text('취소 29일 구장'), findsWidgets);
      expect(find.text('취소 30일 구장'), findsNothing);
      await tester.tap(find.text('전체 기록'));
      await tester.pumpAndSettle();
      expect(find.text('취소 29일 구장'), findsWidgets);
      expect(find.text('취소 30일 구장'), findsWidgets);
      expect(cancelCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
