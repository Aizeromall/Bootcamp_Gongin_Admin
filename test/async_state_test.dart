// 수정 일 : 2026-10-30 / 작업자 : 양태건
// AsyncNotifier 전환 후 늦은 응답·중복 저장·오류 복구·조건 변경을 검증합니다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/login_notifier.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/match_notifier.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/match_workflow_notifier.dart';

class WorkflowApi extends OperationsApi {
  Completer<Map<String, dynamic>>? gate;
  final commands = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    if (json == null) return {'version': 2, 'status': 'attendance'};
    commands.add(json);
    if (gate != null) return gate!.future;
    return {'version': 3, 'status': 'live'};
  }
}

void main() {
  test('로그인 요청 중 로그아웃하면 늦은 인증 성공이 세션을 복구하지 않는다', () async {
    final gate = Completer<void>();
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      await gate.future;
      if (request.url.path != '/admin/login') return http.Response('{}', 401);
      return http.Response(
        jsonEncode({'result': 'OK', 'h_id': 'staff', 'role': 'headquarters'}),
        200,
      );
    });
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [loginClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(loginProvider.notifier);
    final first = notifier.login('staff', 'pw');
    await notifier.login('staff', 'pw');
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2); // 본사·매니저 각각 한 번만 인증합니다.
    notifier.reset();
    gate.complete();
    await first;
    expect(container.read(loginProvider).requireValue, isNull);
  });

  test('경기 명령 중복을 차단하고 실패 후 마지막 서버 상태·버전으로 재시도한다', () async {
    final api = WorkflowApi();
    final container = ProviderContainer(
      overrides: [operationsApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    const key = (managerId: 'staff', path: '/match/operations/1');
    final sub = container.listen(matchWorkflowProvider(key), (_, _) {});
    addTearDown(sub.close);
    await container.read(matchWorkflowProvider(key).future);
    final notifier = container.read(matchWorkflowProvider(key).notifier);
    api.gate = Completer();
    final first = notifier.command('start');
    expect(await notifier.command('start'), isFalse);
    expect(notifier.current!['version'], 2);
    api.gate!.completeError(const OperationsApiException(409, '다시 확인해 주세요.'));
    expect(await first, isFalse);
    expect(container.read(matchWorkflowProvider(key)).hasError, isTrue);
    expect(notifier.current!['status'], 'attendance');
    api.gate = null;
    expect(await notifier.command('start'), isTrue);
    expect(api.commands.length, 2);
    expect(api.commands.last['version'], 2);
    expect(
      container.read(matchWorkflowProvider(key)).requireValue['status'],
      'live',
    );
  });

  test('검색 조건 변경 후 이전 조회의 늦은 결과를 무시한다', () async {
    final old = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.queryParameters['keyword'] == '이전') return old.future;
      return http.Response(
        jsonEncode({
          'results': [
            {'g_code': 'new', 'g_name': '새 구장'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        operationsApiProvider.overrideWithValue(OperationsApi(client: client)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(groundListProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(groundListProvider.future);
    container.read(groundKeywordProvider.notifier).select('이전');
    final previous = container.read(groundListProvider.future);
    container.read(groundKeywordProvider.notifier).select('최신');
    expect(
      (await container.read(groundListProvider.future)).single.g_code,
      'new',
    );
    old.complete(http.Response('{"results":[]}', 200));
    await previous;
    expect(
      container.read(groundListProvider).requireValue.single.g_code,
      'new',
    );
  });
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
