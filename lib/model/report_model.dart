// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 신고 API의 nullable 필드와 숫자·문자열 응답을 화면 모델로 변환합니다.
int? reportInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
String? reportText(Object? value) =>
    value == null || '$value'.trim().isEmpty ? null : '$value';

class ReportRecord {
  ReportRecord.fromJson(Map<String, dynamic> json)
    : id =
          reportInt(json['r_seq']) ??
          (throw const FormatException('Invalid report ID')),
      status = reportText(json['state_text']) ?? '상태 확인 필요',
      category = reportText(json['r_option_name']) ?? '기타',
      reporter =
          reportText(json['reporter_name']) ??
          reportText(json['c_id_seq']) ??
          '정보 없음',
      target =
          reportText(json['target_name']) ??
          reportText(json['r_person']) ??
          '정보 없음',
      reportedAt = reportText(json['r_date']),
      description = reportText(json['r_reason']),
      sport = reportText(json['sport']),
      sportName = reportText(json['sport_name']) ?? '기타',
      ground = reportText(json['g_name']),
      matchDate = reportText(json['match_date']),
      matchTime = reportText(json['match_time']),
      matchCode = reportText(json['c_r_r_code']),
      manager = reportText(json['m_name']),
      reviewer = reportText(json['h_name']),
      reviewerId = reportText(json['h_id']),
      canStartReview = json['can_start_review'] == true,
      evidence = (json['r_evidence'] as List? ?? [])
          .map((v) => '$v')
          .where((v) => v.trim().isNotEmpty)
          .toList(),
      history = json['target_history'] is Map
          ? Map<String, dynamic>.from(json['target_history'])
          : null;
  final int id;
  final String status, category, reporter, target, sportName;
  final String? reportedAt,
      description,
      sport,
      ground,
      matchDate,
      matchTime,
      matchCode,
      manager,
      reviewer,
      reviewerId;
  final bool canStartReview;
  // 수정 일 : 2026-11-03 / 작업자 : 김병재
  // 제재 등록은 심의중이고 로그인한 직원이 심의를 시작한 신고에서만 가능합니다(서버도 같은 조건으로 검증).
  bool canSanction(String staffId) => status == '심의중' && reviewerId == staffId;
  final List<String> evidence;
  final Map<String, dynamic>? history;
  int? get warnings => reportInt(history?['warning_count']);
  int? get receivedReports => reportInt(history?['received_report_count']);
  String? get accountState => reportText(history?['account_state']);
}

class ReportCollection {
  ReportCollection.fromJson(Map<String, dynamic> json)
    : pending = reportInt(json['pending_count']),
      total = reportInt(json['total']),
      statusCounts = Map<String, dynamic>.from(
        json['status_counts'] as Map? ?? {},
      ).map((key, value) => MapEntry(key, reportInt(value))),
      sports = (json['sport_counts'] as List? ?? [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList(),
      reports = (json['results'] as List? ?? [])
          .map(
            (v) => ReportRecord.fromJson(Map<String, dynamic>.from(v as Map)),
          )
          .toList();
  final int? pending, total;
  final Map<String, int?> statusCounts;
  final List<Map<String, dynamic>> sports;
  final List<ReportRecord> reports;
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
