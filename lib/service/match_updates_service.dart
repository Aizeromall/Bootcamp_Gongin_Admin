// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 본사 팀 매칭 조회와 역할별 취소 조회·PATCH 계약을 공통 통신 계층에 연결합니다.
import '../model/headquarters_model.dart';
import '../model/match_updates_model.dart';
import 'operations_api.dart';
import 'headquarters_service.dart';

class MatchUpdatesService {
  MatchUpdatesService(this.api);
  final OperationsApi api;
  Future<List<TeamMatchRecord>> teams({
    String? status,
    String keyword = '',
  }) async {
    final data = await api.request(
      adminPath('/match/team_match', {'status': status, 'keyword': keyword}),
    );
    return adminRows(data['results']).map(TeamMatchRecord.fromJson).toList();
  }

  Future<TeamMatchRecord> team(int code) async =>
      TeamMatchRecord.fromJson(await api.request('/match/team_match/$code'));
  Future<List<CancelledMatch>> cancellations({
    String? managerId,
    int? reason,
    String? kind,
    String? sport,
  }) async {
    final path = managerId == null
        ? '/match/cancel'
        : '/match/manage/cancel/${Uri.encodeComponent(managerId)}';
    final data = await api.request(
      adminPath(path, {
        'r_c_category': reason?.toString(),
        'kind': kind,
        'e_code': sport == 'all' ? null : sport,
      }),
    );
    final rows = adminRows(data['results']);
    // 수정 일 : 2026-10-30 / 작업자 : 양태건
    // 구버전 응답이나 다른 유형을 정상 내역으로 섞어 표시하지 않습니다.
    if (kind != null && rows.any((row) => row['kind'] != kind)) {
      throw const OperationsApiException(502, '취소 유형을 확인할 수 없습니다. 다시 조회해 주세요.');
    }
    return rows
        .map(CancelledMatch.fromJson)
        .where((r) => cancellationReasons.containsKey(r.reason))
        .toList();
  }

  Future<AdminRow> cancellationDetail(CancelledMatch match) => api.request(
    adminPath('/match/cancel/${Uri.encodeComponent(match.groundCode)}', {
      'r_date': match.date,
      'rs_time': match.start,
    }),
  );
  Future<void> cancel({
    required String managerId,
    required String groundCode,
    required String date,
    required String start,
    required int reason,
    int? teamCode,
  }) async {
    final result = await api.patch(
      '/match/manage/cancel/${Uri.encodeComponent(managerId)}',
      {
        'g_code': groundCode,
        'r_date': date,
        'rs_time': start,
        'r_c_category': reason,
        'team_code': ?teamCode,
      },
    );
    if (result['result'] != 'OK') {
      throw const OperationsApiException(
        502,
        '취소 결과를 확인할 수 없습니다. 내역을 다시 조회해 주세요.',
      );
    }
  }
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
