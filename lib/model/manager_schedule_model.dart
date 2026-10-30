// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 배정 시간대 응답을 보존하고 빈 시간대와 팀 경기 정보를 구분합니다.
import 'headquarters_model.dart';
import 'match_updates_model.dart';

class ManagerSchedule {
  ManagerSchedule.fromJson(AdminRow row)
    : managerId = adminText(row['m_id']),
      date = adminText(row['r_date']),
      grounds = adminRows(row['grounds']).map(ScheduleGround.fromJson).toList();
  final String managerId, date;
  final List<ScheduleGround> grounds;
}

class ScheduleGround {
  ScheduleGround.fromJson(AdminRow row)
    : code = adminText(row['g_code']),
      name = adminText(row['g_name']),
      capacity = adminInt(row['g_num']),
      slots = adminRows(row['slots']).map(ScheduleSlot.fromJson).toList();
  final String code, name;
  final int? capacity;
  final List<ScheduleSlot> slots;
}

class ScheduleSlot {
  ScheduleSlot.fromJson(AdminRow row)
    : date = row['r_date']?.toString(),
      start = adminText(row['rs_time']),
      end = adminText(row['re_time']),
      type = adminText(row['slot_type']),
      label = adminText(row['slot_type_name']),
      count = adminInt(adminDocument(row['pickup'])['reservation_count']),
      renter = adminText(adminDocument(row['rental'])['c_name']),
      teamCode = adminInt(adminDocument(row['team_match'])['team_code']),
      home = adminText(adminDocument(row['team_match'])['home_t_name']),
      away = adminText(adminDocument(row['team_match'])['away_t_name']);
  final String start, end, type, label, renter, home, away;
  final String? date;
  final int? count, teamCode;
  String get title => type == 'team_match' ? '$home vs $away' : label;
}
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 실력매칭 운영 기록과 팀 경기 결과를 하나의 날짜별 목록으로 합칩니다.
class ManagerMatchEntry {
  ManagerMatchEntry({
    required this.ground,
    required this.slot,
    this.operation,
    this.team,
    this.sport,
  });
  final ScheduleGround ground;
  final ScheduleSlot slot;
  final AdminRow? operation;
  final TeamMatchRecord? team;
  final String? sport;
}

class ManagerMatchDay {
  ManagerMatchDay(this.grounds, this.entries);
  final List<ScheduleGround> grounds;
  final List<ManagerMatchEntry> entries;
}
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
