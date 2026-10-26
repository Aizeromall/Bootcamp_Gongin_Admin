// [이 파일의 역할]
// 화면에 보여줄 날짜·금액 문자열 변환 함수 모음 (intl 패키지 없이 직접 구현)

// 요일 이름 (DateTime.weekday : 월=1 ... 일=7 이라서 인덱스 0은 월요일)
const List<String> _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

// 서버로 보내는 날짜 형식 : 2026-10-25
String formatApiDate(DateTime d) {
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

// 화면에 보여주는 날짜 형식 : 2026.10.25 (토)
String formatKoreanDate(DateTime d) {
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}.$mm.$dd (${weekdayName(d)})';
}

// 요일 한 글자 : 월, 화, ... 일
String weekdayName(DateTime d) => _weekdayNames[d.weekday - 1];

// 날짜 + 시간 형식 : 2026.10.25 14:30
String formatDateTime(DateTime d) {
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}.$mm.$dd $hh:$mi';
}

// 금액 형식 : 10000 -> 10,000원
String formatWon(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  // 뒤에서부터 3자리마다 쉼표를 넣기 위해 앞에서 남는 자릿수를 먼저 계산
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}$buffer원';
}

// 서버가 준 날짜 문자열(2026-10-25 또는 2026-10-25T10:00:00)을 DateTime으로 변환
// 파싱에 실패하면 null (화면에서 "-" 로 표시)
DateTime? parseServerDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
