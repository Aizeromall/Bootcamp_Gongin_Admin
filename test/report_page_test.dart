// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 실제 DB를 호출하지 않고 신고 목록·필터·심의와 역할별 진입을 검증합니다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/model/login_role.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/dashboard/dashboard_page.dart';
import 'package:bootcamp_project_gongin_admin_app/view/report/report_page.dart';

class ReportFakeApi extends OperationsApi {
  bool failList = false, failReview = false;
  int writes = 0;
  Completer<void>? reviewGate;
  final requests = <String>[];
  Map<String, dynamic>? lastBody;
  final reports = <Map<String, dynamic>>[
    {
      'r_seq': 1,
      'r_date': '2026-10-27T10:30:00',
      'state': 0,
      'state_text': '접수',
      'r_option_name': '폭언·욕설',
      'c_id_seq': 'user_01',
      'reporter_name': '신고한 회원',
      'r_person': 'target_01',
      'target_name': '신고 대상 회원 이름이 아주 길어지는 경우도 확인',
      'sport': 'SOCCER',
      'sport_name': '축구',
      'r_reason': '경기 도중 욕설이 있었습니다.\n확인을 요청합니다.',
      'g_name': '테스트 풋살장',
      'match_date': '2026-10-26',
      'match_time': '19:00',
      'm_name': '담당 매니저',
      'c_r_r_code': '1_20261026_190000',
      'h_name': null,
      'r_evidence': ['evidence-01.jpg'],
      'can_start_review': true,
      'target_history': {
        'warning_count': 2,
        'received_report_count': 3,
        'account_state': '정상',
      },
    },
  ];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    requests.add(path);
    final uri = Uri.parse(path);
    if (uri.path == '/report/list') {
      if (failList) {
        throw const OperationsApiException(500, '신고 내역을 불러오지 못했습니다.');
      }
      final state = uri.queryParameters['state'],
          sport = uri.queryParameters['sport'];
      final bySport = reports
          .where((r) => sport == null || r['sport'] == sport)
          .toList();
      final byState = reports
          .where((r) => state == null || r['state_text'] == state)
          .toList();
      return jsonDecode(
        jsonEncode({
          'pending_count': reports
              .where((r) => r['state_text'] != '처리완료')
              .length,
          'status_counts': {
            '전체': bySport.length,
            for (final s in ['접수', '심의중', '처리완료', '기각'])
              s: bySport.where((r) => r['state_text'] == s).length,
          },
          'sport_counts': [
            {
              'sport': 'SOCCER',
              'sport_name': '축구',
              'count': byState.where((r) => r['sport'] == 'SOCCER').length,
            },
            {'sport': 'BASEBALL', 'sport_name': '야구', 'count': 0},
          ],
          'total': reports
              .where(
                (r) =>
                    (state == null || r['state_text'] == state) &&
                    (sport == null || r['sport'] == sport),
              )
              .length,
          'results': reports
              .where(
                (r) =>
                    (state == null || r['state_text'] == state) &&
                    (sport == null || r['sport'] == sport),
              )
              .toList(),
        }),
      ) as Map<String, dynamic>;
    }
    if (uri.path.startsWith('/report/detail/')) {
      return jsonDecode(jsonEncode(reports.first)) as Map<String, dynamic>;
    }
    if (uri.path.startsWith('/report/review/')) {
      writes++;
      lastBody = json;
      if (reviewGate != null) await reviewGate!.future;
      if (failReview) {
        throw const OperationsApiException(409, '이미 심의가 시작된 신고입니다.');
      }
      reports.first.addAll({
        'state': 1,
        'state_text': '심의중',
        'can_start_review': false,
        'h_name': '본사 직원',
      });
      return {'result': 'OK', 'r_seq': 1, 'state': 1, 'state_text': '심의중'};
    }
    return {'results': <Map<String, dynamic>>[]};
  }
}

