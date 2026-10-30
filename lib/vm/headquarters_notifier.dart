import 'dart:async';

// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 담당자와 조회 조건을 키로 사용하고 저장 후 목록·집계를 함께 갱신합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/headquarters_model.dart';
import '../service/headquarters_service.dart';
import '../service/operations_api.dart';
import 'login_notifier.dart';
import 'education_notifier.dart';
import 'report_notifier.dart';

typedef AdminQuery = ({String staffId, String path});
final headquartersServiceProvider = Provider(
  (ref) => HeadquartersService(ref.watch(operationsApiProvider)),
);
final adminDataProvider = AsyncNotifierProvider.autoDispose
    .family<AdminDataNotifier, AdminPayload, AdminQuery>(
      AdminDataNotifier.new,
      retry: (_, _) => null,
    );

class AdminMutation extends AsyncNotifier<void> {
  AdminMutation(this.staffId);
  final String staffId;
  @override
  void build() {
    ref.watch(loginProvider);
  }

  Future<String?> upload(String name, List<int> bytes) async {
    if (state.isLoading) return null;
    state = const AsyncLoading();
    try {
      final file = await ref
          .read(headquartersServiceProvider)
          .upload(staffId, name, bytes);
      if (!ref.mounted) return null;
      state = const AsyncData(null);
      return file;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      return null;
    }
  }

  Future<bool> save(String path, AdminRow body) async {
    return _perform(
      () => ref.read(headquartersServiceProvider).save(path, body),
    );
  }

  Future<bool> answer(int sequence, String text) => _perform(
    () => ref.read(headquartersServiceProvider).answer(sequence, staffId, text),
  );
  Future<bool> _perform(Future<void> Function() action) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    try {
      await action();
      if (!ref.mounted) return false;
      ref.invalidate(adminDataProvider);
      ref.invalidate(operationsDataProvider);
      ref.invalidate(reportListProvider);
      ref.invalidate(educationListProvider);
      state = const AsyncData(null);
      return true;
    } catch (error, stack) {
      if (!ref.mounted) return false;
      if (error is OperationsApiException && error.statusCode == 409) {
        ref.invalidate(adminDataProvider);
      }
      state = AsyncError(error, stack);
      return false;
    }
  }
}

final adminMutationProvider = AsyncNotifierProvider.autoDispose
    .family<AdminMutation, void, String>(AdminMutation.new);
String adminError(Object error) => error is OperationsApiException
    ? error.message
    : '정보를 불러오지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.';
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class AdminDataNotifier extends AsyncNotifier<AdminPayload> {
  AdminDataNotifier(this.query);
  final AdminQuery query;
  @override
  Future<AdminPayload> build() async =>
      AdminPayload(await ref.watch(operationsDataProvider(query.path).future));
}

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
