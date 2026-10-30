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
  });
  final CancellationKey target;
  final String groundName;
  @override
  ConsumerState<MatchCancelDialog> createState() => _MatchCancelDialogState();
}

class _MatchCancelDialogState extends ConsumerState<MatchCancelDialog> {
  int? reason;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchCancellationProvider(widget.target));
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
                      : (v) => setState(() => reason = v),
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
                        .read(matchCancellationProvider(widget.target).notifier)
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
