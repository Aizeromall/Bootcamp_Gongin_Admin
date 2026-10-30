// 수정 일 : 2026-10-30 / 작업자 : 양태건
import '../model/ground_location.dart';
import 'operations_api.dart';

class GroundLocationService {
  const GroundLocationService(this.api);
  final OperationsApi api;
  Future<GroundLocation> resolve(double lat, double lng) async =>
      GroundLocation.fromJson(
        await api.request('/approval/ground-location?lat=$lat&lng=$lng'),
      );
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
