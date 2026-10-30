// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 매니저 토큰으로 본인이 등록한 결과만 조회합니다.
import '../model/manager_result_model.dart';
import '../model/headquarters_model.dart';
import 'operations_api.dart';
import 'headquarters_service.dart';

class ManagerResultService {
  ManagerResultService(this.api);
  final OperationsApi api;
  Future<List<ManagerResult>> list(String kind, String sport) async {
    final data = await api.request(
      adminPath('/match/manager/results', {
        'kind': kind,
        'e_code': sport == 'all' ? null : sport,
      }),
    );
    return adminRows(data['results']).map(ManagerResult.fromJson).toList();
  }

  // 수정 일 : 2026-10-29 / 작업자 : 양태건
  // 담당자 소유 결과를 먼저 확인한 뒤 팀 상세의 경기별 변동을 실제 ID로 연결합니다.
  Future<ManagerResult> detail(String code) async {
    final data = await api.request(
      '/match/manager/results/${Uri.encodeComponent(code)}',
    );
    if (data['kind'] != 'team') return ManagerResult.fromJson(data);
    final match = await api.request(
      '/match/team_match/${Uri.encodeComponent(code)}',
    );
    final result = adminDocument(match['result']);
    final players = <String, AdminRow>{};
    final ratings = <String, Object?>{};
    for (final side in ['home', 'away']) {
      final team = adminDocument(match['${side}_team']);
      for (final player in adminRows(team['players'])) {
        players[adminText(player['c_id_seq'])] = player;
      }
      ratings[adminText(team['t_id'])] = adminDocument(
        result['${side}_rating'],
      )['rating_change'];
    }
    for (final player in adminRows(match['other_players'])) {
      players[adminText(player['c_id_seq'])] = player;
    }
    data['sides'] = [
      for (final side in adminRows(data['sides']))
        {
          ...side,
          'members': [
            for (final member in adminRows(side['members']))
              {
                ...member,
                'rating_change':
                    players[adminText(member['c_id_seq'])]?['rating_change'],
              },
          ],
        },
    ];
    data['team_summary'] = [
      for (final team in adminRows(data['team_summary']))
        {...team, 'rating_change': ratings[adminText(team['t_id'])]},
    ];
    return ManagerResult.fromJson(data);
  }
}
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
