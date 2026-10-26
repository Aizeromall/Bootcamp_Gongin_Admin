import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/model/login_role.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/dashboard/dashboard_page.dart';

class FakeApi extends OperationsApi {
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    if (path.startsWith('/match/list/')) {
      return {
        'reservations': [
          {
            'r_seq': 1,
            'g_name': '테스트 구장',
            'c_name': '회원',
            'r_date': '2026-10-24',
            'rs_time': '10:00',
            're_time': '12:00',
          },
        ],
      };
    }
    return {'results': <Map<String, dynamic>>[]};
  }
}

void main() {
  Widget app(LoginRole role) => ProviderScope(
    overrides: [operationsApiProvider.overrideWithValue(FakeApi())],
    child: MaterialApp(
      home: DashboardPage(role: role, userId: 'test', onLogout: () {}),
    ),
  );
  testWidgets('본사 메뉴에서 문의 관리로 이동', (tester) async {
    await tester.pumpWidget(app(LoginRole.headquarters));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.question_answer_outlined));
    await tester.pumpAndSettle();
    expect(find.text('답변 대기'), findsOneWidget);
    expect(find.text('문의가 없습니다.'), findsOneWidget);
  });
  testWidgets('담당 경기에서 출석 및 경기 결과 입력 열기', (tester) async {
    await tester.pumpWidget(app(LoginRole.manager));
    await tester.pumpAndSettle();
    expect(find.text('테스트 구장'), findsOneWidget);
    await tester.tap(find.text('출석 등록'));
    await tester.pumpAndSettle();
    expect(find.text('등록 확정'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('경기 결과 등록'));
    await tester.pumpAndSettle();
    expect(find.text('종목 코드'), findsOneWidget);
    expect(find.text('최종 스코어'), findsOneWidget);
  });
}
