// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 개인·팀 경기 반영을 API의 ID와 null 계약으로 검증합니다.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/service/manager_result_service.dart';
import 'package:bootcamp_project_gongin_admin_app/service/operations_api.dart';
import 'package:bootcamp_project_gongin_admin_app/model/manager_result_model.dart';

import 'manager_schedule_test.dart' show jsonResponse;

void main() {
  test('회원 순서와 팀 순서가 달라도 실제 ID로 +24·-20·null을 연결', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path == '/match/manager/results/9') {
        return jsonResponse({
          'kind': 'team',
          'sides': [
            {
              'members': [
                {'c_id_seq': 'a'},
                {'c_id_seq': 'b'},
                {'c_id_seq': 'c'},
              ],
            },
          ],
          'team_summary': [
            {'t_id': 2},
            {'t_id': 1},
          ],
        });
      }
      expect(paths.first, '/match/manager/results/9');
      expect(request.url.path, '/match/team_match/9');
      return jsonResponse({
        'home_team': {
          't_id': 1,
          'players': [
            {'c_id_seq': 'b', 'rating_change': -20},
            {'c_id_seq': 'a', 'rating_change': 24},
          ],
        },
        'away_team': {
          't_id': 2,
          'players': [
            {'c_id_seq': 'c', 'rating_change': null},
          ],
        },
        'result': {
          'home_rating': {'rating_change': 12},
          'away_rating': {'rating_change': -8},
        },
      });
    });
    addTearDown(client.close);
    final result = await ManagerResultService(OperationsApi(client: client))
        .detail('9');
    final members = result.sides.first['members'] as List;
    expect(members.map((m) => signedRating(m['rating_change'])).toList(), [
      '+24',
      '-20',
      '변동 기록 없음',
    ]);
    final teams = result.data['team_summary'] as List;
    expect(teams.map((t) => t['rating_change']).toList(), [-8, 12]);
    expect(signedRating(0), '0');
  });
  test('실력매칭은 기존 API 변동을 보존하고 팀 상세를 요청하지 않는다', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/match/manager/results/pickup');
      return jsonResponse({
        'kind': 'pickup',
        'sides': [
          {
            'members': [
              {'rating_change': 24},
            ],
          },
        ],
      });
    });
    addTearDown(client.close);
    final result = await ManagerResultService(OperationsApi(client: client))
        .detail('pickup');
    expect((result.sides.first['members'] as List).first['rating_change'], 24);
  });
}
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
