// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 담당 종목·평가 원문·특정 매니저 재교육 연결은 HTTP Mock으로 검증합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/service/education_service.dart';
import 'package:bootcamp_project_gongin_admin_app/view/education/education_page.dart';

import 'education_page_test.dart' show FakeEducationApi;

class ContextApi extends FakeEducationApi {
  final reads = <String>[];
  bool failEvaluation = false, failSports = false;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    reads.add(path);
    if (path == '/approval/grounds/managers') {
      if (failSports) throw const OperationsApiException(500, '담당 종목 조회 실패');
      return {
        'results': [
          {
            'm_id': 'MG2025014',
            'assign': [
              {'g_code': '7'},
              {'g_code': 9},
              {'g_code': 7},
            ],
          },
          {
            'm_id': 'MG2024007',
            'assign': [
              {'g_code': 8},
            ],
          },
          {'m_id': 'MG2025021', 'assign': []},
        ],
      };
    }
    if (path == '/match/ground') {
      return {
        'results': [
          {'g_code': 7, 'e_code': '축구'},
          {'g_code': 9, 'e_code': '배구'},
          {'g_code': 8, 'e_code': null},
        ],
      };
    }
    if (path.startsWith('/management/managers/')) {
      if (failEvaluation) {
        throw const OperationsApiException(500, '평가 이력 조회 실패');
      }
      return {
        'evaluates': [
          {'e_date': '2026-09-30', 'e_detail': '기존 평가 원문: 안전 안내 개선 필요'},
        ],
      };
    }
    return super.request(path, json: json, form: form);
  }
}

void main() {
  Widget host(ContextApi api) => ProviderScope(
    overrides: [operationsApiProvider.overrideWithValue(api)],
    child: const MaterialApp(
      home: Scaffold(body: EducationPage(staffId: 'hq')),
    ),
  );
  void size(WidgetTester t) {
    t.view.physicalSize = const Size(1180, 820);
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

  test('담당 종목은 구장 코드로 연결·중복 제거하고 미기록과 배정 없음을 구분한다', () async {
    final api = ContextApi();
    final sports = await EducationService(api).assignedSports();
    expect(sports['MG2025014'], ['축구', '배구']);
    expect(sports['MG2024007'], ['종목 미기록']);
    expect(sports['MG2025021'], isEmpty);
    expect(sports.containsKey('MG2025030'), isFalse);
    expect(api.reads.length, 2);
  });
  testWidgets('종목 조회는 매니저 수와 무관하게 공유하고 평가는 버튼을 눌렀을 때 조회한다', (t) async {
    size(t);
    final api = ContextApi();
    await t.pumpWidget(host(api));
    await t.pumpAndSettle();
    expect(find.text('축구 · 배구'), findsOneWidget);
    expect(api.reads.where((p) => p == '/approval/grounds/managers').length, 1);
    expect(
      api.reads.where((p) => p.startsWith('/management/managers/')),
      isEmpty,
    );
    await tap(t, find.byKey(const ValueKey('evaluation:MG2025014')));
    expect(api.reads, contains('/management/managers/MG2025014'));
    expect(find.text('기존 평가 원문: 안전 안내 개선 필요'), findsWidgets);
    expect(find.text('2026-09-30'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('평가 조회 실패는 빈 이력으로 숨기지 않고 재시도한다', (t) async {
    size(t);
    final api = ContextApi()..failEvaluation = true;
    await t.pumpWidget(host(api));
    await t.pumpAndSettle();
    await tap(t, find.byKey(const ValueKey('evaluation:MG2025014')));
    expect(find.text('평가 이력 조회 실패'), findsOneWidget);
    api.failEvaluation = false;
    await tap(t, find.text('다시 시도'));
    expect(find.text('기존 평가 원문: 안전 안내 개선 필요'), findsWidgets);
  });
  testWidgets('평가에서 재교육을 열면 해당 매니저만 선택되며 초기화할 수 있다', (t) async {
    size(t);
    final api = ContextApi();
    await t.pumpWidget(host(api));
    await t.pumpAndSettle();
    await tap(t, find.byKey(const ValueKey('evaluation:MG2025014')));
    await tap(t, find.text('이 매니저 재교육 개설'));
    expect(
      t
          .widget<EducationCreateDialog>(find.byType(EducationCreateDialog))
          .category,
      '재교육',
    );
    final checked = t
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .where((c) => c.value == true);
    expect(checked.length, 1);
    expect((checked.single.title as Text).data, '정하늘');
    await tap(t, find.text('대상 선택 초기화'));
    expect(
      t
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((c) => c.value == false),
      isTrue,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('현재 대상 명단에서 제외된 매니저는 교육 저장 요청을 보내지 않는다', (t) async {
    size(t);
    final api = ContextApi();
    await t.pumpWidget(
      ProviderScope(
        overrides: [operationsApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(
            body: EducationCreateDialog(
              staffId: 'hq',
              category: '재교육',
              initialManagerId: 'retired_manager',
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, '교육 제목'), '재교육');
    await tap(t, find.text('교육 일정 선택'));
    await tap(t, find.text('선택').last);
    await tap(t, find.text('선택').last);
    await t.enterText(find.widgetWithText(TextFormField, '교육 장소'), '본사 교육장');
    await tap(t, find.widgetWithText(FilledButton, '교육 개설'));
    expect(api.creationWrites, 0);
    expect(
      find.text('현재 배정 가능한 매니저만 선택해 주세요. 선택을 초기화한 뒤 다시 선택할 수 있습니다.'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
