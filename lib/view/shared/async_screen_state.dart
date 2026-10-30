// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 화면은 상태를 보관하지 않고 화면별 AsyncNotifier의 값을 읽고 변경합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../../vm/screen_state_notifier.dart';

mixin AsyncScreenState<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  ScreenValues initialScreenValues();
  ScreenValues copyScreenValues(ScreenValues values);
  late ScreenStateScope screenScope = ScreenStateScope(
    initialScreenValues,
    copyScreenValues,
  );
  void resetScreenScope() {
    screenScope = ScreenStateScope(initialScreenValues, copyScreenValues);
  }

  T screenValue<T>(String key) =>
      ref.read(screenStateProvider(screenScope).notifier).current[key] as T;
  void setScreenValue(String key, Object? value) =>
      ref.read(screenStateProvider(screenScope).notifier).setValue(key, value);
  void updateScreen(void Function() action) =>
      ref.read(screenStateProvider(screenScope).notifier).edit(action);
  // 컨트롤러는 UI 자원이며 입력 문자열은 화면 AsyncNotifier에도 반영합니다.
  // 생성 시에는 provider를 변경하지 않아 초기 build 중 상태 변경을 피합니다.
  TextEditingController screenTextController(String key, {String text = ''}) {
    final controller = TextEditingController(text: text);
    controller.addListener(() {
      if (!mounted) return;
      final notifier = ref.read(screenStateProvider(screenScope).notifier);
      if (notifier.current['text:$key'] != controller.text) {
        notifier.setValue('text:$key', controller.text);
      }
    });
    return controller;
  }

  void watchScreen() => ref.watch(screenStateProvider(screenScope));
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
