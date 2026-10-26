// ###  2026.10.23 문의 관리 모델 클래스 구성
//
// [이 파일의 역할]
// 본사 관리자 앱의 "문의 내역" 화면에서 쓰는 모델
//   AdminInquiry : 회원이 작성한 문의 원글 1건 + 추가 문의(follow_ups)   (GET /inquiry/list, /inquiry/detail/{i_seq})
//   FollowUp     : 원글에 이어 회원이 남긴 추가 문의 1건
// 답변은 문의 행마다 따로 저장되므로, 원글과 추가 문의 각각에 답변을 등록할 수 있음 (POST /inquiry/answer)

// 추가 문의 1건
class FollowUp {
  final int i_seq; // 문의번호
  final String post; // 추가 문의 내용
  final DateTime? i_date; // 작성일
  final bool answered; // 답변 완료 여부
  final String? inquiry_detail; // 답변 내용
  final DateTime? i_answer_date; // 답변일
  final String? h_id; // 답변한 본사 직원

  FollowUp({
    required this.i_seq,
    required this.post,
    this.i_date,
    required this.answered,
    this.inquiry_detail,
    this.i_answer_date,
    this.h_id,
  });

  factory FollowUp.fromJson(Map<String, dynamic> json) {
    return FollowUp(
      i_seq: json['i_seq'] ?? 0,
      post: json['post'] ?? '',
      i_date: DateTime.tryParse('${json['i_date']}'),
      // i_state는 문자열 '0'(답변 대기) / '1'(답변 완료)
      answered: '${json['i_state']}' == '1',
      inquiry_detail: json['inquiry_detail'],
      i_answer_date: DateTime.tryParse('${json['i_answer_date']}'),
      h_id: json['h_id'],
    );
  }
}

// 문의 원글 1건
class AdminInquiry {
  final int i_seq; // 문의번호
  final String c_id_seq; // 문의한 회원 아이디
  final String? c_name; // 문의한 회원 이름
  final String title; // 제목 (문의 유형 이름. 유형이 없으면 내용 앞부분)
  final String post; // 문의 내용
  final DateTime? i_date; // 작성일
  final bool answered; // 답변 완료 여부
  final String? inquiry_detail; // 답변 내용
  final DateTime? i_answer_date; // 답변일
  final String? h_id; // 답변한 본사 직원 아이디
  final String? h_name; // 답변한 본사 직원 이름
  final List<FollowUp> follow_ups; // 추가 문의 목록

  AdminInquiry({
    required this.i_seq,
    required this.c_id_seq,
    this.c_name,
    required this.title,
    required this.post,
    this.i_date,
    required this.answered,
    this.inquiry_detail,
    this.i_answer_date,
    this.h_id,
    this.h_name,
    required this.follow_ups,
  });

  factory AdminInquiry.fromJson(Map<String, dynamic> json) {
    final List follow = json['follow_ups'] ?? [];
    return AdminInquiry(
      i_seq: json['i_seq'] ?? 0,
      c_id_seq: json['c_id_seq'] ?? '',
      c_name: json['c_name'],
      title: json['title'] ?? '',
      post: json['post'] ?? '',
      i_date: DateTime.tryParse('${json['i_date']}'),
      answered: '${json['i_state']}' == '1',
      inquiry_detail: json['inquiry_detail'],
      i_answer_date: DateTime.tryParse('${json['i_answer_date']}'),
      h_id: json['h_id'],
      h_name: json['h_name'],
      follow_ups: follow.map((e) => FollowUp.fromJson(e)).toList(),
    );
  }

  // 원글 또는 추가 문의 중 답변이 안 된 것이 있는지 (목록의 "처리 필요" 표시용)
  bool get hasPending => !answered || follow_ups.any((f) => !f.answered);
}
