// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 기존 본사 API의 목록·nullable 값·문서 JSON을 공통으로 변환합니다.
import 'dart:convert';

typedef AdminRow = Map<String, dynamic>;
int? adminInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
String adminText(Object? value) =>
    value == null || '$value'.trim().isEmpty ? '—' : '$value';
List<AdminRow> adminRows(Object? value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];
AdminRow adminDocument(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      /* 기존 일반 문자열 문서는 원문으로 표시합니다. */
    }
  }
  return {};
}

class AdminPayload {
  const AdminPayload(this.data);
  final AdminRow data;
  List<AdminRow> get rows => adminRows(data['results']);
  int? number(String key) => adminInt(data[key]);
}

String? approvalKind(Object? content) {
  final kind = adminDocument(content)['유형'];
  if (['휴가', '신규 계약', '재계약', '해지'].contains(kind)) return '$kind';
  final title = '$content'.split(r'\n').first.split('\n').first;
  if (title.contains('휴가')) return '휴가';
  if (title.contains('해지') || title.contains('취소')) return '해지';
  if (title.contains('재계약') || title.contains('갱신') || title.contains('연장')) {
    return '재계약';
  }
  if (title.contains('계약')) return '신규 계약';
  return null;
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
