// ###  2026.10.23 회원·매니저 관리 모델 클래스 구성
//
// [이 파일의 역할]
// 본사 관리자 앱의 "회원 관리" 화면에서 서버(FastAPI)와 주고받는 데이터를 Dart 객체로 바꿔주는 모델 모음
//   MemberSummary / MemberDetail   : 회원 목록 1건 / 상세   (GET /management/members, /management/members/{c_id_seq})
//   ManagerSummary / ManagerDetail : 매니저 목록 1건 / 상세 (GET /management/managers, /management/managers/{m_id})
//   SanctionItem / ReportItem      : 회원 상세의 제재 이력 / 받은 신고
//
// 날짜 값은 서버가 문자열로 주므로 DateTime.tryParse로 변환 (실패하면 null → 화면에서 "-" 표시)

import 'sport_model.dart';

// 선호 종목 값(1~4 또는 종목 이름)을 화면용 종목 이름으로 변환. 값이 없으면 "-"
String preferStockName(String? value) {
  if (value == null || value.isEmpty) return '-';
  return Sport.fromValue(value)?.name ?? value;
}

// 회원 목록의 1건
class MemberSummary {
  final String c_id_seq; // 회원 아이디 (예: minjun_01)
  final String c_name; // 이름
  final String? c_prefer_stock; // 선호 종목
  final DateTime? c_signupdate; // 가입일
  final DateTime? c_deletdate; // 탈퇴일 (null이면 이용 중)
  final int match_count; // 참여 경기 수
  final int warning_count; // 유효 경고 수 (제재 - 처리된 이의신청)

  MemberSummary({
    required this.c_id_seq,
    required this.c_name,
    this.c_prefer_stock,
    this.c_signupdate,
    this.c_deletdate,
    required this.match_count,
    required this.warning_count,
  });

  factory MemberSummary.fromJson(Map<String, dynamic> json) {
    return MemberSummary(
      c_id_seq: json['c_id_seq'] ?? '',
      c_name: json['c_name'] ?? '',
      c_prefer_stock: json['c_prefer_stock']?.toString(),
      c_signupdate: DateTime.tryParse('${json['c_signupdate']}'),
      c_deletdate: DateTime.tryParse('${json['c_deletdate']}'),
      match_count: json['match_count'] ?? 0,
      warning_count: json['warning_count'] ?? 0,
    );
  }

  bool get isWithdrawn => c_deletdate != null;
}

// 회원 목록 응답 (전체 인원 + 목록)
class MemberList {
  final int total;
  final List<MemberSummary> results;
  MemberList({required this.total, required this.results});

  factory MemberList.fromJson(Map<String, dynamic> json) {
    final List raw = json['results'] ?? [];
    return MemberList(
      total: json['total'] ?? raw.length,
      results: raw.map((e) => MemberSummary.fromJson(e)).toList(),
    );
  }
}

// 제재 이력 1건 (status : 유효 / 철회)
class SanctionItem {
  final DateTime? date; // 부과일
  final String? detail; // 사유
  final String status; // 상태

  SanctionItem({this.date, this.detail, required this.status});

  // 회원 제재(cs_*)와 매니저 제재(s_*)는 키 이름만 다르고 구조가 같아서 한 클래스로 처리
  factory SanctionItem.fromJson(Map<String, dynamic> json) {
    return SanctionItem(
      date: DateTime.tryParse('${json['cs_date'] ?? json['s_date']}'),
      detail: json['cs_detail'] ?? json['s_detail'],
      // 매니저 제재에는 상태가 없으므로 "유효"로 취급
      status: json['status'] ?? '유효',
    );
  }
}

// 받은 신고 1건 (state : 처리완료 / 미처리)
class ReportItem {
  final int r_seq; // 신고 번호
  final DateTime? r_date; // 신고일
  final String? r_reason; // 신고 사유
  final String state; // 처리 상태

  ReportItem({required this.r_seq, this.r_date, this.r_reason, required this.state});

  factory ReportItem.fromJson(Map<String, dynamic> json) {
    return ReportItem(
      r_seq: json['r_seq'] ?? 0,
      r_date: DateTime.tryParse('${json['r_date']}'),
      r_reason: json['r_reason'],
      state: json['state'] ?? '',
    );
  }
}

// 회원 상세
class MemberDetail {
  final MemberSummary summary; // 목록과 같은 기본 값
  final String? c_phone; // 전화번호
  final String? c_gender; // 성별
  final String? c_address; // 주소
  final String? c_team; // 소속팀
  final String? c_position; // 선호 포지션
  final int received_report_count; // 받은 신고 수
  final int sent_report_count; // 한 신고 수
  final List<ReportItem> received_reports; // 받은 신고 목록
  final List<SanctionItem> sanctions; // 제재 이력

