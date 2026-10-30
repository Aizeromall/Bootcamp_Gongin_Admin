// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 화면 인스턴스별 선택·작성 상태를 AsyncNotifier에 보관합니다.
// Scope는 화면이 소유하며 입력 컨트롤러·스크롤·타이머 자체는 포함하지 않습니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ScreenValues = Map<String, Object?>;

class ScreenStateScope {
  const ScreenStateScope(this.initial, this.copy);
  final ScreenValues Function() initial;
  final ScreenValues Function(ScreenValues) copy;
}

final screenStateProvider = AsyncNotifierProvider.autoDispose
    .family<ScreenStateNotifier, ScreenValues, ScreenStateScope>(
      ScreenStateNotifier.new,
    );

class ScreenStateNotifier extends AsyncNotifier<ScreenValues> {
  ScreenStateNotifier(this.scope);
  final ScreenStateScope scope;
  ScreenValues? draft;
  ScreenValues get current => draft ?? state.requireValue;
  @override
  ScreenValues build() => scope.initial();
  void setValue(String key, Object? value) => edit(() => current[key] = value);
  // 여러 필드와 컬렉션을 한 번에 변경하며 이전 스냅샷을 수정하지 않습니다.
  // 콜백은 동기 UI 변경만 수행합니다. HTTP 저장은 기능별 Notifier가 담당합니다.
  void edit(void Function() action) {
    if (draft != null) {
      action();
      return;
    }
    draft = scope.copy(state.requireValue);
    try {
      action();
      state = AsyncData(draft!);
    } finally {
      draft = null;
    }
  }
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
