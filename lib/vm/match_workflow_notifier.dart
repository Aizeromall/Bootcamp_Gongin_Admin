// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 담당자·경기별 서버 상태와 명령 중복 제출·오류 복구를 AsyncNotifier가 소유합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../service/match_workflow_service.dart';
import '../service/operations_api.dart';
import 'login_notifier.dart';

typedef MatchWorkflowKey = ({String? managerId, String path});
final matchWorkflowServiceProvider = Provider(
  (ref) => MatchWorkflowService(ref.watch(operationsApiProvider)),
);
final matchWorkflowProvider = AsyncNotifierProvider.autoDispose
    .family<MatchWorkflowNotifier, Map<String, dynamic>, MatchWorkflowKey>(
      MatchWorkflowNotifier.new,
      retry: (_, _) => null,
    );

class MatchWorkflowNotifier extends AsyncNotifier<Map<String, dynamic>> {
  MatchWorkflowNotifier(this.key);
  final MatchWorkflowKey key;
  int generation = 0;
  Map<String, dynamic>? lastConfirmed;
  // 실패·저장 중에도 마지막 서버 확인 결과를 유지해 경기 입력을 보존합니다.
  Map<String, dynamic>? get current => state.value ?? lastConfirmed;
  @override
  Future<Map<String, dynamic>> build() async {
    ref.watch(loginProvider);
    final request = ++generation;
    lastConfirmed = null;
    final result = await ref.watch(matchWorkflowServiceProvider).load(key.path);
    if (ref.mounted && request == generation) lastConfirmed = result;
    return result;
  }

  Future<void> reload() async {
    if (state.isLoading) return;
    final request = ++generation;
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(matchWorkflowServiceProvider)
          .load(key.path);
      if (ref.mounted && request == generation) {
        lastConfirmed = result;
        state = AsyncData(result);
      }
    } catch (error, stack) {
      if (ref.mounted && request == generation) {
        state = AsyncError(error, stack);
      }
    }
  }

  Future<bool> command(
    String action, [
    Map<String, dynamic> values = const {},
  ]) async {
    if (state.isLoading || current == null) return false;
    final version = current!['version'];
    final request = ++generation;
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(matchWorkflowServiceProvider)
          .command(key.path, version, action, values);
      if (!ref.mounted || request != generation) return false;
      lastConfirmed = result;
      state = AsyncData(result);
      return true;
    } catch (error, stack) {
      if (ref.mounted && request == generation) {
        state = AsyncError(error, stack);
      }
      return false;
    }
  }
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
