// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 로그인 담당자·필터별 조회를 분리하고 취소 성공 후 내 매치·취소 내역을 갱신합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/match_updates_model.dart';
import '../model/headquarters_model.dart';
import '../service/match_updates_service.dart';
import '../service/operations_api.dart';
import 'login_notifier.dart';
import 'headquarters_notifier.dart';

final matchUpdatesServiceProvider = Provider(
  (ref) => MatchUpdatesService(ref.watch(operationsApiProvider)),
);
typedef TeamMatchQuery = ({String staffId, String? status, String keyword});
final teamMatchesProvider = FutureProvider.autoDispose
    .family<List<TeamMatchRecord>, TeamMatchQuery>(
      (ref, q) => ref
          .watch(matchUpdatesServiceProvider)
          .teams(status: q.status, keyword: q.keyword),
      retry: (_, _) => null,
    );
final teamMatchProvider = FutureProvider.autoDispose
    .family<TeamMatchRecord, ({String staffId, int code})>(
      (ref, q) => ref.watch(matchUpdatesServiceProvider).team(q.code),
      retry: (_, _) => null,
    );
typedef CancelQuery = ({String staffId, String? managerId, int? reason});
final cancelledMatchesProvider = FutureProvider.autoDispose
    .family<List<CancelledMatch>, CancelQuery>(
      (ref, q) => ref
          .watch(matchUpdatesServiceProvider)
          .cancellations(managerId: q.managerId, reason: q.reason),
      retry: (_, _) => null,
    );
final cancelledDetailProvider = FutureProvider.autoDispose
    .family<AdminRow, ({String staffId, CancelledMatch match})>(
      (ref, q) =>
          ref.watch(matchUpdatesServiceProvider).cancellationDetail(q.match),
      retry: (_, _) => null,
    );
typedef CancellationKey = ({
  String managerId,
  String groundCode,
  String date,
  String start,
});

class MatchCancellation extends AsyncNotifier<void> {
  MatchCancellation(this.key);
  final CancellationKey key;
  @override
  void build() {
    ref.watch(loginProvider);
  }

  Future<bool> submit(int reason) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    try {
      await ref
          .read(matchUpdatesServiceProvider)
          .cancel(
            managerId: key.managerId,
            groundCode: key.groundCode,
            date: key.date,
            start: key.start,
            reason: reason,
          );
      if (!ref.mounted) return false;
      ref.invalidate(cancelledMatchesProvider);
      ref.invalidate(cancelledDetailProvider);
      ref.invalidate(teamMatchesProvider);
      ref.invalidate(teamMatchProvider);
      ref.invalidate(operationsDataProvider);
      ref.invalidate(adminDataProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      if (ref.mounted) {
        if (e is OperationsApiException && e.statusCode == 409) {
          ref.invalidate(operationsDataProvider);
          ref.invalidate(cancelledMatchesProvider);
        }
        state = AsyncError(e, s);
      }
      return false;
    }
  }
}

final matchCancellationProvider = AsyncNotifierProvider.autoDispose
    .family<MatchCancellation, void, CancellationKey>(MatchCancellation.new);
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