void main() {
  Widget app(ReportFakeApi api, {LoginRole? role, String staffId = 'hq01'}) =>
      ProviderScope(
        retry: (_, _) => null,
        overrides: [operationsApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: role == null
              ? Scaffold(body: ReportPage(staffId: staffId))
              : DashboardPage(role: role, userId: staffId, onLogout: () {}),
        ),
      );
  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> reachReview(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '심의 시작'),
      350,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('report-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('넓은 화면에서 목록과 상세·서버 집계를 함께 표시', (tester) async {
    size(tester, const Size(1500, 1000));
    final api = ReportFakeApi();
    await tester.pumpWidget(app(api));
    await tester.pumpAndSettle();
    expect(find.text('처리 대기 1건'), findsOneWidget);
    expect(find.text('접수 1'), findsOneWidget);
    expect(find.text('신고 내용'), findsOneWidget);
    expect(find.text('경기 도중 욕설이 있었습니다.\n확인을 요청합니다.'), findsOneWidget);
    expect(api.requests.any((p) => p.startsWith('/report/detail/1')), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('필터는 서버에 전달하며 빈 결과는 별도 표시', (tester) async {
    size(tester, const Size(1500, 1000));
    final api = ReportFakeApi();
    await tester.pumpWidget(app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '축구 1'));
    await tester.pumpAndSettle();
    expect(
      api.requests
          .map(Uri.parse)
          .any((u) => u.queryParameters['sport'] == 'SOCCER'),
      isTrue,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '처리완료 0'));
    await tester.pumpAndSettle();
    expect(find.text('해당하는 신고가 없습니다.'), findsOneWidget);
    expect(
      api.requests
          .map(Uri.parse)
          .any(
            (u) =>
                u.queryParameters['state'] == '처리완료' &&
                u.queryParameters['sport'] == 'SOCCER',
          ),
      isTrue,
    );
  });
  testWidgets('오류를 빈 목록으로 숨기지 않고 재시도', (tester) async {
    final api = ReportFakeApi()..failList = true;
    await tester.pumpWidget(app(api));
    await tester.pumpAndSettle();
    expect(find.text('신고 내역을 불러오지 못했습니다.'), findsOneWidget);
    expect(find.text('해당하는 신고가 없습니다.'), findsNothing);
    api.failList = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('폭언·욕설'), findsOneWidget);
  });
  testWidgets('심의 시작에 본사 ID를 보내고 중복 제출을 막고 상태 갱신', (tester) async {
    size(tester, const Size(1500, 1000));
    final gate = Completer<void>();
    final api = ReportFakeApi()..reviewGate = gate;
    await tester.pumpWidget(app(api));
    await tester.pumpAndSettle();
    await reachReview(tester);
    await tester.tap(find.widgetWithText(FilledButton, '심의 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '심의 시작').last);
    await tester.pump();
    expect(api.writes, 1);
    expect(api.lastBody, {'h_id': 'hq01'});
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '처리 중…'),
    );
    expect(button.onPressed, isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(api.writes, 1);
    expect(api.reports.first['state_text'], '심의중');
    expect(find.text('심의중 1'), findsOneWidget);
    expect(find.text('심의를 시작했습니다.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '심의 시작'), findsNothing);
  });
  testWidgets('심의 충돌은 성공으로 표시하지 않고 서버 상태 재조회', (tester) async {
    size(tester, const Size(1500, 1000));
    final api = ReportFakeApi()..failReview = true;
    await tester.pumpWidget(app(api));
    await tester.pumpAndSettle();
    await reachReview(tester);
    final before = api.requests
        .where((p) => p.startsWith('/report/detail'))
        .length;
    await tester.tap(find.widgetWithText(FilledButton, '심의 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '심의 시작').last);
    await tester.pumpAndSettle();
    expect(find.text('이미 심의가 시작된 신고입니다.'), findsOneWidget);
    expect(find.text('심의를 시작했습니다.'), findsNothing);
    expect(
      api.requests.where((p) => p.startsWith('/report/detail')).length,
      greaterThan(before),
    );
  });
  testWidgets('작은 화면에서 목록 선택 후 상세와 목록 복귀', (tester) async {
    size(tester, const Size(390, 844));
    await tester.pumpWidget(app(ReportFakeApi()));
    await tester.pumpAndSettle();
    expect(find.text('신고 내용'), findsNothing);
    await tester.tap(find.text('폭언·욕설'));
    await tester.pumpAndSettle();
    expect(find.text('신고 내용'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('목록으로'));
    await tester.pumpAndSettle();
    expect(find.text('신고 내용'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('신고 메뉴는 본사에만 노출', (tester) async {
    await tester.pumpWidget(app(ReportFakeApi(), role: LoginRole.headquarters));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('education-nav-4')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('education-nav-4')));
    await tester.pumpAndSettle();
    expect(find.text('신고 내역'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(ReportFakeApi(), role: LoginRole.manager));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.flag_outlined), findsNothing);
  });
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
