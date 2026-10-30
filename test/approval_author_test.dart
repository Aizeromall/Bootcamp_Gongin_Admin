// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 품의 열람은 유지하고 원문 작성자가 본인인 경우 승인·반려 버튼만 숨깁니다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/headquarters/approval_panel.dart';

class AuthorApi extends OperationsApi {
  bool detailOwn = false;
  String document(String author) => jsonEncode({
    '유형': '휴가',
    '작성자': {'h_id': author, 'h_name': author},
    '내용': {},
    '결재선': [],
  });
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    if (Uri.parse(path).path == '/approval/requests') {
      return {
        'results': [
          {
            'm_code': 1,
            'h_id': 'other',
            'a_reason': '본인 작성 문서',
            'm_content': document('self'),
          },
          {
            'm_code': 2,
            'h_id': 'self',
            'a_reason': '타인 작성 문서',
            'm_content': document('other'),
          },
        ],
      };
    }
    return {
      'm_content': document(detailOwn ? 'self' : 'other'),
      'approval': [
        {'a_state': '심사중'},
      ],
    };
  }
}

void main() {
  for (final detailOwn in [false, true]) {
    testWidgets('본인 문서 열람 유지 및 결재 버튼 제한: $detailOwn', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = AuthorApi()..detailOwn = detailOwn;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [operationsApiProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: Scaffold(body: ApprovalPanel(staffId: 'self')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('휴가 · 본인 작성 문서'), findsOneWidget);
      expect(find.text('휴가 · 타인 작성 문서'), findsOneWidget);
      await tester.tap(find.text('휴가 · 타인 작성 문서'));
      await tester.pumpAndSettle();
      expect(find.text('승인'), detailOwn ? findsNothing : findsOneWidget);
      expect(find.text('반려'), detailOwn ? findsNothing : findsOneWidget);
    });
  }
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
