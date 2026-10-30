// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 신고 조회는 GET, 심의 시작은 로그인한 본사 ID를 포함한 JSON POST로 연결합니다.
import '../model/report_model.dart';
import 'operations_api.dart';

class ReportService {
  ReportService(this.api);
  final OperationsApi api;
  Future<ReportCollection> list({String? state, String? sport}) async {
    final path = Uri(
      path: '/report/list',
      queryParameters: {'state': ?state, 'sport': ?sport},
    ).toString();
    return ReportCollection.fromJson(await api.request(path));
  }

  Future<ReportRecord> detail(int id) async =>
      ReportRecord.fromJson(await api.request('/report/detail/$id'));
  Future<void> startReview(int id, String staffId) async {
    final result = await api.request(
      '/report/review/$id',
      json: {'h_id': staffId},
    );
    if (result['result'] != 'OK') {
      throw Exception('심의를 시작하지 못했습니다. 다시 시도해 주세요.');
    }
  }
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
