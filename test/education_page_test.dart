// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 교육 API는 Mock으로 대체하며 실제 DB를 호출하지 않습니다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/model/login_role.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/education/education_page.dart';
import 'package:bootcamp_project_gongin_admin_app/view/dashboard/dashboard_page.dart';

class FakeEducationApi extends OperationsApi {
  bool failList = false, failCreate = false, failComplete = false;
  int completionWrites = 0, creationWrites = 0;
  Completer<void>? gate;
  Map<String, dynamic>? lastCreation;
  final managers = <Map<String, dynamic>>[
    for (var i = 0; i < 5; i++)
      {
        'm_id': [
          'MG2025014',
          'MG2024007',
          'MG2025021',
          'MG2024033',
          'MG2025030',
        ][i],
        'm_name': ['정하늘', '김도현', '이수아', '박준영', '최예린'][i],
        'm_workplace': '본사 담당 구장',
      },
  ];
  late final courses = <Map<String, dynamic>>[
    {
      'course_id': 'edu_safety',
      'title': '안전 · 응급처치 (CPR · AED)',
      'category': '필수',
      'format': '오프라인',
      'scheduled_at': '2026-11-05T14:00:00',
      'duration_minutes': 180,
      'location': '본사 3층 교육장',
      'instructor': '대한적십자사 강사',
      'description': '경기 중 부상·심정지 대응. 교육 종료 후 출석부와 퀴즈 결과를 확인해 주세요.',
      'completed_count': 0,
      'total': 5,
      'managers': [
        for (var i = 0; i < 5; i++)
          {
            'training_seq': i + 1,
            'm_id': managers[i]['m_id'],
            'name': managers[i]['m_name'],
            'workplace': managers[i]['m_workplace'],
            'completed': false,
          },
      ],
    },
  ];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    if (path == '/education/courses' && json == null) {
      if (failList) {
        throw const OperationsApiException(500, '교육 목록을 불러오지 못했습니다.');
      }
      return jsonDecode(
        jsonEncode({
          'results': courses,
          'total': courses.length,
          'required_pending': courses
              .where(
                (c) =>
                    c['category'] == '필수' && c['completed_count'] < c['total'],
              )
              .length,
        }),
      ) as Map<String, dynamic>;
    }
    if (path == '/education/managers') return {'results': managers};
    if (path == '/education/courses' && json != null) {
      creationWrites++;
      lastCreation = json;
      if (failCreate) {
        throw const OperationsApiException(422, '교육을 개설하지 못했습니다.');
      }
      courses.add({
        ...json,
        'course_id': 'edu_new',
        'completed_count': 0,
        'total': (json['manager_ids'] as List).length,
        'managers': <Map<String, dynamic>>[],
      });
      return {'result': 'OK', 'course_id': 'edu_new'};
    }
    if (path.startsWith('/education/completion/')) {
      completionWrites++;
      if (gate != null) await gate!.future;
      if (failComplete) {
        throw const OperationsApiException(500, '이수 처리를 완료하지 못했습니다.');
      }
      final id = int.parse(path.split('/').last);
      for (final c in courses) {
        for (final m in c['managers'] as List) {
          if (m['training_seq'] == id) m['completed'] = true;
        }
        c['completed_count'] = (c['managers'] as List)
            .where((m) => m['completed'] == true)
            .length;
      }
      return {'result': 'OK', 'training_seq': id, 'completed': true};
    }
    return {'results': <Map<String, dynamic>>[]};
  }
}

