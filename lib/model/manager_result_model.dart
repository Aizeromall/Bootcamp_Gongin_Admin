// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 실제 결과·현재 등급·경기별 변동을 구분합니다. 없는 점수는 0으로 만들지 않습니다.
import 'headquarters_model.dart';

const managerSports = <String, String>{
  'all': '전 종목',
  'SOCCER': '⚽ 축구',
  'VOLLEYBALL': '🏐 배구',
  'BASKETBALL': '🏀 농구',
  'BASEBALL': '⚾ 야구',
};
String? normalizeManagerSport(Object? value) {
  final text = value?.toString().trim();
  if (managerSports.containsKey(text) && text != 'all') return text;
  return const {
    '1': 'SOCCER',
    '2': 'BASKETBALL',
    '3': 'BASEBALL',
    '4': 'VOLLEYBALL',
    '축구': 'SOCCER',
    '농구': 'BASKETBALL',
    '야구': 'BASEBALL',
    '배구': 'VOLLEYBALL',
  }[text];
}

String signedRating(Object? value) {
  final number = adminInt(value);
  return number == null ? '변동 기록 없음' : '${number > 0 ? '+' : ''}$number';
}

class ManagerResult {
  ManagerResult.fromJson(this.data);
  final AdminRow data;
  String get code => adminText(data['code']);
  String get ground => adminText(data['ground']);
  String get home => adminText(data['home']);
  String get away => adminText(data['away']);
  String get date => adminText(data['date'] ?? data['recorded_at']);
  String get time => adminText(data['time']);
  String get score => data['home_score'] == null || data['away_score'] == null
      ? '점수 미기록'
      : '${data['home_score']} : ${data['away_score']}';
  List<AdminRow> get sides => adminRows(data['sides']);
  List<AdminRow> get columns => adminRows(data['stat_columns']);
}
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

class ManagerRatingRules {
  ManagerRatingRules.fromJson(AdminRow data)
    : tiers =
          adminRows(data['tiers'])
              .where(
                (row) =>
                    adminInt(row['min_rating']) != null &&
                    row['name'] is String,
              )
              .toList()
            ..sort(
              (a, b) =>
                  adminInt(b['min_rating'])!
                      .compareTo(adminInt(a['min_rating'])!),
            );
  final List<AdminRow> tiers;
  String? tier(Object? rating) {
    final value = adminInt(rating);
    if (value == null) return null;
    for (final row in tiers) {
      if (value >= adminInt(row['min_rating'])!) return row['name'] as String;
    }
    return null;
  }
}
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
