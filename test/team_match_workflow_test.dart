// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 팀 예약자 출석 → 팀 설정 생략 → 전체 화면 기록을 Mock API로 검증합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/match/match_page.dart';
import 'package:bootcamp_project_gongin_admin_app/view/match/match_cancel_dialog.dart';

import 'dashboard_test.dart' show FakeApi;

class TeamApi extends FakeApi {
  TeamApi() {
    state['fixed_sides'] = {'1': 'A', '2': 'B'};
    state['team_names'] = ['홈팀', '원정팀'];
  }
  final actions = <String>[];
  bool failCancel = false;
  Map<String, dynamic>? cancelBody;
  int cancelCalls = 0;
  @override
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> json,
  ) async {
    expect(path, '/match/manage/cancel/manager1');
    cancelCalls++;
    cancelBody = json;
    if (failCancel) throw const OperationsApiException(409, '취소 조건을 확인해 주세요.');
    return {'result': 'OK'};
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    if (path == '/match/team_operations/9') {
      if (json != null) actions.add('${json['action']}');
      if (json?['action'] == 'start') {
        state['assignments'] = Map<String, String>.from(state['fixed_sides']);
      }
      return super.request('/match/operations/1', json: json, form: form);
    }
    return super.request(path, json: json, form: form);
  }
}

void main() {
  testWidgets('팀매칭 취소 버튼은 경기코드를 전송하고 실패 후 재시도하며 화면을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(1200, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = TeamApi()..failCancel = true;
    var cancelled = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [operationsApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(
            body: MatchWorkflowPage(
              teamCode: 9,
              embedded: true,
              managerId: 'manager1',
              onCancelled: () => cancelled = true,
              match: const {
                'g_name': '구장',
                'g_code': 1,
                'r_seq': 9,
                'r_date': '2026-10-30',
                'rs_time': '18:00',
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('경기 취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('경기 취소'));
    await tester.pumpAndSettle();
    expect(find.byType(MatchCancelDialog), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('우천·기상악화').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('예약 취소 확정'));
    await tester.pumpAndSettle();
    expect(cancelled, isFalse);
    expect(find.text('취소 조건을 확인해 주세요.'), findsOneWidget);
    api.failCancel = false;
    await tester.tap(find.text('예약 취소 확정'));
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    expect(api.cancelCalls, 2);
    expect(api.cancelBody, {
      'g_code': '1',
      'r_date': '2026-10-30',
      'rs_time': '18:00',
      'r_c_category': 2,
      'team_code': 9,
    });
    expect(find.byType(MatchCancelDialog), findsNothing);
    expect(find.byType(MatchWorkflowPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('홈·원정 예약자 출석 후 바로 전체 화면 경기 기록', (tester) async {
    tester.view.physicalSize = const Size(1200, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = TeamApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [operationsApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(
            body: MatchWorkflowPage(
              teamCode: 9,
              embedded: true,
              match: {'g_name': '구장', 'r_seq': 9},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('선수1 · 홈팀'), findsOneWidget);
    expect(find.text('선수2 · 원정팀'), findsOneWidget);
    expect(find.text('경기 시작 · 팀 설정'), findsNothing);
    await tester.ensureVisible(find.text('전원 출석'));
    await tester.tap(find.text('전원 출석'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('경기 시작'));
    await tester.tap(find.text('경기 시작'));
    await tester.pumpAndSettle();
    expect(api.actions, ['attendance', 'attendance', 'start']);
    expect(find.text('팀 이름'), findsNothing);
    final full = find.byKey(const ValueKey('fullscreen-match-live'));
    expect(tester.getSize(full).width, 1200);
    await tester.tap(find.text('선수1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '골'));
    await tester.pumpAndSettle();
    expect(find.text('1 : 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
