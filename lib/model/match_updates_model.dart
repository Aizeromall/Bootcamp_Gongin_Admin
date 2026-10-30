// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 팀 매칭·취소 API의 실제 nullable 응답과 문자열 취소 사유를 변환합니다.
import 'headquarters_model.dart';

class MatchedTeam {
  MatchedTeam.fromJson(AdminRow row)
    : name = adminText(row['t_name']),
      captain = adminText(row['captain_name']),
      phone = adminText(row['captain_phone']),
      grade = adminText(row['grade']),
      members = adminInt(row['member_count']),
      wins = adminInt(row['wins']),
      draws = adminInt(row['draws']),
      losses = adminInt(row['losses']),
      winRate = adminInt(row['win_rate']);
  final String name, captain, phone, grade;
  final int? members, wins, draws, losses, winRate;
}

class TeamMatchRecord {
  TeamMatchRecord.fromJson(AdminRow row)
    : code =
          adminInt(row['team_code']) ??
          (throw const FormatException('Invalid team code')),
      sport = row['e_code']?.toString(),
      status = adminText(row['status']),
      statusName = adminText(row['status_name']),
      start = adminText(row['team_start']),
      end = adminText(row['team_end']),
      ground = adminText(row['g_name']),
      manager = adminText(row['m_name']),
      capacity = adminInt(row['team_num']),
      home = MatchedTeam.fromJson(adminDocument(row['home_team'])),
      away = MatchedTeam.fromJson(adminDocument(row['away_team'])),
      homeScore = adminInt(adminDocument(row['result'])['home_score']),
      awayScore = adminInt(adminDocument(row['result'])['away_score']),
      resultDate = adminText(adminDocument(row['result'])['t_r_r_date']);
  final int code;
  final String? sport;
  final String status, statusName, start, end, ground, manager, resultDate;
  final int? capacity, homeScore, awayScore;
  final MatchedTeam home, away;
  String get score => homeScore == null || awayScore == null
      ? '점수 미기록'
      : '$homeScore : $awayScore';
}

const cancellationReasons = {1: '정원 미달', 2: '우천·기상악화', 3: '노쇼 및 환불'};

class CancelledMatch {
  CancelledMatch.fromJson(AdminRow row)
    : groundCode = adminText(row['g_code']),
      ground = adminText(row['g_name']),
      date = adminText(row['r_date']),
      start = adminText(row['rs_time']),
      end = adminText(row['re_time']),
      cancelDate = adminText(row['r_cancel_date']),
      reason = adminInt(row['r_c_category']),
      count = adminInt(row['canceled_count']),
      capacity = adminInt(row['g_num']);
  final String groundCode, ground, date, start, end, cancelDate;
  final int? reason, count, capacity;
  String get reasonName => cancellationReasons[reason] ?? '사유 미확인';
  String get identity => '$groundCode|$date|$start|$reason';
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
