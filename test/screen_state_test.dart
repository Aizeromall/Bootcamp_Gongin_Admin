// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 화면별 AsyncNotifier 격리·변경 스냅샷·예외·수명과 입력 바인딩을 검증합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/screen_state_notifier.dart';
import 'package:bootcamp_project_gongin_admin_app/view/shared/async_screen_state.dart';

ScreenStateScope scope() => ScreenStateScope(
  () => {'selected': <String>{}, 'page': 0},
  (values) => {
    ...values,
    'selected': Set<String>.from(values['selected'] as Set),
  },
);

class DraftWidget extends ConsumerStatefulWidget {
  const DraftWidget({super.key});
  @override
  ConsumerState<DraftWidget> createState() => DraftWidgetState();
}

class DraftWidgetState extends ConsumerState<DraftWidget>
    with AsyncScreenState<DraftWidget> {
  late final text = screenTextController('name');
  @override
  Map<String, Object?> initialScreenValues() => {};
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    watchScreen();
    return TextField(controller: text);
  }
}

void main() {
  test('화면 인스턴스를 분리하고 컬렉션 변경 시 이전 스냅샷을 보존한다', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final first = scope(), second = scope();
    final a = container.listen(screenStateProvider(first), (_, _) {}),
        b = container.listen(screenStateProvider(second), (_, _) {});
    addTearDown(a.close);
    addTearDown(b.close);
    final old = container.read(screenStateProvider(first)).requireValue;
    final notifier = container.read(screenStateProvider(first).notifier);
    notifier.edit(() {
      (notifier.current['selected'] as Set<String>).add('one');
      notifier.setValue('page', 2);
    });
    expect(old['selected'], isEmpty);
    expect(
      container.read(screenStateProvider(first)).requireValue['selected'],
      {'one'},
    );
    expect(
      container.read(screenStateProvider(second)).requireValue['selected'],
      isEmpty,
    );
  });
  test('변경 중 예외가 발생하면 이전 상태를 유지한다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final key = scope();
    final subscription = container.listen(screenStateProvider(key), (_, _) {});
    addTearDown(subscription.close);
    final notifier = container.read(screenStateProvider(key).notifier);
    expect(
      () => notifier.edit(() {
        notifier.current['page'] = 4;
        throw StateError('failed');
      }),
      throwsStateError,
    );
    expect(container.read(screenStateProvider(key)).requireValue['page'], 0);
    notifier.setValue('page', 1);
    expect(container.read(screenStateProvider(key)).requireValue['page'], 1);
  });
  testWidgets('입력 문자열을 provider에 반영하고 화면 종료 시 정리한다', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final key = GlobalKey<DraftWidgetState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: DraftWidget(key: key)),
        ),
      ),
    );
    final stateScope = key.currentState!.screenScope;
    await tester.enterText(find.byType(TextField), '작성 내용');
    await tester.pump();
    expect(
      container.read(screenStateProvider(stateScope)).requireValue['text:name'],
      '작성 내용',
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(container.exists(screenStateProvider(stateScope)), isFalse);
    expect(tester.takeException(), isNull);
  });
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
