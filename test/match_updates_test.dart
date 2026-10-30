// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 팀 경기·문자열 취소 사유·PATCH는 Mock으로만 검증하며 실제 DB에는 쓰지 않습니다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/model/match_updates_model.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/service/match_updates_service.dart';
import 'package:bootcamp_project_gongin_admin_app/view/headquarters/match_updates_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/view/match/match_cancel_dialog.dart';

class UpdatesApi extends OperationsApi {
  final reads = <String>[];
  int patchCount = 0;
  Map<String, dynamic>? body;
  String? patchPath;
  bool failList = false, failCancel = false, cancelled = false;
  Completer<void>? gate;
  Map<String, dynamic> team(int id) => {
    'team_code': id,
    'team_start': '2026-10-18T16:00:00',
    'team_end': '2026-10-18T18:00:00',
    'team_num': 12,
    'g_name': '팀 경기 구장',
    'm_id': 'manager1',
    'm_name': '담당 매니저',
    'status': id == 71 ? 'finished' : 'waiting_result',
    'status_name': id == 71 ? '경기 종료' : '결과 대기',
    'home_team': {
      't_name': '홈팀',
      'captain_name': '홈팀장',
      'captain_phone': '010-0000-0000',
      'grade': null,
      'member_count': 6,
      'wins': 2,
      'draws': 0,
      'losses': 1,
      'win_rate': 67,
    },
    'away_team': {
      't_name': '원정팀',
      'captain_name': '원정팀장',
      'grade': 'A',
      'member_count': 6,
    },
    'result': id == 71
        ? {'home_score': 4, 'away_score': 2, 't_r_r_date': '2026-10-18'}
        : null,
  };
  Map<String, dynamic> cancellation(Object category) => {
    'g_code': 7,
    'g_name': '취소 구장',
    'r_date': '2026-10-28',
    'rs_time': '19:00',
    're_time': '21:00',
    'r_c_category': category,
    'canceled_count': 3,
    'g_num': 12,
    'r_cancel_date': '2026-10-28T10:00:00',
  };
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    reads.add(path);
    final route = Uri.parse(path).path;
    if (failList) throw const OperationsApiException(500, '목록 조회 실패');
    if (route == '/match/team_match') {
      return {
        'results': [team(71), team(72)],
        'total': 2,
      };
    }
    if (route == '/match/team_match/71') return team(71);
    if (route == '/match/team_match/72') return team(72);
    if (route == '/match/cancel' || route == '/match/manage/cancel/manager1') {
      return {
        'results': [cancellation('3'), cancellation('4')],
      };
    }
    if (route == '/match/cancel/7') {
      return {
        ...cancellation('3'),
        'members': [
          {
            'c_name': '예약 회원',
            'c_phone': '010-0000-0000',
            'attendance': false,
            'is_refunded': true,
          },
        ],
      };
    }
    return {'results': []};
  }

  @override
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> json,
  ) async {
    patchCount++;
    patchPath = path;
    body = json;
    if (gate != null) await gate!.future;
    if (failCancel) {
      throw const OperationsApiException(409, '정원이 다 찬 경기는 취소할 수 없습니다.');
    }
    cancelled = true;
    return {'result': 'OK', 'r_c_category': '2', 'refund_count': 2};
  }
}

