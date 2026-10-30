import '../shared/async_screen_state.dart';

// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 취소 사유는 숫자로 요청하고 서버의 성공이 확인된 뒤에만 창을 닫습니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/match_updates_model.dart';
import '../../vm/match_updates_notifier.dart';
import '../../vm/headquarters_notifier.dart';

class MatchCancelDialog extends ConsumerStatefulWidget {
  const MatchCancelDialog({
    super.key,
    required this.target,
    required this.groundName,
    this.teamCode,
    this.absentCount,
  });
  final int? teamCode;
  final int? absentCount;
  final CancellationKey target;
  final String groundName;
  @override
  ConsumerState<MatchCancelDialog> createState() => _MatchCancelDialogState();
}

class _MatchCancelDialogState extends ConsumerState<MatchCancelDialog>
    with AsyncScreenState<MatchCancelDialog> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {'reason': null};
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  int? get reason => screenValue<int?>('reason');
  set reason(int? value) => setScreenValue('reason', value);
  @override
  Widget build(BuildContext context) {
    watchScreen();
    // 수정 일 : 2026-10-30 / 작업자 : 양태건
    // 공통 취소 창에서 팀 경기코드를 포함한 요청 상태를 분리합니다.
    final provider = widget.teamCode == null
        ? matchCancellationProvider(widget.target)
        : teamMatchCancellationProvider((
            target: widget.target,
            teamCode: widget.teamCode!,
          ));
    final state = ref.watch(provider);
    return PopScope(
      canPop: !state.isLoading,
      child: AlertDialog(
        title: const Text('경기 전체 예약 취소'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${widget.groundName}\n${widget.target.date} · ${widget.target.start}',
                ),
                const SizedBox(height: 12),
                const Text('이 경기의 전체 예약을 취소합니다. 취소 사유를 선택해 주세요.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: '취소 사유'),
                  items: [
                    for (final e in cancellationReasons.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: state.isLoading
                      ? null
                      : (v) => updateScreen(() => reason = v),
                ),
                // 수정 일 : 2026-10-30 / 작업자 : 양태건
                // 시설·우천은 차감하지 않고 노쇼 취소의 결석자 패널티만 사전 안내합니다.
                if (reason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      reason == 3
                          ? '${widget.absentCount == null ? '결석으로 확인된 회원' : '결석 확인 ${widget.absentCount}명'}에게 최대 -30점의 노쇼 패널티가 적용됩니다. 최저 1000점이며 출석·미확인 회원은 제외됩니다.'
                          : '시설 문제·우천 취소에는 점수 패널티가 적용되지 않습니다.',
                      style: TextStyle(color: reason == 3 ? Colors.red : null),
                    ),
                  ),
                if (state.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      adminError(state.error!),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: state.isLoading
                ? null
                : () => Navigator.pop(context, false),
            child: const Text('돌아가기'),
          ),
          FilledButton(
            onPressed: state.isLoading || reason == null
                ? null
                : () async {
                    final saved = await ref
                        .read(provider.notifier)
                        .submit(reason!);
                    if (saved && context.mounted) Navigator.pop(context, true);
                  },
            child: Text(state.isLoading ? '처리 중…' : '예약 취소 확정'),
          ),
        ],
      ),
    );
  }
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
