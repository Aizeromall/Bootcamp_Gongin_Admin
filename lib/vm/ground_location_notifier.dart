// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 담당자별 선택 위치를 분리하고 늦게 온 이전 클릭 응답을 무시합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/ground_location.dart';
import '../service/ground_location_service.dart';
import '../service/operations_api.dart';
import 'login_notifier.dart';

final groundLocationServiceProvider = Provider(
  (ref) => GroundLocationService(ref.watch(operationsApiProvider)),
);

class GroundLocationNotifier extends AsyncNotifier<GroundLocation?> {
  GroundLocationNotifier(this.staffId);
  final String staffId;
  int version = 0;
  @override
  GroundLocation? build() {
    ref.watch(loginProvider);
    version++;
    return null;
  }

  Future<void> select(double lat, double lng) async {
    final request = ++version;
    state = const AsyncLoading();
    try {
      final location = await ref
          .read(groundLocationServiceProvider)
          .resolve(lat, lng);
      if (ref.mounted && request == version) state = AsyncData(location);
    } catch (error, stack) {
      if (ref.mounted && request == version) state = AsyncError(error, stack);
    }
  }
}

final groundLocationProvider = AsyncNotifierProvider.autoDispose
    .family<GroundLocationNotifier, GroundLocation?, String>(
      GroundLocationNotifier.new,
    );
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
