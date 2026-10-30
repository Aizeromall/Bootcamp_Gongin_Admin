// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 경기 조회·명령의 HTTP 계약은 서비스에 두고 화면에서는 Notifier만 호출합니다.
import 'operations_api.dart';

class MatchWorkflowService {
  const MatchWorkflowService(this.api);
  final OperationsApi api;
  Future<Map<String, dynamic>> load(String path) => api.request(path);
  Future<Map<String, dynamic>> command(
    String path,
    Object? version,
    String action,
    Map<String, dynamic> values,
  ) => api.request(
    path,
    json: {'version': version, 'action': action, ...values},
  );
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
