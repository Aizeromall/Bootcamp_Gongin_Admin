// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 교육 조회와 변경 상태를 본사 계정별로 분리합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/education_model.dart';
import '../service/education_service.dart';
import '../service/operations_api.dart';
import 'login_notifier.dart';

final educationServiceProvider = Provider(
  (ref) => EducationService(ref.watch(operationsApiProvider)),
);
final educationListProvider = FutureProvider.autoDispose
    .family<EducationCollection, String>(
      (ref, staffId) => ref.watch(educationServiceProvider).list(),
      retry: (_, _) => null,
    );
final educationManagersProvider = FutureProvider.autoDispose
    .family<List<EducationManager>, String>(
      (ref, staffId) => ref.watch(educationServiceProvider).managers(),
      retry: (_, _) => null,
    );
// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 담당 종목은 목록 요청 두 번으로 공유하고 평가 상세는 사용자가 열 때만 조회합니다.
final educationAssignedSportsProvider = FutureProvider.autoDispose
    .family<Map<String, List<String>>, String>(
      (ref, staffId) => ref.watch(educationServiceProvider).assignedSports(),
      retry: (_, _) => null,
    );
typedef EducationProfileKey = ({String staffId, String managerId});
final educationEvaluationsProvider = FutureProvider.autoDispose
    .family<List<EducationEvaluation>, EducationProfileKey>(
      (ref, key) =>
          ref.watch(educationServiceProvider).evaluations(key.managerId),
      retry: (_, _) => null,
    );

class EducationMutation extends AsyncNotifier<String?> {
  EducationMutation(this.staffId);
  final String staffId;
  @override
  String? build() {
    ref.watch(loginProvider);
    return null;
  }

  Future<bool> create(Map<String, dynamic> values) async =>
      _run(() => ref.read(educationServiceProvider).create(values));
  Future<bool> complete(int id) async => _run(() async {
    await ref.read(educationServiceProvider).complete(id);
    return null;
  });
  Future<bool> _run(Future<String?> Function() action) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    try {
      final result = await action();
      if (!ref.mounted) return false;
      ref.invalidate(educationListProvider(staffId));
      ref.invalidate(operationsDataProvider);
      state = AsyncData(result);
      return true;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      return false;
    }
  }
}

final educationMutationProvider = AsyncNotifierProvider.autoDispose
    .family<EducationMutation, String?, String>(EducationMutation.new);
String educationError(Object error) => error is OperationsApiException
    ? error.message
    : '교육 정보를 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.';
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
