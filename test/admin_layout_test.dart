// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 전체 관리자 목업의 분할 화면과 실제 Form 답변 계약을 Mock으로 검증합니다.
import 'dart:async';

import 'package:bootcamp_project_gongin_admin_app/view/match/manager_schedule_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/view/match/manager_result_panel.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/app.dart';
import 'package:bootcamp_project_gongin_admin_app/model/login_role.dart';
import 'package:bootcamp_project_gongin_admin_app/view/dashboard/dashboard_page.dart';
import 'package:bootcamp_project_gongin_admin_app/view/match/match_page.dart';

import 'dashboard_test.dart' show FakeApi;

import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/management/management_page.dart';
import 'package:bootcamp_project_gongin_admin_app/view/inquiry/inquiry_page.dart';

import 'headquarters_test.dart' show HeadquartersFake;

class LayoutApi extends HeadquartersFake {
  bool failAnswer = false, answered = false;
  Completer<void>? answerGate;
  final answers = <Map<String, String>>[];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    if (path == '/inquiry/answer' && form != null) {
      answers.add(form);
      if (answerGate != null) await answerGate!.future;
      if (failAnswer) throw const OperationsApiException(500, '답변 저장 실패');
      answered = true;
      return {'result': 'OK', 'i_seq': 41};
    }
    final route = Uri.parse(path).path;
    if (route == '/management/members') {
      return {
        'total': 1,
        'results': [
          {
            'c_id_seq': 'member_01',
            'c_name': '회원 하나',
            'match_count': 3,
            'warning_count': 1,
          },
        ],
      };
    }
    if (route == '/management/members/member_01') {
      reads.add(path);
      return {
        'c_id_seq': 'member_01',
        'c_name': '회원 하나',
        'c_phone': '010-0000-0000',
        'c_position': 'FW',
        'match_count': 3,
        'warning_count': 1,
        'sanctions': [],
        'received_reports': [],
        'private_internal_column': '표시하면 안 됨',
      };
    }
    if (route == '/inquiry/list') {
      return {
        'results': [
          {
            'i_seq': 41,
            'title': '예약 문의',
            'post': '예약 날짜 질문',
            'c_name': '회원 하나',
            'i_state': answered ? '1' : '0',
          },
        ],
      };
    }
    if (route == '/inquiry/detail/41') {
      return {
        'i_seq': 41,
        'title': '예약 문의',
        'post': '예약 날짜 질문',
        'c_name': '회원 하나',
        'i_state': answered ? '1' : '0',
        'inquiry_detail': answered ? '날짜 안내 답변' : null,
        'follow_ups': [
          {'i_seq': 42, 'post': '추가 질문', 'i_state': '0'},
        ],
      };
    }
    return super.request(path, json: json, form: form);
  }
}

