// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 담당자·결과 유형·종목별 조회를 분리합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/manager_result_model.dart';
import '../model/login_role.dart';
import '../service/manager_result_service.dart';
import '../service/operations_api.dart';
import 'login_notifier.dart';

final managerResultServiceProvider = Provider(
  (ref) => ManagerResultService(ref.watch(operationsApiProvider)),
);
typedef ManagerResultQuery = ({String managerId, String kind, String sport});
final managerResultsProvider = FutureProvider.autoDispose
    .family<List<ManagerResult>, ManagerResultQuery>((ref, query) {
      final session = ref.watch(loginProvider).asData?.value;
      if (session?.userId != query.managerId ||
          session?.role != LoginRole.manager) {
        throw const OperationsApiException(403, '로그인한 매니저의 결과만 조회할 수 있습니다.');
      }
      return ref
          .watch(managerResultServiceProvider)
          .list(query.kind, query.sport);
    }, retry: (_, _) => null);
final managerResultDetailProvider = FutureProvider.autoDispose
    .family<ManagerResult, ({String managerId, String code})>((ref, query) {
      final session = ref.watch(loginProvider).asData?.value;
      if (session?.userId != query.managerId ||
          session?.role != LoginRole.manager) {
        throw const OperationsApiException(403, '로그인한 매니저의 결과만 조회할 수 있습니다.');
      }
      return ref.watch(managerResultServiceProvider).detail(query.code);
    }, retry: (_, _) => null);
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

final managerRatingRulesProvider =
    FutureProvider.autoDispose<ManagerRatingRules>(
      (ref) async => ManagerRatingRules.fromJson(
        await ref
            .watch(operationsApiProvider)
            .request('/match/rating/stat_keys'),
      ),
      retry: (_, _) => null,
    );
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

final managerTeamRosterProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String managerId, int code})>((
      ref,
      query,
    ) async {
      final session = ref.watch(loginProvider).asData?.value;
      if (session?.userId != query.managerId ||
          session?.role != LoginRole.manager) {
        throw const OperationsApiException(403, '로그인한 매니저의 일정만 조회할 수 있습니다.');
      }
      return ref
          .watch(operationsApiProvider)
          .request('/match/manager/teams/${query.code}/roster');
    }, retry: (_, _) => null);
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
