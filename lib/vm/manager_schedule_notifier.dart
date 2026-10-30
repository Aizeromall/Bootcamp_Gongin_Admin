// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 계정·조회 날짜·시간대별로 캐시를 분리하고 일정에 있는 경기만 상세 조회합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/login_role.dart';
import '../model/headquarters_model.dart';
import '../model/manager_schedule_model.dart';
import '../model/match_updates_model.dart';
import '../service/manager_schedule_service.dart';
import '../service/operations_api.dart';
import 'login_notifier.dart';
import 'match_updates_notifier.dart';

// 실력매칭·팀매칭 표시 조건은 담당자별로 분리합니다.
enum ManagerMatchKind { all, pickup, team }

final managerMatchKindProvider = NotifierProvider.autoDispose
    .family<ManagerMatchKindNotifier, ManagerMatchKind, String>(
      ManagerMatchKindNotifier.new,
    );

class ManagerMatchKindNotifier extends Notifier<ManagerMatchKind> {
  ManagerMatchKindNotifier(this.managerId);
  final String managerId;
  @override
  ManagerMatchKind build() {
    ref.watch(loginProvider);
    return ManagerMatchKind.all;
  }

  void select(ManagerMatchKind kind) => state = kind;
}

typedef ScheduleQuery = ({String managerId, String date});
typedef ScheduleMatchQuery = ({
  ScheduleQuery schedule,
  String groundCode,
  String start,
  int code,
});
final managerScheduleServiceProvider = Provider(
  (ref) => ManagerScheduleService(ref.watch(operationsApiProvider)),
);
final managerScheduleProvider = FutureProvider.autoDispose
    .family<ManagerSchedule, ScheduleQuery>((ref, query) {
      final session = ref.watch(loginProvider).asData?.value;
      if (session?.role != LoginRole.manager ||
          session?.userId != query.managerId) {
        throw const OperationsApiException(403, '로그인한 매니저의 일정만 조회할 수 있습니다.');
      }
      return ref
          .watch(managerScheduleServiceProvider)
          .load(query.managerId, query.date);
    }, retry: (_, _) => null);
final scheduledTeamMatchProvider = FutureProvider.autoDispose
    .family<TeamMatchRecord, ScheduleMatchQuery>((ref, query) async {
      final service = ref.watch(matchUpdatesServiceProvider);
      final schedule = await ref.watch(
        managerScheduleProvider(query.schedule).future,
      );
      final allowed = schedule.grounds.any(
        (ground) =>
            ground.code == query.groundCode &&
            ground.slots.any(
              (slot) =>
                  slot.start == query.start &&
                  slot.type == 'team_match' &&
                  slot.teamCode == query.code,
            ),
      );
      if (!allowed) {
        throw const OperationsApiException(403, '담당 일정에 포함된 팀 경기가 아닙니다.');
      }
      if (!ref.mounted) throw StateError('Schedule request disposed');
      return service.team(query.code);
    }, retry: (_, _) => null);
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 완료는 서버 상태로 판단합니다. 지난 날짜라는 이유로 결과 대기를 완료 처리하지 않습니다.
// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 한국 날짜를 기준으로 내 매치의 과거 날짜 조회를 제한합니다.
final managerTodayProvider = Provider<DateTime>((ref) {
  final now = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime(now.year, now.month, now.day);
});

