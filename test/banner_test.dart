// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 실제 DB·서버 호출 없이 배너 multipart·기간 선택·권한·중복 저장을 검증합니다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/model/login_role.dart';
import 'package:bootcamp_project_gongin_admin_app/service/banner_service.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/view/headquarters/announcement_panel.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/banner_notifier.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/login_notifier.dart';

class BannerLogin extends LoginNotifier {
  BannerLogin(this.department);
  final String department;
  @override
  StaffSession? build() => StaffSession(
    userId: 'staff',
    role: LoginRole.headquarters,
    department: department,
  );
}

http.Response response(Object body, [int code = 200]) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test('업로드는 multipart file과 로그인 직원 ID를 전송한다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/images/banner');
      expect(request.headers['content-type'], contains('multipart/form-data'));
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.body, contains('name="h_id"'));
      expect(request.body, contains('staff'));
      expect(request.body, contains('filename="banner.png"'));
      return response({
        'b_seq': 7,
        'image_url': '/images/banner/files/file.png',
      }, 201);
    });
    addTearDown(client.close);
    final image = await BannerService(
      OperationsApi(client: client, accessToken: 'test-token'),
    ).upload('staff', 'banner.png', [1, 2, 3]);
    expect(image.id, 7);
    expect(image.chosen, false);
  });
  test('목록과 상대 이미지 주소를 서버 주소 기준으로 해석한다', () async {
    final client = MockClient(
      (request) async => response({
        'results': [
          {
            'b_seq': 2,
            'image_url': '/images/banner/files/a.png',
            'is_chosen': 1,
          },
        ],
      }),
    );
    addTearDown(client.close);
    final images = await BannerService(OperationsApi(client: client)).list();
    expect(images.single.chosen, true);
    expect(
      Uri.parse(BannerService.imageUrl(images.single.url)).path,
      '/images/banner/files/a.png',
    );
  });
  test('기간 선택 실패를 유지하고 중복 제출을 막은 뒤 재시도한다', () async {
    final gate = Completer<void>();
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/images/banner-select');
      expect(jsonDecode(request.body), {
        'h_id': 'staff',
        'b_seq': 7,
        'c_start': '2026-10-28',
        'c_end': '2026-10-30',
      });
      if (calls == 1) {
        await gate.future;
        return response({
          'detail': {'message': '이미 선택된 기간입니다.'},
        }, 409);
      }
      return response({'c_image_seq': 5, 'c_boolean': true}, 201);
    });
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        loginProvider.overrideWith(() => BannerLogin('홍보팀')),
        operationsApiProvider.overrideWithValue(OperationsApi(client: client)),
      ],
    );
    addTearDown(container.dispose);
    final provider = bannerMutationProvider('staff');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final notifier = container.read(provider.notifier);
    final first = notifier.choose(7, '2026-10-28', '2026-10-30');
    expect(await notifier.choose(7, '2026-10-28', '2026-10-30'), false);
    gate.complete();
    expect(await first, false);
    expect(container.read(provider).hasError, true);
    expect(calls, 1);
    expect(await notifier.choose(7, '2026-10-28', '2026-10-30'), true);
  });
  test('다른 부서는 업로드 요청을 보내지 않는다', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return response({});
    });
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        loginProvider.overrideWith(() => BannerLogin('운영팀')),
        operationsApiProvider.overrideWithValue(OperationsApi(client: client)),
      ],
    );
    addTearDown(container.dispose);
    final provider = bannerMutationProvider('staff');
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    expect(await container.read(provider.notifier).upload('a.png', [1]), null);
    expect(calls, 0);
    expect(container.read(provider).hasError, true);
  });
  testWidgets('공지 작성에서 배너 설정을 열고 권한과 빈 목록을 표시한다', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, '/images/banner');
      return response({'results': []});
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginProvider.overrideWith(() => BannerLogin('운영팀')),
          operationsApiProvider.overrideWithValue(
            OperationsApi(client: client),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAnnouncementWriter(context, 'staff'),
                child: const Text('작성 열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('작성 열기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('배너 이미지 선택·등록'));
    await tester.tap(find.text('배너 이미지 선택·등록'));
    await tester.pumpAndSettle();
    expect(find.text('배너 등록·선택은 홍보팀 직원만 가능합니다.'), findsOneWidget);
    expect(find.text('등록된 배너 이미지가 없습니다.'), findsOneWidget);
    expect(find.text('기기에서 이미지 선택'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
