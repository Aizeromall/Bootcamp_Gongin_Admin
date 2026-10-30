// 수정 일 : 2026-10-28 / 작업자 : 양태건
// Mock HTTP로 검색 인코딩·목록 선택·실제 코드 상세 조회를 검증합니다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/ground/ground_page.dart';

void main() {
  testWidgets('구장 검색 후 선택한 코드의 상세를 표시한다', (tester) async {
    final paths = <Uri>[];
    final row = {
      'g_code': 17,
      'g_name': '한강 구장',
      'g_address': '서울 마포구',
      'g_num': 12,
      'g_price': 50000,
      'g_information': '실내 구장',
    };
    final client = MockClient((request) async {
      paths.add(request.url);
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/17')
              ? row
              : {
                  'results': [row],
                },
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationsApiProvider.overrideWithValue(
            OperationsApi(client: client),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: GroundPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '서울');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(paths.last.queryParameters['keyword'], '서울');
    await tester.tap(find.text('한강 구장'));
    await tester.pumpAndSettle();
    expect(paths.last.path, '/match/ground/17');
    expect(find.text('50000원'), findsOneWidget);
    expect(find.text('실내 구장'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
