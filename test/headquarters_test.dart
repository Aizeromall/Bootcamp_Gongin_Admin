// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 실제 서버·DB 없이 본사 조회와 쓰기 요청 계약을 검증합니다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/model/headquarters_model.dart';
import 'package:bootcamp_project_gongin_admin_app/model/login_role.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/dashboard/dashboard_page.dart';
import 'package:bootcamp_project_gongin_admin_app/view/headquarters/announcement_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/view/headquarters/appeal_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/view/headquarters/team_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/view/headquarters/approval_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/view/headquarters/manager_work_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/service/headquarters_service.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/headquarters_notifier.dart';

class HeadquartersFake extends OperationsApi {
  int uploads = 0;
  @override
  Future<Map<String, dynamic>> uploadPhoto(
    String staffId,
    String name,
    List<int> bytes,
  ) async {
    uploads++;
    return {'s_image': 'saved_photo.jpg'};
  }

  final reads = <String>[];
  final writes = <(String, AdminRow)>[];
  bool failWrite = false, failTeams = false, reviewed = false;
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    final uri = Uri.parse(path);
    final route = uri.path;
    if (json != null) {
      writes.add((route, json));
      if (gate != null) await gate!.future;
      if (failWrite) throw const OperationsApiException(422, '입력을 다시 확인해 주세요.');
      if (route.startsWith('/appeal/review/')) reviewed = true;
      return {'result': 'OK', 'a_seq': 4, 'm_code': 99};
    }
    reads.add(path);
    if (route == '/announce/admin') {
      return {
        'total': 1,
        'results': [
          {
            'a_seq': 4,
            'a_classify': '운영',
            'a_title': '실제 공지 제목',
            'a_detail': '실제 공지 본문',
            'h_name': '본사 직원',
            'a_date': '2026-10-27T09:00:00',
            'a_target': ['본사'],
          },
        ],
      };
    }
    if (route == '/inquiry/list') {
      return {
        'results': [
          {
            'i_seq': 1,
            'post': '실제 미답변 문의',
            'i_state': '0',
            'follow_ups': [
              {'i_seq': 2, 'i_state': null, 'post': '추가 문의'},
            ],
          },
        ],
      };
    }
    if (route == '/report/list') return {'pending_count': 3, 'results': []};
    if (route == '/education/courses') {
      return {'required_pending': 2, 'total': 2, 'results': []};
    }
    if (route == '/appeal/list') {
      return {
        'pending_count': reviewed ? 1 : 1,
        'total': 1,
        'results': [
          {
            'a_seq': 71,
            'title': '홍길동 · 사실과 다름',
            'state_text': reviewed ? '재심의 중' : '접수',
            'sport_name': '축구',
          },
        ],
      };
    }
    if (route == '/appeal/detail/71') {
      return {
        'a_seq': 71,
        'title': '홍길동 · 사실과 다름',
        'state_text': reviewed ? '재심의 중' : '접수',
        'a_reason': '증빙을 확인해 주세요.',
        'a_evidence': ['https://example.com/evidence'],
        'can_start_review': !reviewed,
        'sanction': {'label': '경고 1회', 'cs_detail': '제재 사유'},
      };
    }
    if (route == '/appeal/sanction') {
      return {
        'total': 1,
        'results': [
          {
            'cs_seq': 5,
            'member_name': '홍길동',
            'label': '경고 1회',
            'tag': '유효',
            'cs_detail': '제재 사유',
          },
        ],
      };
    }
    if (route == '/management/teams') {
      if (failTeams) throw const OperationsApiException(500, '팀 조회 실패');
      return {
        'total': 1,
        'results': [
          {
            't_id': 17,
            't_name': '실제 팀',
            'category': '축구',
            'captain_name': '김팀장',
            'member_count': 4,
            'grade': null,
          },
        ],
      };
    }
    if (route == '/management/teams/17') {
      return {
        't_id': 17,
        't_name': '실제 팀',
        'category': '축구',
        'wins': 0,
        'draws': 0,
        'losses': 0,
        'grade': null,
        'win_rate': null,
        'members': [
          {'c_name': '김팀장', 'c_id_seq': 'captain_01', 'c_position': 'FW'},
        ],
        'recent_matches': [],
      };
    }
    if (route == '/approval/grounds/managers') {
      return {
        'results': [
          {'m_id': 'manager1', 'm_name': '경기 담당자', 'm_workplace': '서울'},
        ],
      };
    }
    if (route == '/match/list/manager1') {
      return {
        'reservations': [
          {
            'r_seq': 71,
            'g_name': '실제 구장',
            'r_date': '2026-11-01',
            'rs_time': '19:00:00',
            're_time': '21:00:00',
            'c_name': '예약자',
          },
        ],
      };
    }
    if (route == '/management/managers/manager1') {
      return {
        'evaluates': [
          {'e_date': '2026-10-20', 'e_detail': '본사 평가 원문'},
        ],
      };
    }
    if (route == '/approval/templates') {
      return {
        'results': [
          {'m_code': 10, 'm_content': '휴가 품의 양식'},
          {'m_code': 11, 'm_content': '재계약 품의 양식'},
          {'m_code': 12, 'm_content': '해지 품의 양식'},
          {'m_code': 13, 'm_content': '신규 계약 품의 양식'},
        ],
      };
    }
    if (route == '/approval/approvers') {
      return {
        'results': [
          for (final p in ['사원', '팀장', '임원'])
            {'h_id': 'sign_$p', 'h_name': '결재자$p', 'h_position': p},
        ],
      };
    }
    if (route == '/approval/vacation/deputies') {
      return {
        'results': [
          {'h_id': 'deputy1', 'h_name': '동료 직원'},
        ],
      };
    }
    if (route == '/approval/requests') {
      return {
        'results': [
          {
            'm_code': 88,
            'a_reason': '휴가 신청',
            'a_state': '심사중',
            'a_step': 0,
            'h_name': '신청자',
            'm_content': '휴가 품의 양식',
          },
        ],
      };
    }
    if (route == '/approval/requests/88') {
      return {
        'm_code': 88,
        'm_content': {
          '유형': '휴가',
          '작성자': {'h_name': '신청자', 'h_id': 'hq'},
          '내용': {
            'h_start': '2026-11-01',
            'h_end': '2026-11-02',
            'h_deputy': 'deputy1',
          },
          '결재선': [],
        },
        'approval': [
          {'a_state': '심사중', 'a_step': 0, 'h_name': '신청자', 'a_reason': '휴가 신청'},
        ],
      };
    }
    return {'results': []};
  }
}

