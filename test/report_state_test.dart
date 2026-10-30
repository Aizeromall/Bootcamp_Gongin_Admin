// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 필터·담당자 캐시 분리와 nullable 신고 모델을 Mock으로 검증합니다.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/model/report_model.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/report_notifier.dart';

class DeferredReportApi extends OperationsApi {
  final requests = <String>[];
  final pending = <String, Completer<Map<String, dynamic>>>{};
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    requests.add(path);
    return pending
        .putIfAbsent(
          Uri.parse(path).queryParameters['state'] ?? 'all',
          () => Completer<Map<String, dynamic>>(),
        )
        .future;
  }
}

Map<String, dynamic> collection(int id) => {
  'results': [
    {'r_seq': id, 'state_text': '접수'},
  ],
  'total': 1,
};
void main() {
  test('응답에 없는 이력 수치를 0으로 만들지 않는다', () {
    final report = ReportRecord.fromJson({'r_seq': '1', 'r_evidence': null});
    expect(report.id, 1);
    expect(report.warnings, isNull);
    expect(report.receivedReports, isNull);
    expect(report.accountState, isNull);
    expect(report.evidence, isEmpty);
  });
  test('누락된 신고 식별자를 가짜 ID로 변환하지 않는다', () {
    expect(() => ReportRecord.fromJson({}), throwsFormatException);
  });
  test('늦은 이전 필터 응답이 현재 결과를 덮어쓰지 않는다', () async {
    final api = DeferredReportApi();
    final container = ProviderContainer(
      overrides: [operationsApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    const old = (staffId: 'hq01', state: '접수', sport: null);
    const current = (staffId: 'hq01', state: '심의중', sport: null);
    final sub1 = container.listen(reportListProvider(old), (_, _) {});
    final sub2 = container.listen(reportListProvider(current), (_, _) {});
    addTearDown(sub1.close);
    addTearDown(sub2.close);
    final oldFuture = container.read(reportListProvider(old).future);
    final currentFuture = container.read(reportListProvider(current).future);
    api.pending['심의중']!.complete(collection(2));
    expect((await currentFuture).reports.single.id, 2);
    api.pending['접수']!.complete(collection(1));
    await oldFuture;
    expect(
      container
          .read(reportListProvider(current))
          .requireValue
          .reports
          .single
          .id,
      2,
    );
  });
  test('담당자가 다르면 같은 필터라도 별도 provider로 조회한다', () async {
    final api = DeferredReportApi();
    final container = ProviderContainer(
      overrides: [operationsApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    const one = (staffId: 'hq01', state: null, sport: null);
    const two = (staffId: 'hq02', state: null, sport: null);
    final sub1 = container.listen(reportListProvider(one), (_, _) {});
    final sub2 = container.listen(reportListProvider(two), (_, _) {});
    addTearDown(sub1.close);
    addTearDown(sub2.close);
    final a = container.read(reportListProvider(one).future),
        b = container.read(reportListProvider(two).future);
    api.pending['all']!.complete(collection(1));
    await Future.wait([a, b]);
    expect(api.requests.length, 2);
  });
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
