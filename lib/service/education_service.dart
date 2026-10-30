// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 본사 서명 토큰은 공통 OperationsApi가 전달합니다.
import '../model/education_model.dart';
import 'operations_api.dart';

class EducationService {
  EducationService(this.api);
  final OperationsApi api;
  // 수정 일 : 2026-10-27 / 작업자 : 양태건
  // 배정 목록과 구장 종목을 실제 구장 코드로 연결하며 개인별 중복 요청을 피합니다.
  Future<Map<String, List<String>>> assignedSports() async {
    final data = await Future.wait([
      api.request('/approval/grounds/managers'),
      api.request('/match/ground'),
    ]);
    final grounds = {
      for (final row in (data[1]['results'] as List? ?? []).whereType<Map>())
        '${row['g_code']}': educationText(row['e_code']),
    };
    return {
      for (final manager
          in (data[0]['results'] as List? ?? []).whereType<Map>())
        '${manager['m_id']}': {
          for (final assign
              in (manager['assign'] as List? ?? []).whereType<Map>())
            grounds['${assign['g_code']}'] ?? '종목 미기록',
        }.toList(),
    };
  }

  Future<List<EducationEvaluation>> evaluations(String managerId) async {
    final data = await api.request(
      '/management/managers/${Uri.encodeComponent(managerId)}',
    );
    return (data['evaluates'] as List? ?? [])
        .whereType<Map>()
        .map((v) => EducationEvaluation.fromJson(Map<String, dynamic>.from(v)))
        .toList();
  }

  Future<EducationCollection> list() async =>
      EducationCollection.fromJson(await api.request('/education/courses'));
  Future<List<EducationManager>> managers() async {
    final data = await api.request('/education/managers');
    return (data['results'] as List? ?? [])
        .map(
          (v) => EducationManager.fromJson(Map<String, dynamic>.from(v as Map)),
        )
        .toList();
  }

  Future<String> create(Map<String, dynamic> values) async {
    final result = await api.request('/education/courses', json: values);
    if (result['result'] != 'OK' || result['course_id'] is! String) {
      throw Exception('교육 개설 결과를 확인할 수 없습니다.');
    }
    return result['course_id'] as String;
  }

  Future<void> complete(int trainingId) async {
    final result = await api.request(
      '/education/completion/$trainingId',
      json: {'completed': true},
    );
    if (result['result'] != 'OK') throw Exception('이수 처리 결과를 확인할 수 없습니다.');
  }
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
