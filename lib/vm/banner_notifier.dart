import 'dart:async';

// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 계정별 배너 상태와 중복 저장 방지. 실제 권한은 서버가 최종 검증합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/banner_model.dart';
import '../model/login_role.dart';
import '../service/banner_service.dart';
import '../service/operations_api.dart';
import 'login_notifier.dart';

final bannerServiceProvider = Provider(
  (ref) => BannerService(ref.watch(operationsApiProvider)),
);
final bannerListProvider = AsyncNotifierProvider.autoDispose
    .family<BannerListNotifier, List<BannerImage>, String>(
      BannerListNotifier.new,
      retry: (_, _) => null,
    );
final bannerMutationProvider = AsyncNotifierProvider.autoDispose
    .family<BannerMutation, void, String>(BannerMutation.new);

class BannerMutation extends AsyncNotifier<void> {
  BannerMutation(this.staffId);
  final String staffId;
  @override
  void build() {
    ref.watch(loginProvider);
  }

  void checkPermission() {
    final session = ref.read(loginProvider).asData?.value;
    if (session?.userId != staffId ||
        session?.role != LoginRole.headquarters ||
        session?.department?.trim() != '홍보팀') {
      throw const OperationsApiException(403, '배너 등록·선택은 홍보팀 직원만 가능합니다.');
    }
  }

  Future<BannerImage?> upload(String name, List<int> bytes) async {
    if (state.isLoading) return null;
    state = const AsyncLoading();
    try {
      checkPermission();
      if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
        throw const OperationsApiException(
          422,
          '이미지는 0바이트 초과, 10MB 이하로 선택해 주세요.',
        );
      }
      final image = await ref
          .read(bannerServiceProvider)
          .upload(staffId, name, bytes);
      if (!ref.mounted) return null;
      ref.invalidate(bannerListProvider(staffId));
      state = const AsyncData(null);
      return image;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      return null;
    }
  }

  Future<bool> choose(int id, String start, String end) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    try {
      checkPermission();
      await ref.read(bannerServiceProvider).choose(staffId, id, start, end);
      if (!ref.mounted) return false;
      ref.invalidate(bannerListProvider(staffId));
      state = const AsyncData(null);
      return true;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      return false;
    }
  }
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class BannerListNotifier extends AsyncNotifier<List<BannerImage>> {
  BannerListNotifier(this.staffId);
  final String staffId;
  @override
  FutureOr<List<BannerImage>> build() =>
      ref.watch(bannerServiceProvider).list();
}

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
