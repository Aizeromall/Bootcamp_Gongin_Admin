// ###  2026.10.23 매니저 경기 관리 모델 클래스 구성
//
// [이 파일의 역할]
// 매치 매니저 앱의 "내 매치" 화면에서 쓰는 모델과 경기 기록 입력용 상수
//   MatchReservation : 매니저에게 배정된 구장의 예약 1건 (예약한 회원 정보 포함)   (GET /match/list/{m_id})
//   MatchListData    : 매니저 이름 + 예약 목록
//   kMatchSports     : 경기 결과 등록 시 선택하는 종목 코드(e_code)와 스탯 항목 이름
//
// 경기 결과 등록 규칙 (POST /match/score/{m_id}/{r_seq})
//   c_r_r_statcode : 스탯 4개를 "-"로 이어서 전송 (예: 골/어시/태클/선방 → "1-1-1-1")
//   c_r_r_score    : 전체 스코어 문자열 (예: "3:2")

// 매니저가 담당하는 구장의 예약 1건
class MatchReservation {
  final int r_seq; // 예약번호
  final DateTime r_date; // 경기 날짜
  final String rs_time; // 시작 시간 (HH:mm)
  final String re_time; // 종료 시간 (HH:mm)
  final String g_code; // 구장코드
  final String g_name; // 구장명
  final int g_num; // 수용 인원
  final String c_id_seq; // 예약한 회원 아이디
  final String c_name; // 회원 이름
  final int? c_rating; // 회원 실력 점수
  final String? c_position; // 선호 포지션
  final bool r_check; // 매치 성사(정원 마감) 여부

  MatchReservation({
    required this.r_seq,
    required this.r_date,
    required this.rs_time,
    required this.re_time,
    required this.g_code,
    required this.g_name,
    required this.g_num,
    required this.c_id_seq,
    required this.c_name,
    this.c_rating,
    this.c_position,
    required this.r_check,
  });

  factory MatchReservation.fromJson(Map<String, dynamic> json) {
    // 서버 시간은 HH:MM:SS 형식이라 앞 5글자(HH:mm)만 사용
    String hhmm(dynamic v) => '$v'.length >= 5 ? '$v'.substring(0, 5) : '$v';
    return MatchReservation(
      r_seq: json['r_seq'] ?? 0,
      r_date: DateTime.tryParse('${json['r_date']}') ?? DateTime.now(),
      rs_time: hhmm(json['rs_time']),
      re_time: hhmm(json['re_time']),
      g_code: '${json['g_code']}',
      g_name: json['g_name'] ?? '',
      g_num: json['g_num'] ?? 0,
      c_id_seq: json['c_id_seq'] ?? '',
      c_name: json['c_name'] ?? '',
      c_rating: json['c_rating'],
      c_position: json['c_position'],
      r_check: json['r_check'] == true || json['r_check'] == 1,
    );
  }

  // 같은 경기(구장 + 날짜 + 시작 시간)로 묶기 위한 키
  String get matchKey => '$g_code|${r_date.year}-${r_date.month}-${r_date.day}|$rs_time';

  // 회원 아이디 끝 번호(_01~_04)로 종목 코드(e_code) 추정 : 01 축구 / 02 농구 / 03 야구 / 04 배구
  String get sportCode {
    final suffix = c_id_seq.split('_').last;
    switch (suffix) {
      case '02':
        return 'BASKETBALL';
      case '03':
        return 'BASEBALL';
      case '04':
        return 'VOLLEYBALL';
      default:
        return 'SOCCER';
    }
  }
}

// 매니저 이름 + 담당 구장 예약 목록
class MatchListData {
  final String m_name;
  final List<MatchReservation> reservations;

  MatchListData({required this.m_name, required this.reservations});

  factory MatchListData.fromJson(Map<String, dynamic> json) {
    final List raw = json['reservations'] ?? [];
    return MatchListData(
      m_name: json['m_name'] ?? '',
      reservations: raw.map((e) => MatchReservation.fromJson(e)).toList(),
    );
  }
}

// 경기 결과 등록 시 선택하는 종목 : 서버에 보내는 코드 + 화면 이름 + 스탯 항목 4개
class MatchSportOption {
  final String e_code; // 서버에 보내는 종목 코드
  final String name; // 화면 표시 이름
  final List<String> statLabels; // 스탯 항목 이름 4개 (입력 순서 = statcode의 "-" 순서)

  const MatchSportOption(this.e_code, this.name, this.statLabels);
}

const List<MatchSportOption> kMatchSports = [
  MatchSportOption('SOCCER', '축구', ['골', '어시', '태클', '선방']),
  MatchSportOption('BASKETBALL', '농구', ['득점', '리바운드', '어시스트', '스틸']),
  MatchSportOption('BASEBALL', '야구', ['안타', '타점', '득점', '삼진']),
  MatchSportOption('VOLLEYBALL', '배구', ['득점', '블로킹', '서브에이스', '디그']),
];
