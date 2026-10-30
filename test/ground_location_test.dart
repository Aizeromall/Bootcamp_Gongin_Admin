// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 네이티브 지도·실제 서버 대신 Mock으로 선택·경합·오류·회원 범위를 검증합니다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/ground_location_notifier.dart';
import 'package:bootcamp_project_gongin_admin_app/view/headquarters/ground_location_picker.dart';
import 'package:bootcamp_project_gongin_admin_app/view/headquarters/approval_writer.dart';

import 'headquarters_test.dart' show HeadquartersFake;

http.Response locationResponse(double lat) => http.Response(
  jsonEncode({'g_address': '선택한 구장 주소 $lat', 'g_lat': lat, 'g_lng': 127.0}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test('늦은 이전 응답이 최신 선택을 덮어쓰지 않고 담당자 간 선택을 분리한다', () async {
    final first = Completer<http.Response>(),
        second = Completer<http.Response>();
    var calls = 0;
    final client = MockClient((request) {
      expect(request.url.path, '/approval/ground-location');
      return ++calls == 1 ? first.future : second.future;
    });
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        operationsApiProvider.overrideWithValue(OperationsApi(client: client)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(groundLocationProvider('staff1'), (_, _) {});
    addTearDown(sub.close);
    await container.read(groundLocationProvider('staff1').future);
    final notifier = container.read(groundLocationProvider('staff1').notifier);
    final a = notifier.select(37, 127), b = notifier.select(38, 127);
    second.complete(locationResponse(38));
    await b;
    first.complete(locationResponse(37));
    await a;
    expect(
      container.read(groundLocationProvider('staff1')).asData!.value!.latitude,
      38,
    );
    expect(
      await container.read(groundLocationProvider('staff2').future),
      isNull,
    );
  });
  testWidgets('지도 선택 주소만 보여주며 오류 시 이전 좌표로 제출하지 않는다', (tester) async {
    var fail = false;
    final client = MockClient(
      (request) async => fail ? http.Response('{}', 500) : locationResponse(37),
    );
    addTearDown(client.close);
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationsApiProvider.overrideWithValue(
            OperationsApi(client: client),
          ),
          groundMapBuilderProvider.overrideWithValue(
            (picked) => TextButton(
              onPressed: () => picked(37, 127),
              child: const Text('지도 위치 선택'),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Form(
              key: form,
              child: const GroundLocationPicker(staffId: 'staff'),
            ),
          ),
        ),
      ),
    );
    expect(form.currentState!.validate(), isFalse);
    await tester.tap(find.text('지도 위치 선택'));
    await tester.pumpAndSettle();
    expect(find.text('선택한 주소 · 선택한 구장 주소 37.0'), findsOneWidget);
    expect(form.currentState!.validate(), isTrue);
    expect(find.byType(TextFormField), findsNothing);
    fail = true;
    await tester.tap(find.text('지도 위치 선택'));
    await tester.pumpAndSettle();
    expect(form.currentState!.validate(), isFalse);
    expect(find.text('선택한 주소 · 선택한 구장 주소 37.0'), findsNothing);
  });
  testWidgets('신규 계약 구장 정보에 주소·좌표 입력 대신 지도 선택이 나온다', (tester) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationsApiProvider.overrideWithValue(HeadquartersFake()),
          groundMapBuilderProvider.overrideWithValue(
            (picked) => const Text('구장 선택 지도'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ApprovalWriter(staffId: 'hq')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('품의 양식'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신규 계약 · 양식 13').last);
    await tester.pumpAndSettle();
    expect(find.text('구장 선택 지도'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '전체 주소'), findsNothing);
    expect(find.widgetWithText(TextFormField, '위도'), findsNothing);
    expect(find.widgetWithText(TextFormField, '경도'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