void main() {
  Widget app(LayoutApi api, Widget child) => ProviderScope(
    overrides: [operationsApiProvider.overrideWithValue(api)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
  void viewport(WidgetTester t, Size size) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets('iPad 로그인은 남색 소개와 공통 로그인 입력을 함께 표시한다', (t) async {
    viewport(t, const Size(1180, 820));
    await t.pumpWidget(const ProviderScope(child: GonginApp()));
    await t.pumpAndSettle();
    expect(find.text('공In중개사\n관리자'), findsOneWidget);
    expect(find.text('담당자 로그인'), findsOneWidget);
    expect(find.text('본사 로그인'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('회원 목록과 상세를 함께 표시하고 내부 키는 노출하지 않는다', (t) async {
    viewport(t, const Size(1180, 820));
    final api = LayoutApi();
    await t.pumpWidget(app(api, const ManagementPage(managers: false)));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '회원 하나'), findsOneWidget);
    expect(find.text('010-0000-0000'), findsOneWidget);
    expect(api.reads, contains('/management/members/member_01'));
    expect(find.text('private_internal_column'), findsNothing);
    expect(find.text('표시하면 안 됨'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('휴대폰 회원 화면은 상세 선택 후 목록으로 복귀한다', (t) async {
    viewport(t, const Size(390, 844));
    await t.pumpWidget(app(LayoutApi(), const ManagementPage(managers: false)));
    await t.pumpAndSettle();
    expect(find.text('010-0000-0000'), findsNothing);
    await tap(t, find.text('회원 하나'));
    expect(find.text('010-0000-0000'), findsOneWidget);
    await tap(t, find.text('목록으로'));
    expect(find.text('010-0000-0000'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('문의 답변 실패 시 입력을 보존하고 Form 계약으로 한 번만 재등록한다', (t) async {
    viewport(t, const Size(1180, 1000));
    final api = LayoutApi()..failAnswer = true;
    await t.pumpWidget(app(api, const InquiryPage(staffId: 'staff1')));
    await t.pumpAndSettle();
    expect(find.text('추가 질문'), findsWidgets);
    await tap(t, find.text('답변 작성').first);
    await t.enterText(find.widgetWithText(TextFormField, '답변 내용'), '날짜 안내 답변');
    await tap(t, find.text('답변 등록'));
    expect(find.text('답변 저장 실패'), findsOneWidget);
    expect(find.text('날짜 안내 답변'), findsOneWidget);
    api.failAnswer = false;
    api.answerGate = Completer<void>();
    await t.tap(find.text('답변 등록'));
    await t.pump();
    expect(find.text('등록 중…'), findsOneWidget);
    expect(api.answers.length, 2);
    expect(api.answers.last, {
      'i_seq': '41',
      'h_id': 'staff1',
      'inquiry_detail': '날짜 안내 답변',
    });
    api.answerGate!.complete();
    await t.pumpAndSettle();
    expect(find.byType(AnswerDialog), findsNothing);
    expect(find.text('본사 답변'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('매니저 메뉴는 내 매치·실력매칭 결과·팀매칭 결과로 구분한다', (t) async {
    viewport(t, const Size(1180, 820));
    final api = LayoutApi();
    await t.pumpWidget(
      app(
        api,
        DashboardPage(
          role: LoginRole.manager,
          userId: 'manager1',
          onLogout: () {},
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('매치 목록'), findsNothing);
    expect(
      t.widget<ManagerSchedulePanel>(find.byType(ManagerSchedulePanel)).history,
      false,
    );
    await tap(t, find.byKey(const ValueKey('education-nav-1')));
    expect(find.byType(ManagerResultsPanel), findsOneWidget);
    expect(
      t.widget<ManagerResultsPanel>(find.byType(ManagerResultsPanel)).kind,
      'pickup',
    );
    expect(find.text('지난 매치'), findsNothing);
    expect(find.text('완료 매치'), findsNothing);
    expect(find.text('전 종목'), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('education-nav-2')));
    expect(
      t.widget<ManagerResultsPanel>(find.byType(ManagerResultsPanel)).kind,
      'team',
    );
    expect(find.text('팀 관리'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('본사와 매니저에서 평가 메뉴를 제거하고 본사 레이아웃은 유지한다', (t) async {
    viewport(t, const Size(1180, 820));
    final api = LayoutApi();
    for (final role in [LoginRole.manager, LoginRole.headquarters]) {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        app(api, DashboardPage(role: role, userId: 'staff', onLogout: () {})),
      );
      await t.pumpAndSettle();
      expect(find.text('내 평가'), findsNothing);
      expect(find.text('매니저 평가'), findsNothing);
      if (role == LoginRole.headquarters) {
        expect(find.text('본사 관리자'), findsOneWidget);
        expect(find.text('매치 관리'), findsOneWidget);
      } else {
        expect(find.text('실력매칭'), findsWidgets);
        expect(find.text('팀매칭'), findsWidgets);
        expect(find.text('회원 관리'), findsNothing);
      }
      expect(t.takeException(), isNull);
    }
    expect(
      api.reads.where((path) => path.startsWith('/management/managers/')),
      isEmpty,
    );
  });
  testWidgets('휴대폰 경기 기록도 점수판과 두 열 버튼이 넘치지 않는다', (t) async {
    viewport(t, const Size(390, 844));
    final api = FakeApi()..status = 'live';
    api.state['assignments'] = {'1': 'A', '2': 'B'};
    await t.pumpWidget(
      ProviderScope(
        overrides: [operationsApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: MatchWorkflowPage(match: {'r_seq': 1, 'g_name': '구장'}),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('0 : 0'), findsOneWidget);
    await tap(t, find.text('선수1'));
    await tap(t, find.widgetWithText(FilledButton, '골'));
    expect(api.state['events'], hasLength(1));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