typedef ManagerMatchDayQuery = ({String managerId, String date, bool history});
final managerMatchDayProvider = FutureProvider.autoDispose
    .family<ManagerMatchDay, ManagerMatchDayQuery>((ref, query) async {
      final session = ref.watch(loginProvider).asData?.value;
      if (session?.role != LoginRole.manager ||
          session?.userId != query.managerId) {
        throw const OperationsApiException(403, '로그인한 매니저의 일정만 조회할 수 있습니다.');
      }
      final today = ref.watch(managerTodayProvider);
      final requestedDay = DateTime.tryParse(query.date);
      if (!query.history &&
          requestedDay != null &&
          requestedDay.isBefore(today)) {
        return ManagerMatchDay([], []);
      }
      final scheduleFuture = ref.watch(
        managerScheduleProvider((managerId: query.managerId, date: query.date))
            .future,
      );
      final operationsFuture = ref.watch(
        operationsDataProvider('/match/operations').future,
      );
      final service = ref.watch(matchUpdatesServiceProvider);
      final schedule = await scheduleFuture;
      final operations = await operationsFuture;
      final entries = <ManagerMatchEntry>[];
      final grounds = [...schedule.grounds];
      for (final raw in (operations['results'] as List? ?? [])) {
        final row = Map<String, dynamic>.from(raw as Map);
        final status = row['status'];
        final eligible = query.history
            ? status == 'completed'
            : status == 'attendance' || status == 'teams';
        if (!eligible || row['r_date'] != query.date) continue;
        // 운영 API의 match_code는 g_code_YYYYMMDD_HHMMSS 형식입니다.
        final code =
            row['g_code']?.toString() ??
            '${row['match_code'] ?? ''}'.split('_').first;
        final overlapsTeam = schedule.grounds.any(
          (ground) =>
              ground.code == code &&
              ground.slots.any(
                (slot) =>
                    slot.type == 'team_match' &&
                    slot.start == '${row['rs_time']}'.substring(0, 5),
              ),
        );
        if (overlapsTeam) continue;
        final ground = ScheduleGround.fromJson({
          'g_code': code,
          'g_name': row['g_name'],
          'slots': [],
        });
        if (!grounds.any((value) => value.code == ground.code)) {
          grounds.add(ground);
        }
        entries.add(
          ManagerMatchEntry(
            ground: ground,
            slot: ScheduleSlot.fromJson({
              'rs_time': row['rs_time'],
              're_time': row['re_time'],
              'slot_type': 'pickup',
              'slot_type_name': '실력매칭',
              'pickup': {'reservation_count': row['count']},
            }),
            operation: row,
            sport: row['e_code']?.toString(),
          ),
        );
      }
      final teamSlots = [
        for (final ground in schedule.grounds)
          for (final slot in ground.slots)
            if (slot.type == 'team_match' && slot.teamCode != null)
              (ground: ground, slot: slot),
      ];
      final teams = await Future.wait(
        teamSlots.map((entry) => service.team(entry.slot.teamCode!)),
      );
      for (var index = 0; index < teamSlots.length; index++) {
        final team = teams[index];
        if (query.history
            ? team.status != 'finished'
            : team.status != 'scheduled') {
          continue;
        }
        entries.add(
          ManagerMatchEntry(
            ground: teamSlots[index].ground,
            slot: teamSlots[index].slot,
            team: team,
            sport: team.sport,
          ),
        );
      }
      if (!ref.mounted) throw StateError('Match list disposed');
      entries.sort(
        (a, b) => query.history
            ? b.slot.start.compareTo(a.slot.start)
            : a.slot.start.compareTo(b.slot.start),
      );
      return ManagerMatchDay(grounds, entries);
    }, retry: (_, _) => null);
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 내 매치의 기본 목록은 오늘부터의 모든 예정 경기를 표시합니다.
final managerUpcomingProvider = FutureProvider.autoDispose
    .family<ManagerMatchDay, String>((ref, managerId) async {
      final session = ref.watch(loginProvider).asData?.value;
      if (session?.userId != managerId || session?.role != LoginRole.manager) {
        throw const OperationsApiException(403, '로그인한 매니저의 일정만 조회할 수 있습니다.');
      }
      final data = await ref
          .watch(operationsApiProvider)
          .request('/match/manager/upcoming');
      final entries = <ManagerMatchEntry>[];
      final grounds = <String, ScheduleGround>{};
      final teamRows = adminRows(data['teams']);
      for (final row in adminRows(data['operations'])) {
        final code =
            row['g_code']?.toString() ??
            '${row['match_code'] ?? ''}'.split('_').first;
        final teamOverlap = teamRows.any(
          (team) =>
              '${team['g_code']}' == code &&
              '${team['team_start']}'
                  .replaceFirst('T', ' ')
                  .startsWith('${row['r_date']} ${row['rs_time']}'),
        );
        if (teamOverlap) continue;
        final ground = ScheduleGround.fromJson({
          'g_code': code,
          'g_name': row['g_name'],
          'g_num': row['g_num'],
        });
        grounds[ground.code] = ground;
        entries.add(
          ManagerMatchEntry(
            ground: ground,
            slot: ScheduleSlot.fromJson({
              'r_date': row['r_date'],
              'rs_time': row['rs_time'],
              're_time': row['re_time'],
              'slot_type': 'pickup',
              'slot_type_name': '실력매칭',
              'pickup': {'reservation_count': row['count']},
            }),
            operation: row,
            sport: row['e_code']?.toString(),
          ),
        );
      }
      for (final row in teamRows) {
        final team = TeamMatchRecord.fromJson(row);
        final ground = ScheduleGround.fromJson({
          'g_code': row['g_code'],
          'g_name': row['g_name'],
          'g_num': row['team_num'],
        });
        grounds[ground.code] = ground;
        final start = team.start.replaceFirst('T', ' ');
        final end = team.end.replaceFirst('T', ' ');
        entries.add(
          ManagerMatchEntry(
            ground: ground,
            slot: ScheduleSlot.fromJson({
              'r_date': start.length >= 10 ? start.substring(0, 10) : null,
              'rs_time': start.length >= 16 ? start.substring(11, 16) : null,
              're_time': end.length >= 16 ? end.substring(11, 16) : null,
              'slot_type': 'team_match',
              'slot_type_name': '팀매칭',
              'team_match': {
                'team_code': team.code,
                'home_t_name': team.home.name,
                'away_t_name': team.away.name,
              },
            }),
            team: team,
            sport: team.sport,
          ),
        );
      }
      entries.sort(
        (a, b) => '${a.slot.date} ${a.slot.start}'.compareTo(
          '${b.slot.date} ${b.slot.start}',
        ),
      );
      return ManagerMatchDay(grounds.values.toList(), entries);
    }, retry: (_, _) => null);
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
