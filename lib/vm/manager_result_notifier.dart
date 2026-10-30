import 'dart:async';

// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 담당자·결과 유형·종목별 조회를 분리합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/manager_result_model.dart';
import '../model/login_role.dart';
import '../model/match_updates_model.dart';
import '../service/match_updates_service.dart';
import '../service/manager_result_service.dart';
import '../service/operations_api.dart';
import 'login_notifier.dart';

final managerResultServiceProvider = Provider(
  (ref) => ManagerResultService(ref.watch(operationsApiProvider)),
);
typedef ManagerResultQuery = ({String managerId, String kind, String sport});
final managerResultsProvider = AsyncNotifierProvider.autoDispose
    .family<ManagerResultsNotifier, List<ManagerResult>, ManagerResultQuery>(
      ManagerResultsNotifier.new,
      retry: (_, _) => null,
    );
final managerResultDetailProvider = AsyncNotifierProvider.autoDispose
    .family<
      ManagerResultDetailNotifier,
      ManagerResult,
      ({String managerId, String code})
    >(ManagerResultDetailNotifier.new, retry: (_, _) => null);
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

final managerRatingRulesProvider =
    AsyncNotifierProvider.autoDispose<
      ManagerRatingRulesNotifier,
      ManagerRatingRules
    >(ManagerRatingRulesNotifier.new, retry: (_, _) => null);
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

final managerTeamRosterProvider = AsyncNotifierProvider.autoDispose
    .family<
      ManagerTeamRosterNotifier,
      Map<String, dynamic>,
      ({String managerId, int code})
    >(ManagerTeamRosterNotifier.new, retry: (_, _) => null);
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 담당자·유형·종목별 취소 목록을 분리하며 다른 계정의 캐시를 사용하지 않습니다.
final managerCancelledResultsProvider = AsyncNotifierProvider.autoDispose
    .family<
      ManagerCancelledResultsNotifier,
      List<CancelledMatch>,
      ManagerResultQuery
    >(ManagerCancelledResultsNotifier.new, retry: (_, _) => null);
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class ManagerResultsNotifier extends AsyncNotifier<List<ManagerResult>> {
  ManagerResultsNotifier(this.query);
  final ManagerResultQuery query;
  @override
  FutureOr<List<ManagerResult>> build() {
    final session = ref.watch(loginProvider).asData?.value;
    if (session?.userId != query.managerId ||
        session?.role != LoginRole.manager) {
      throw const OperationsApiException(403, '로그인한 매니저의 결과만 조회할 수 있습니다.');
    }
    return ref
        .watch(managerResultServiceProvider)
        .list(query.kind, query.sport);
  }
}

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class ManagerResultDetailNotifier extends AsyncNotifier<ManagerResult> {
  ManagerResultDetailNotifier(this.query);
  final ({String managerId, String code}) query;
  @override
  FutureOr<ManagerResult> build() {
    final session = ref.watch(loginProvider).asData?.value;
    if (session?.userId != query.managerId ||
        session?.role != LoginRole.manager) {
      throw const OperationsApiException(403, '로그인한 매니저의 결과만 조회할 수 있습니다.');
    }
    return ref.watch(managerResultServiceProvider).detail(query.code);
  }
}

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class ManagerRatingRulesNotifier extends AsyncNotifier<ManagerRatingRules> {
  @override
  Future<ManagerRatingRules> build() async => ManagerRatingRules.fromJson(
    await ref.watch(operationsApiProvider).request('/match/rating/stat_keys'),
  );
}

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class ManagerTeamRosterNotifier extends AsyncNotifier<Map<String, dynamic>> {
  ManagerTeamRosterNotifier(this.query);
  final ({String managerId, int code}) query;
  @override
  Future<Map<String, dynamic>> build() async {
    final session = ref.watch(loginProvider).asData?.value;
    if (session?.userId != query.managerId ||
        session?.role != LoginRole.manager) {
      throw const OperationsApiException(403, '로그인한 매니저의 일정만 조회할 수 있습니다.');
    }
    return ref
        .watch(operationsApiProvider)
        .request('/match/manager/teams/${query.code}/roster');
  }
}

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class ManagerCancelledResultsNotifier
    extends AsyncNotifier<List<CancelledMatch>> {
  ManagerCancelledResultsNotifier(this.query);
  final ManagerResultQuery query;
  @override
  FutureOr<List<CancelledMatch>> build() {
    final session = ref.watch(loginProvider).asData?.value;
    if (session?.userId != query.managerId ||
        session?.role != LoginRole.manager) {
      throw const OperationsApiException(403, '로그인한 매니저의 취소 내역만 조회할 수 있습니다.');
    }
    return MatchUpdatesService(ref.watch(operationsApiProvider)).cancellations(
      managerId: query.managerId,
      kind: query.kind,
      sport: query.sport,
    );
  }
}

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
