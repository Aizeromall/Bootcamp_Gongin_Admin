// 작업자 : 양태건
// 수정일 : 2026-10-26
// [수정 시작] 경기 진행과 지난 매치 이동을 검증합니다.
import 'dart:convert';

import 'package:bootcamp_project_gongin_admin_app/vm/login_notifier.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/model/login_role.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/dashboard/dashboard_page.dart';
import 'package:bootcamp_project_gongin_admin_app/view/match/match_page.dart';

class DashboardLogin extends LoginNotifier {
  @override
  AsyncValue<StaffSession?> build() =>
      const AsyncData(StaffSession(userId: 'test', role: LoginRole.manager));
}

String get testMatchDate => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 9))
    .toIso8601String()
    .substring(0, 10);

class FakeApi extends OperationsApi {
  String status = 'attendance';
  int version = 0;
  final state = <String, dynamic>{
    'players': [
      for (var i = 1; i <= 2; i++)
        {
          'r_seq': i,
          'c_id_seq': 'test${i}_01',
          'c_name': '선수$i',
          'c_position': '수비',
          'c_prefer_stock': '1',
        },
    ],
    'attendance': <String, dynamic>{},
    'assignments': <String, dynamic>{},
    'team_names': ['블루팀', '화이트팀'],
    'team_colors': ['blue', 'grey'],
    'events': <Map<String, dynamic>>[],
    'injuries': <Map<String, dynamic>>[],
    'running_since': null,
  };
  Map<String, dynamic> get detail {
    final stats = <String, dynamic>{
      for (var i = 1; i <= 2; i++)
        '$i': {'goal': 0, 'assist': 0, 'shot': 0, 'yellow': 0, 'red': 0},
    };
    final scores = {'A': 0, 'B': 0};
    for (final e in state['events'] as List) {
      stats['${e['r_seq']}'][e['kind']]++;
      if (e['kind'] == 'goal') scores[e['team']] = scores[e['team']]! + 1;
    }
    return jsonDecode(
      jsonEncode({
        'state': state,
        'status': status,
        'version': version,
        'elapsed_seconds': 0,
        'stats': stats,
        'scores': scores,
      }),
    ) as Map<String, dynamic>;
  }

