// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 매니저별 일정 API만 사용하며 전체 팀 경기 목록은 조회하지 않습니다.
import '../model/manager_schedule_model.dart';
import 'operations_api.dart';
import 'headquarters_service.dart';

class ManagerScheduleService {
  ManagerScheduleService(this.api);
  final OperationsApi api;
  Future<ManagerSchedule> load(String managerId, String date) async {
    final result = ManagerSchedule.fromJson(
      await api.request(
        adminPath('/match/schedule/${Uri.encodeComponent(managerId)}', {
          'r_date': date,
        }),
      ),
    );
    if (result.managerId != managerId || result.date != date) {
      throw const OperationsApiException(502, '일정 응답을 확인할 수 없습니다. 다시 조회해 주세요.');
    }
    return result;
  }
}
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