  MemberDetail({
    required this.summary,
    this.c_phone,
    this.c_gender,
    this.c_address,
    this.c_team,
    this.c_position,
    required this.received_report_count,
    required this.sent_report_count,
    required this.received_reports,
    required this.sanctions,
  });

  factory MemberDetail.fromJson(Map<String, dynamic> json) {
    final List reports = json['received_reports'] ?? [];
    final List sanctions = json['sanctions'] ?? [];
    return MemberDetail(
      summary: MemberSummary.fromJson(json),
      c_phone: json['c_phone'],
      c_gender: json['c_gender'],
      c_address: json['c_address'],
      c_team: json['c_team'],
      c_position: json['c_position'],
      received_report_count: json['received_report_count'] ?? 0,
      sent_report_count: json['sent_report_count'] ?? 0,
      received_reports: reports.map((e) => ReportItem.fromJson(e)).toList(),
      sanctions: sanctions.map((e) => SanctionItem.fromJson(e)).toList(),
    );
  }
}

// 매니저 목록의 1건
class ManagerSummary {
  final String m_id; // 매니저 아이디
  final String m_name; // 이름
  final String? m_phone; // 전화번호
  final String? m_gender; // 성별
  final String? m_workplace; // 근무지
  final int sanction_count; // 제재 건수

  ManagerSummary({
    required this.m_id,
    required this.m_name,
    this.m_phone,
    this.m_gender,
    this.m_workplace,
    required this.sanction_count,
  });

  factory ManagerSummary.fromJson(Map<String, dynamic> json) {
    return ManagerSummary(
      m_id: json['m_id'] ?? '',
      m_name: json['m_name'] ?? '',
      m_phone: json['m_phone'],
      m_gender: json['m_gender'],
      m_workplace: json['m_workplace'],
      sanction_count: json['sanction_count'] ?? 0,
    );
  }
}

// 매니저 목록 응답
class ManagerList {
  final int total;
  final List<ManagerSummary> results;
  ManagerList({required this.total, required this.results});

  factory ManagerList.fromJson(Map<String, dynamic> json) {
    final List raw = json['results'] ?? [];
    return ManagerList(
      total: json['total'] ?? raw.length,
      results: raw.map((e) => ManagerSummary.fromJson(e)).toList(),
    );
  }
}

// 매니저 배정(담당 구장) 1건
class AssignItem {
  final String g_name; // 구장명
  final String? a_day; // 근무 요일 (예: 월,수,금)
  final String? a_time; // 근무 시간대 (예: 18:00~22:00)

  AssignItem({required this.g_name, this.a_day, this.a_time});

  factory AssignItem.fromJson(Map<String, dynamic> json) {
    return AssignItem(
      g_name: json['g_name'] ?? '',
      a_day: json['a_day'],
      a_time: json['a_time'],
    );
  }
}

// 매니저 평가 1건
class EvaluateItem {
  final DateTime? e_date; // 평가일
  final String? e_detail; // 평가 내용

  EvaluateItem({this.e_date, this.e_detail});

  factory EvaluateItem.fromJson(Map<String, dynamic> json) {
    return EvaluateItem(
      e_date: DateTime.tryParse('${json['e_date']}'),
      e_detail: json['e_detail'],
    );
  }
}

// 매니저 상세
class ManagerDetail {
  final ManagerSummary summary;
  final List<AssignItem> assigns; // 배정 구장
  final List<EvaluateItem> evaluates; // 평가
  final List<SanctionItem> sanctions; // 제재
  final List<DateTime> hires; // 채용일

  ManagerDetail({
    required this.summary,
    required this.assigns,
    required this.evaluates,
    required this.sanctions,
    required this.hires,
  });

  factory ManagerDetail.fromJson(Map<String, dynamic> json) {
    final List assigns = json['assigns'] ?? [];
    final List evaluates = json['evaluates'] ?? [];
    final List sanctions = json['sanctions'] ?? [];
    final List hires = json['hires'] ?? [];
    return ManagerDetail(
      summary: ManagerSummary.fromJson(json),
      assigns: assigns.map((e) => AssignItem.fromJson(e)).toList(),
      evaluates: evaluates.map((e) => EvaluateItem.fromJson(e)).toList(),
      sanctions: sanctions.map((e) => SanctionItem.fromJson(e)).toList(),
      hires: hires
          .map((e) => DateTime.tryParse('${e['h_date']}'))
          .whereType<DateTime>()
          .toList(),
    );
  }
}