void main() {
  Widget app(FakeEducationApi api, {LoginRole? role}) => ProviderScope(
    retry: (_, _) => null,
    overrides: [operationsApiProvider.overrideWithValue(api)],
    child: MaterialApp(
      home: role == null
          ? Scaffold(body: EducationPage(staffId: 'hq01'))
          : DashboardPage(
              role: role,
              userId: 'hq01',
              userName: '본사 직원',
              department: '운영팀',
              onLogout: () {},
            ),
    ),
  );
  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> visibleTap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('Figma 교육 목록·상세·이수 집계를 표시한다', (tester) async {
    size(tester, const Size(1180, 820));
    await tester.pumpWidget(app(FakeEducationApi()));
    await tester.pumpAndSettle();
    expect(find.text('과정 1개 · 미이수 필수 1과정'), findsOneWidget);
    expect(find.text('대상 매니저 · 이수 현황'), findsOneWidget);
    expect(find.text('0/5 (0%)'), findsOneWidget);
    expect(find.text('정하늘'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('교육이 없으면 실제 빈 상태와 개설 버튼을 표시한다', (tester) async {
    final api = FakeEducationApi();
    api.courses.clear();
    await tester.pumpWidget(app(api));
    await tester.pumpAndSettle();
    expect(find.text('+ 교육 개설'), findsOneWidget);
    expect(find.textContaining('등록된 교육이 없습니다.'), findsOneWidget);
    expect(find.text('안전 · 응급처치 (CPR · AED)'), findsNothing);
  });
  testWidgets('조회 실패는 빈 상태로 숨기지 않고 재시도한다', (tester) async {
    final api = FakeEducationApi()..failList = true;
    await tester.pumpWidget(app(api));
    await tester.pumpAndSettle();
    expect(find.text('교육 목록을 불러오지 못했습니다.'), findsOneWidget);
    api.failList = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('안전 · 응급처치 (CPR · AED)'), findsOneWidget);
  });
  testWidgets('이수 처리는 확인 후 한 번만 전송하고 집계를 갱신한다', (tester) async {
    size(tester, const Size(1180, 900));
    final api = FakeEducationApi()..gate = Completer<void>();
    await tester.pumpWidget(app(api));
    await tester.pumpAndSettle();
    await visibleTap(tester, find.widgetWithText(FilledButton, '이수 처리').first);
    await tester.tap(find.text('이수 확정'));
    await tester.pump();
    expect(api.completionWrites, 1);
    for (final button in tester.widgetList<FilledButton>(
      find.widgetWithText(FilledButton, '이수 처리'),
    )) {
      expect(button.onPressed, isNull);
    }
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('1/5 (20%)'), findsOneWidget);
    expect(find.text('이수 처리를 완료했습니다.'), findsOneWidget);
  });
  testWidgets('개설 실패 시 입력과 선택 대상을 보존하고 재시도한다', (tester) async {
    size(tester, const Size(1300, 1100));
    final api = FakeEducationApi()..failCreate = true;
    await tester.pumpWidget(app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ 교육 개설'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '교육 제목'),
      '신규 교육 과정',
    );
    await visibleTap(tester, find.text('교육 일정 선택'));
    await tester.tap(find.text('선택').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '교육 장소'),
      '본사 교육장',
    );
    await visibleTap(tester, find.widgetWithText(CheckboxListTile, '정하늘'));
    await visibleTap(tester, find.widgetWithText(FilledButton, '교육 개설'));
    expect(api.creationWrites, 1);
    expect(find.text('신규 교육 과정'), findsOneWidget);
    expect(find.byType(EducationCreateDialog), findsOneWidget);
    expect(api.lastCreation!['manager_ids'], ['MG2025014']);
    api.failCreate = false;
    await visibleTap(tester, find.widgetWithText(FilledButton, '교육 개설'));
    expect(find.byType(EducationCreateDialog), findsNothing);
    expect(api.creationWrites, 2);
    expect(find.text('교육을 개설했습니다.'), findsOneWidget);
  });
  testWidgets('작은 화면에서 교육 선택과 목록 복귀를 제공한다', (tester) async {
    size(tester, const Size(390, 844));
    await tester.pumpWidget(app(FakeEducationApi()));
    await tester.pumpAndSettle();
    expect(find.text('대상 매니저 · 이수 현황'), findsNothing);
    await tester.tap(find.text('안전 · 응급처치 (CPR · AED)'));
    await tester.pumpAndSettle();
    expect(find.text('대상 매니저 · 이수 현황'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('교육 목록으로'));
    await tester.pumpAndSettle();
    expect(find.text('대상 매니저 · 이수 현황'), findsNothing);
  });
  testWidgets('본사에만 교육 메뉴와 212px 디자인 셸을 제공한다', (tester) async {
    size(tester, const Size(1180, 820));
    await tester.pumpWidget(
      app(FakeEducationApi(), role: LoginRole.headquarters),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-education')));
    await tester.pumpAndSettle();
    expect(find.text('본사 관리자'), findsOneWidget);
    expect(find.text('대상 매니저 · 이수 현황'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(FakeEducationApi(), role: LoginRole.manager));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-education')), findsNothing);
  });
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