  Map<String, dynamic> get resultFixture {
    final oldRows = (detail['state']['legacy_records'] as List? ?? []);
    final members = oldRows.isNotEmpty
        ? [
            for (final row in oldRows)
              {
                'name': row['c_name'],
                'current_tier': null,
                'current_rating': null,
                'rating_change': null,
                'record_text': row['c_r_r_statcode'],
              },
          ]
        : [
            for (final player in state['players'] as List)
              {
                'name': player['c_name'],
                'stats': detail['stats']['${player['r_seq']}'],
                'rating_change': null,
              },
          ];
    return {
      'code': '1_20261029_190000',
      'kind': 'pickup',
      'ground': '테스트 구장',
      'date': testMatchDate,
      'time': '19:00',
      'home': '블루팀',
      'away': '화이트팀',
      'home_score': oldRows.isEmpty ? detail['scores']['A'] : null,
      'away_score': oldRows.isEmpty ? detail['scores']['B'] : null,
      'raw_score': oldRows.isEmpty ? null : oldRows.first['c_r_r_score'],
      'stat_columns': [
        {'key': 'goal', 'label': '골'},
      ],
      'sides': [
        {'name': '블루팀', 'members': members},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    if (path == '/match/manager/upcoming') {
      final rows = await request('/match/operations');
      return {
        'operations': status == 'completed' ? [] : rows['results'],
        'teams': [],
      };
    }
    if (path == '/match/rating/stat_keys') {
      return {
        'tiers': [
          {'min_rating': 1500, 'name': '비기너 1'},
        ],
      };
    }
    if (path.startsWith('/match/manager/results/')) return resultFixture;
    if (path.startsWith('/match/manager/results')) {
      return {
        'results': status == 'completed' ? [resultFixture] : [],
      };
    }
    if (path.startsWith('/match/schedule/test')) {
      return {
        'm_id': 'test',
        'r_date': Uri.parse(path).queryParameters['r_date'],
        'grounds': [],
      };
    }
    if (path == '/match/operations') {
      return {
        'results': [
          {
            'r_seq': 1,
            'g_code': 1,
            'e_code': 'SOCCER',
            'g_name': '테스트 구장',
            'r_date': testMatchDate,
            'rs_time': '19:00',
            'status': status,
            'count': 2,
            'scores': detail['scores'],
          },
        ],
      };
    }
    if (path.startsWith('/match/operations/')) {
      if (json != null) {
        version++;
        switch (json['action']) {
          case 'attendance':
            state['attendance']['${json['r_seq']}'] = json['attendance'];
          case 'teams':
            status = 'teams';
            if (json.containsKey('assignments')) {
              state['assignments'] = json['assignments'];
            }
            if (json.containsKey('team_names')) {
              state['team_names'] = json['team_names'];
            }
            if (json.containsKey('team_colors')) {
              state['team_colors'] = json['team_colors'];
            }
          case 'start':
            status = 'live';
            state['running_since'] = 1;
          case 'event':
            (state['events'] as List).add({
              'r_seq': json['r_seq'],
              'name': '선수${json['r_seq']}',
              'kind': json['kind'],
              'team': state['assignments']['${json['r_seq']}'],
              'elapsed_seconds': 0,
            });
          case 'undo':
            (state['events'] as List).removeLast();
          case 'injury':
            (state['injuries'] as List).add({
              ...json,
              'name': '선수${json['r_seq']}',
              'elapsed_seconds': 0,
            });
          case 'pause':
            state['running_since'] = null;
          case 'resume':
            state['running_since'] = 1;
          case 'end':
            status = 'review';
            state['running_since'] = null;
          case 'edit':
            status = 'live';
          case 'publish':
            status = 'completed';
        }
      }
      return detail;
    }
    return {'results': <Map<String, dynamic>>[]};
  }
}

// 작업자 : 양태건
// 수정일 : 2026-10-26
// [추가 시작] 이전 방식의 원본 결과 상세를 검증합니다.
class LegacyApi extends FakeApi {
  LegacyApi() {
    status = 'completed';
  }
  @override
  Map<String, dynamic> get detail {
    final data = super.detail;
    data['legacy'] = true;
    data['scores'] = null;
    data['state']['legacy_records'] = [
      {
        'c_id_seq': 'old_01',
        'c_name': '기존 회원',
        'c_r_r_team': '예전팀',
        'c_r_r_score': '5',
        'c_r_r_statcode': '100',
        'e_code': 'SOCCER',
        'c_r_r_attendance': 1,
        'c_r_r_date': '2026-10-23',
      },
    ];
    return data;
  }
}
// [추가 끝]

void main() {
  Widget app(LoginRole role, FakeApi api) => ProviderScope(
    overrides: [
      operationsApiProvider.overrideWithValue(api),
      loginProvider.overrideWith(DashboardLogin.new),
    ],
    child: MaterialApp(
      home: DashboardPage(role: role, userId: 'test', onLogout: () {}),
    ),
  );
  testWidgets('본사 메뉴에서 문의 관리로 이동', (tester) async {
    await tester.pumpWidget(app(LoginRole.headquarters, FakeApi()));
    await tester.pumpAndSettle();
    // 수정 일 : 2026-10-27 / 작업자 : 양태건
    // 공통 사이드바의 실제 문의 메뉴를 선택해 기존 답변 동작을 검증합니다.
    await tester.tap(find.byKey(const ValueKey('education-nav-2')));
    await tester.pumpAndSettle();
    expect(find.text('답변 대기'), findsOneWidget);
    expect(find.text('문의가 없습니다.'), findsOneWidget);
  });
  testWidgets('출석부터 팀 배정·골·취소·부상·결과 등록 후 지난 매치까지', (tester) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi();
    await tester.pumpWidget(app(LoginRole.manager, api));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '테스트 구장'));
    await tester.pumpAndSettle();
    final attendanceScroll = find
        .descendant(
          of: find.byType(MatchWorkflowPage),
          matching: find.byType(Scrollable),
        )
        .last;
    await tester.scrollUntilVisible(
      find.text('전원 출석'),
      180,
      scrollable: attendanceScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('전원 출석'));
    await tester.pumpAndSettle();
    expect(
      (api.state['attendance'] as Map).values.every((v) => v == true),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('경기 시작 · 팀 설정'),
      180,
      scrollable: attendanceScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('경기 시작 · 팀 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A팀').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('B팀').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('경기 시작'));
    await tester.tap(find.text('경기 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선수1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '골'));
    await tester.pumpAndSettle();
    expect(find.text('골 1'), findsOneWidget);
    expect(find.text('1 : 0'), findsOneWidget);
    await tester.ensureVisible(find.text('마지막 기록 취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('마지막 기록 취소'));
    await tester.pumpAndSettle();
    expect(api.detail['scores'], {'A': 0, 'B': 0});
    await tester.ensureVisible(find.widgetWithText(FilledButton, '골'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '골'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('응급 · 부상 기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('응급 · 부상 기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('발목·발'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '상황 · 부상 내용'),
      '발목을 접질림',
    );
    await tester.ensureVisible(find.text('부상 기록 저장'));
    await tester.tap(find.text('부상 기록 저장'));
    await tester.pumpAndSettle();
    expect((api.state['injuries'] as List).length, 1);
    await tester.ensureVisible(find.text('경기 종료'));
    await tester.tap(find.text('경기 종료'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '경기 종료').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('결과 등록'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('결과 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('결과 등록'));
    await tester.pumpAndSettle();
    expect(api.status, 'completed');
    expect(find.text('공IN · 실력매칭'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '테스트 구장'));
    await tester.pumpAndSettle();
    expect(find.text('경기 결과'), findsOneWidget);
    expect(find.text('1 : 0'), findsOneWidget);
  });
  testWidgets('기존 결과는 지난 매치에서 원문으로 조회하고 재등록하지 않는다', (tester) async {
    await tester.pumpWidget(app(LoginRole.manager, LegacyApi()));
    await tester.pumpAndSettle();
    expect(find.text('테스트 구장'), findsNothing);
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '테스트 구장'));
    await tester.pumpAndSettle();
    expect(find.text('경기 결과'), findsOneWidget);
    expect(find.textContaining('기존 회원'), findsOneWidget);
    expect(find.text('원본 스코어: 5'), findsOneWidget);
    expect(find.textContaining('기록 원문: 100'), findsOneWidget);
    expect(find.text('결과 등록'), findsNothing);
    expect(find.text('0 : 0'), findsNothing);
  });
  testWidgets('좁은 화면에서 출석 명단과 팀 설정을 표시한다', (tester) async {
    tester.view.physicalSize = const Size(450, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi();
    await tester.pumpWidget(app(LoginRole.manager, api));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '테스트 구장'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final attendanceScroll = find
        .descendant(
          of: find.byType(MatchWorkflowPage),
          matching: find.byType(Scrollable),
        )
        .last;
    await tester.scrollUntilVisible(
      find.text('전원 출석'),
      180,
      scrollable: attendanceScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('전원 출석'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('경기 시작 · 팀 설정'),
      180,
      scrollable: attendanceScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('경기 시작 · 팀 설정'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
// [수정 끝]
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
