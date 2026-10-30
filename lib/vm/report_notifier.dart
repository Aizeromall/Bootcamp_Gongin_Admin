// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 담당자·필터별 조회를 분리하고 심의 시작 후 목록과 상세를 함께 갱신합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/report_model.dart';
import '../service/operations_api.dart';
import '../service/report_service.dart';
import 'login_notifier.dart';

typedef ReportQuery = ({String staffId, String? state, String? sport});
typedef ReportDetailKey = ({String staffId, int id});
final reportServiceProvider = Provider(
  (ref) => ReportService(ref.watch(operationsApiProvider)),
);
// 쓰기 재전송 없이 오류 화면에서 사용자가 재시도하도록 조회 자동 재시도도 끕니다.
final reportListProvider = FutureProvider.autoDispose
    .family<ReportCollection, ReportQuery>(
      (ref, query) => ref
          .watch(reportServiceProvider)
          .list(state: query.state, sport: query.sport),
      retry: (_, _) => null,
    );
final reportDetailProvider = FutureProvider.autoDispose
    .family<ReportRecord, ReportDetailKey>(
      (ref, key) => ref.watch(reportServiceProvider).detail(key.id),
      retry: (_, _) => null,
    );

class ReportFilter extends Notifier<({String? state, String? sport})> {
  @override
  ({String? state, String? sport}) build() {
    ref.watch(loginProvider);
    return (state: null, sport: null);
  }

  void selectState(String? value) => state = (state: value, sport: state.sport);
  void selectSport(String? value) => state = (state: state.state, sport: value);
}

final reportFilterProvider =
    NotifierProvider.autoDispose<
      ReportFilter,
      ({String? state, String? sport})
    >(ReportFilter.new);

class ReportReview extends AsyncNotifier<void> {
  ReportReview(this.key);
  final ReportDetailKey key;
  @override
  void build() {
    ref.watch(loginProvider);
  }

  Future<bool> start() async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    try {
      await ref.read(reportServiceProvider).startReview(key.id, key.staffId);
      if (!ref.mounted) return false;
      ref.invalidate(reportListProvider);
      ref.invalidate(operationsDataProvider);
      ref.invalidate(reportDetailProvider(key));
      state = const AsyncData(null);
      return true;
    } catch (error, stack) {
      if (!ref.mounted) return false;
      if (error is OperationsApiException && error.statusCode == 409) {
        ref.invalidate(reportListProvider);
        ref.invalidate(reportDetailProvider(key));
      }
      state = AsyncError(error, stack);
      return false;
    }
  }
}

final reportReviewProvider = AsyncNotifierProvider.autoDispose
    .family<ReportReview, void, ReportDetailKey>(ReportReview.new);
String reportErrorText(Object error) => error is OperationsApiException
    ? error.message
    : '신고 정보를 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.';
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
