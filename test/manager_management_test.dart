// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 매니저 상세의 제재 이력만 숨기고 기존 배정 이력을 보존합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/management/management_page.dart';

class ManagerManagementApi extends OperationsApi {
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    if (Uri.parse(path).path == '/management/managers') {
      return {
        'total': 1,
        'results': [
          {
            'm_id': 'manager1',
            'm_name': '매니저 하나',
            'sanction_count': 0,
            'match_count': 12,
          },
        ],
      };
    }
    return {
      'm_id': 'manager1',
      'm_name': '매니저 하나',
      'sanction_count': 0,
      'sanctions': [
        {'s_detail': '숨길 제재'},
      ],
      'assigns': [
        {'g_name': '배정 구장'},
      ],
    };
  }
}

void main() {
  testWidgets('매니저 상세는 제재 이력을 숨기고 구장 배정 이력을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(1200, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationsApiProvider.overrideWithValue(ManagerManagementApi()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ManagementPage(managers: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('manager1 · 경기 12건'), findsOneWidget);
    expect(find.text('manager1 · 제재 0건'), findsNothing);
    expect(find.text('제재 이력'), findsNothing);
    expect(find.text('숨길 제재'), findsNothing);
    expect(find.text('제재 건수'), findsNothing);
    expect(find.text('구장 배정 이력'), findsOneWidget);
  });
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
