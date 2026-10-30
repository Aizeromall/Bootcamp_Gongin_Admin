import 'dart:async';

// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 로그인 담당자·필터별 조회를 분리하고 취소 성공 후 내 매치·취소 내역을 갱신합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/match_updates_model.dart';
import '../model/headquarters_model.dart';
import '../service/match_updates_service.dart';
import '../service/operations_api.dart';
import 'login_notifier.dart';
import 'manager_schedule_notifier.dart';
import 'manager_result_notifier.dart';
import 'headquarters_notifier.dart';

final matchUpdatesServiceProvider = Provider(
  (ref) => MatchUpdatesService(ref.watch(operationsApiProvider)),
);
typedef TeamMatchQuery = ({String staffId, String? status, String keyword});
final teamMatchesProvider = AsyncNotifierProvider.autoDispose
    .family<TeamMatchesNotifier, List<TeamMatchRecord>, TeamMatchQuery>(
      TeamMatchesNotifier.new,
      retry: (_, _) => null,
    );
final teamMatchProvider = AsyncNotifierProvider.autoDispose
    .family<TeamMatchNotifier, TeamMatchRecord, ({String staffId, int code})>(
      TeamMatchNotifier.new,
      retry: (_, _) => null,
    );
typedef CancelQuery = ({String staffId, String? managerId, int? reason});
final cancelledMatchesProvider = AsyncNotifierProvider.autoDispose
    .family<CancelledMatchesNotifier, List<CancelledMatch>, CancelQuery>(
      CancelledMatchesNotifier.new,
      retry: (_, _) => null,
    );
final cancelledDetailProvider = AsyncNotifierProvider.autoDispose
    .family<
      CancelledDetailNotifier,
      AdminRow,
      ({String staffId, CancelledMatch match})
    >(CancelledDetailNotifier.new, retry: (_, _) => null);
typedef CancellationKey = ({
  String managerId,
  String groundCode,
  String date,
  String start,
});

class MatchCancellation extends AsyncNotifier<void> {
  MatchCancellation(this.key, {this.teamCode});
  final int? teamCode;
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
            teamCode: teamCode,
          );
      if (!ref.mounted) return false;
      ref.invalidate(cancelledMatchesProvider);
      ref.invalidate(managerCancelledResultsProvider);
      ref.invalidate(cancelledDetailProvider);
      ref.invalidate(teamMatchesProvider);
      ref.invalidate(teamMatchProvider);
      // 수정 일 : 2026-10-30 / 작업자 : 양태건
      // 취소된 팀매칭이 선택 날짜의 목록·상세에 남지 않도록 갱신합니다.
      ref.invalidate(managerScheduleProvider);
      ref.invalidate(managerMatchDayProvider);
      ref.invalidate(scheduledTeamMatchProvider);
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

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 팀 경기코드까지 키로 분리하여 같은 시간대의 다른 취소 상태를 재사용하지 않습니다.
final teamMatchCancellationProvider = AsyncNotifierProvider.autoDispose
    .family<MatchCancellation, void, ({CancellationKey target, int teamCode})>(
      (key) => MatchCancellation(key.target, teamCode: key.teamCode),
    );
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class TeamMatchesNotifier extends AsyncNotifier<List<TeamMatchRecord>> {
  TeamMatchesNotifier(this.q);
  final TeamMatchQuery q;
  @override
  FutureOr<List<TeamMatchRecord>> build() => ref
      .watch(matchUpdatesServiceProvider)
      .teams(status: q.status, keyword: q.keyword);
}

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class TeamMatchNotifier extends AsyncNotifier<TeamMatchRecord> {
  TeamMatchNotifier(this.q);
  final ({String staffId, int code}) q;
  @override
  FutureOr<TeamMatchRecord> build() =>
      ref.watch(matchUpdatesServiceProvider).team(q.code);
}

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class CancelledMatchesNotifier extends AsyncNotifier<List<CancelledMatch>> {
  CancelledMatchesNotifier(this.q);
  final CancelQuery q;
  @override
  FutureOr<List<CancelledMatch>> build() => ref
      .watch(matchUpdatesServiceProvider)
      .cancellations(managerId: q.managerId, reason: q.reason);
}

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class CancelledDetailNotifier extends AsyncNotifier<AdminRow> {
  CancelledDetailNotifier(this.q);
  final ({String staffId, CancelledMatch match}) q;
  @override
  FutureOr<AdminRow> build() =>
      ref.watch(matchUpdatesServiceProvider).cancellationDetail(q.match);
}

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