void main() {
  Widget app(UpdatesApi api, Widget child) => ProviderScope(
    overrides: [operationsApiProvider.overrideWithValue(api)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
  void wide(WidgetTester t) {
    t.view.physicalSize = const Size(1180, 900);
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

  test('팀 경기의 미등록 점수를 0으로 만들지 않고 종료 상태도 서버 값을 따른다', () {
    final api = UpdatesApi();
    final noResult = TeamMatchRecord.fromJson(api.team(72));
    expect(noResult.score, '점수 미기록');
    expect(noResult.status, 'waiting_result');
    expect(TeamMatchRecord.fromJson(api.team(71)).score, '4 : 2');
    expect(
      CancelledMatch.fromJson(api.cancellation('3')).reasonName,
      '노쇼 및 환불',
    );
    expect(CancelledMatch.fromJson(api.cancellation(1)).reasonName, '정원 미달');
  });
  test('취소 목록에서 회원 직접 취소 4를 제외하고 매니저 전용 URL과 정수 필터를 사용한다', () async {
    final api = UpdatesApi();
    final rows = await MatchUpdatesService(api)
        .cancellations(managerId: 'manager1', reason: 3);
    expect(rows, hasLength(1));
    expect(Uri.parse(api.reads.single).path, '/match/manage/cancel/manager1');
    expect(Uri.parse(api.reads.single).queryParameters['r_c_category'], '3');
  });
  test('공통 PATCH는 실제 메서드·JSON·토큰을 전달하고 구조화된 오류를 보존한다', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'detail': '취소 조건 충돌'}),
        409,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final api = OperationsApi(client: client, accessToken: 'mock-token');
    await expectLater(
      api.patch('/match/manage/cancel/manager1', {
        'g_code': '7',
        'r_c_category': 2,
      }),
      throwsA(
        isA<OperationsApiException>().having(
          (e) => e.statusCode,
          'status',
          409,
        ),
      ),
    );
    expect(captured.method, 'PATCH');
    expect(jsonDecode(captured.body)['r_c_category'], 2);
    expect(captured.headers['Authorization'], 'Bearer mock-token');
  });
  testWidgets('본사 팀 매칭의 실제 코드로 상세와 두 팀 결과를 표시한다', (t) async {
    wide(t);
    final api = UpdatesApi();
    await t.pumpWidget(app(api, const TeamMatchPanel(staffId: 'hq')));
    await t.pumpAndSettle();
    await tap(t, find.byKey(const ValueKey('team-match:71')));
    expect(api.reads, contains('/match/team_match/71'));
    expect(find.text('4 : 2'), findsOneWidget);
    expect(find.text('홈팀장'), findsOneWidget);
    expect(find.text('경기 종료'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('팀 매칭 검색과 상태 필터는 서버 쿼리로 전달한다', (t) async {
    wide(t);
    final api = UpdatesApi();
    await t.pumpWidget(app(api, const TeamMatchPanel(staffId: 'hq')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '홈팀');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    await tap(t, find.text('전체 상태'));
    await tap(t, find.text('결과 대기').last);
    final query = Uri.parse(api.reads.last).queryParameters;
    expect(query['keyword'], '홈팀');
    expect(query['status'], 'waiting_result');
    expect(t.takeException(), isNull);
  });
  testWidgets('목록 실패는 빈 결과로 숨기지 않고 재시도한다', (t) async {
    wide(t);
    final api = UpdatesApi()..failList = true;
    await t.pumpWidget(app(api, const TeamMatchPanel(staffId: 'hq')));
    await t.pumpAndSettle();
    expect(find.text('목록 조회 실패'), findsOneWidget);
    api.failList = false;
    await tap(t, find.text('다시 시도'));
    expect(find.byKey(const ValueKey('team-match:71')), findsOneWidget);
  });
  testWidgets('본사 취소 상세는 경기일·시작 시간으로 회원 정보를 조회한다', (t) async {
    wide(t);
    final api = UpdatesApi();
    await t.pumpWidget(app(api, const CancelledMatchPanel(staffId: 'hq')));
    await t.pumpAndSettle();
    expect(find.textContaining('노쇼 및 환불'), findsOneWidget);
    await tap(t, find.text('취소 구장'));
    expect(find.text('예약 회원'), findsOneWidget);
    final uri = Uri.parse(api.reads.last);
    expect(uri.path, '/match/cancel/7');
    expect(uri.queryParameters, {'r_date': '2026-10-28', 'rs_time': '19:00'});
  });
  testWidgets('매니저 취소 내역은 담당자 URL만 사용하고 본사 전체 상세를 요청하지 않는다', (t) async {
    wide(t);
    final api = UpdatesApi();
    await t.pumpWidget(
      app(
        api,
        const CancelledMatchPanel(staffId: 'manager1', managerId: 'manager1'),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, find.text('취소 구장'));
    expect(
      api.reads.every(
        (p) => Uri.parse(p).path == '/match/manage/cancel/manager1',
      ),
      isTrue,
    );
    expect(find.text('노쇼 및 환불'), findsOneWidget);
    expect(find.text('예약 회원'), findsNothing);
  });
  testWidgets('취소 충돌 시 사유를 유지하고 중복 PATCH를 차단한다', (t) async {
    wide(t);
    final api = UpdatesApi()..failCancel = true;
    const target = (
      managerId: 'manager1',
      groundCode: '7',
      date: '2026-10-28',
      start: '19:00',
    );
    await t.pumpWidget(
      app(
        api,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  const MatchCancelDialog(target: target, groundName: '구장'),
            ),
            child: const Text('취소 창 열기'),
          ),
        ),
      ),
    );
    await tap(t, find.text('취소 창 열기'));
    await tap(t, find.text('취소 사유'));
    await tap(t, find.text('우천·기상악화').last);
    await tap(t, find.text('예약 취소 확정'));
    expect(find.text('정원이 다 찬 경기는 취소할 수 없습니다.'), findsOneWidget);
    expect(find.text('우천·기상악화'), findsOneWidget);
    api.failCancel = false;
    api.gate = Completer<void>();
    await t.tap(find.text('예약 취소 확정'));
    await t.pump();
    expect(find.text('처리 중…'), findsOneWidget);
    expect(api.patchCount, 2);
    expect(api.body, {
      'g_code': '7',
      'r_date': '2026-10-28',
      'rs_time': '19:00',
      'r_c_category': 2,
    });
    expect(api.patchPath, '/match/manage/cancel/manager1');
    api.gate!.complete();
    await t.pumpAndSettle();
    expect(find.byType(MatchCancelDialog), findsNothing);
    expect(t.takeException(), isNull);
  });
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