void main() {
  Widget host(HeadquartersFake api, Widget child) => ProviderScope(
    overrides: [operationsApiProvider.overrideWithValue(api)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        300,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
    }
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets('본사는 실제 집계·공지·처리할 일 대시보드에서 시작한다', (t) async {
    wide(t);
    final api = HeadquartersFake();
    await t.pumpWidget(
      host(
        api,
        DashboardPage(
          role: LoginRole.headquarters,
          userId: 'hq',
          onLogout: () {},
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('대시보드'), findsNWidgets(2));
    expect(find.text('실제 공지 제목'), findsOneWidget);
    expect(find.text('실제 미답변 문의'), findsOneWidget);
    expect(find.text('오늘 매치'), findsNothing);
    expect(find.text('매출 현황'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('팀 검색·종목 필터·실제 ID 상세·미기록 등급', (t) async {
    wide(t);
    final api = HeadquartersFake();
    await t.pumpWidget(host(api, const TeamPanel(staffId: 'hq')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '실제');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(
      api.reads.any((p) => Uri.parse(p).queryParameters['keyword'] == '실제'),
      isTrue,
    );
    await tap(t, find.text('실제 팀'));
    expect(api.reads, contains('/management/teams/17'));
    expect(find.text('기록 없음'), findsOneWidget);
    expect(find.text('김팀장'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('경기 기록이 없습니다.'),
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
    expect(find.text('경기 기록이 없습니다.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('팀 오류는 빈 목록으로 숨기지 않고 재시도한다', (t) async {
    final api = HeadquartersFake()..failTeams = true;
    await t.pumpWidget(host(api, const TeamPanel(staffId: 'hq')));
    await t.pumpAndSettle();
    expect(find.text('팀 조회 실패'), findsOneWidget);
    api.failTeams = false;
    await tap(t, find.text('다시 시도'));
    expect(find.text('실제 팀'), findsOneWidget);
  });
  testWidgets('공지 실패시 입력 보존·로그인 담당자·중복 제출 방지', (t) async {
    wide(t);
    final api = HeadquartersFake()..failWrite = true;
    await t.pumpWidget(host(api, const AnnouncementPanel(staffId: 'hq')));
    await t.pumpAndSettle();
    await tap(t, find.text('+ 공지 작성'));
    await t.enterText(find.widgetWithText(TextFormField, '제목'), '새 공지');
    await t.enterText(find.widgetWithText(TextFormField, '내용'), '새 공지 본문');
    await tap(t, find.text('공지 등록'));
    expect(find.text('입력을 다시 확인해 주세요.'), findsOneWidget);
    expect(find.text('새 공지 본문'), findsOneWidget);
    api.failWrite = false;
    api.gate = Completer<void>();
    await t.tap(find.text('공지 등록'));
    await t.pump();
    expect(find.text('등록 중…'), findsOneWidget);
    expect(api.writes.length, 2);
    expect(api.writes.last.$2['h_id'], 'hq');
    expect(api.writes.last.$2['a_target'], ['본사']);
    api.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('공지를 등록했습니다.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('이의신청 재심의는 선택 ID와 본사 ID로 요청하고 상태를 갱신한다', (t) async {
    wide(t);
    final api = HeadquartersFake();
    await t.pumpWidget(host(api, const AppealPanel(staffId: 'hq')));
    await t.pumpAndSettle();
    await tap(t, find.text('홍길동 · 사실과 다름'));
    expect(find.text('증빙을 확인해 주세요.'), findsOneWidget);
    await tap(t, find.text('재심의 시작'));
    await tap(t, find.text('확인'));
    expect(api.writes.single.$1, '/appeal/review/71');
    expect(api.writes.single.$2, {'h_id': 'hq'});
    expect(find.text('재심의 중'), findsWidgets);
    expect(find.text('재심의 시작'), findsNothing);
  });
  testWidgets('제재 탭은 서버 태그를 사용하고 상세를 표시한다', (t) async {
    wide(t);
    final api = HeadquartersFake();
    await t.pumpWidget(host(api, const AppealPanel(staffId: 'hq')));
    await t.pumpAndSettle();
    await tap(t, find.text('제재 목록'));
    await tap(t, find.text('홍길동 · 경고 1회'));
    expect(find.text('제재 사유'), findsOneWidget);
    expect(
      api.reads.any((p) => Uri.parse(p).path == '/appeal/sanction'),
      isTrue,
    );
  });
  testWidgets('품의 내역의 승인 요청은 실제 문서 번호와 담당자를 사용한다', (t) async {
    wide(t);
    final api = HeadquartersFake();
    await t.pumpWidget(host(api, const ApprovalPanel(staffId: 'hq')));
    await t.pumpAndSettle();
    await tap(t, find.text('휴가 · 휴가 신청'));
    await tap(t, find.text('승인'));
    await tap(t, find.text('확인'));
    expect(api.writes.single.$1, '/approval/requests/88/sign');
    expect(api.writes.single.$2, {
      'h_id': 'hq',
      'approve': true,
      'comment': '',
    });
    expect(t.takeException(), isNull);
  });
  testWidgets('좁은 화면에서도 대시보드와 메뉴가 넘치지 않는다', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      host(
        HeadquartersFake(),
        DashboardPage(
          role: LoginRole.headquarters,
          userId: 'hq',
          onLogout: () {},
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('답변 대기 문의'), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('mobile-admin-menu')));
    await tap(t, find.text('팀 관리').last);
    expect(find.text('실제 팀'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('휴가 품의는 실제 양식·결재선·대리인을 선택해 상신한다', (t) async {
    wide(t);
    final api = HeadquartersFake();
    await t.pumpWidget(
      host(api, const ApprovalPanel(staffId: 'hq', write: true)),
    );
    await t.pumpAndSettle();
    await tap(t, find.text('품의 양식'));
    await tap(t, find.text('휴가 · 양식 10').last);
    await t.enterText(find.widgetWithText(TextFormField, '품의 사유'), '휴가 사유');
    for (final p in ['사원', '팀장', '임원']) {
      await tap(t, find.text('결재 $p'));
      await tap(t, find.text('결재자$p · sign_$p').last);
    }
    for (final label in ['시작일', '종료일']) {
      await tap(t, find.widgetWithText(TextFormField, label));
      await tap(t, find.text('선택'));
    }
    await tap(t, find.text('대리인'));
    await tap(t, find.text('동료 직원 · deputy1').last);
    await tap(t, find.text('품의 상신'));
    await tap(t, find.text('확인'));
    expect(api.writes.single.$1, '/approval/requests');
    final body = api.writes.single.$2;
    expect(body['h_id'], 'hq');
    expect(body['m_code'], 10);
    expect(body['approver_ids'], ['sign_사원', 'sign_팀장', 'sign_임원']);
    expect(body['data']['h_deputy'], 'deputy1');
    expect(body['data']['h_start'], body['data']['h_end']);
    expect(find.text('품의서를 상신했습니다. 품의 내역에서 확인해 주세요.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('매치는 담당자 ID를 선택해 기존 예약 조회 API로 연결한다', (t) async {
    wide(t);
    final api = HeadquartersFake();
    await t.pumpWidget(host(api, const ManagerWorkPanel(staffId: 'hq')));
    await t.pumpAndSettle();
    await tap(t, find.text('담당 매니저 선택'));
    await tap(t, find.text('경기 담당자 · 서울').last);
    expect(find.text('실제 구장'), findsOneWidget);
    expect(find.text('예약자'), findsWidgets);
    expect(api.reads, contains('/match/list/manager1'));
    expect(t.takeException(), isNull);
  });
  test('사진 업로드는 기존 파일 API 응답을 사용한다', () async {
    final api = HeadquartersFake();
    final service = HeadquartersService(api);
    expect(
      await service.upload('hq', 'photo.jpg', [1, 2, 3]),
      'saved_photo.jpg',
    );
    expect(api.uploads, 1);
  });
  test('문서 유형과 일반 문자열·null 변환을 보존한다', () {
    expect(approvalKind('휴가 양식'), '휴가');
    expect(approvalKind('{"유형":"재계약"}'), '재계약');
    expect(adminDocument('과거 원문'), isEmpty);
    expect(adminInt('17'), 17);
    expect(adminText(null), '—');
  });
  test('담당자별 캐시와 저장 실패/중복 요청을 분리한다', () async {
    final api = HeadquartersFake()..gate = Completer<void>();
    final container = ProviderContainer(
      overrides: [operationsApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      adminMutationProvider('hq'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    await container.read(adminMutationProvider('hq').future);
    final notifier = container.read(adminMutationProvider('hq').notifier);
    final first = notifier.save('/announce/write', {'h_id': 'hq'});
    expect(await notifier.save('/announce/write', {'h_id': 'hq'}), isFalse);
    expect(api.writes.length, 1);
    api.gate!.complete();
    expect(await first, isTrue);
  });
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
