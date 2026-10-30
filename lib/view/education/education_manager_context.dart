// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 교육 화면에서 기존 담당 종목과 평가 원문을 확인하고 대상별 재교육으로 이어집니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/education_model.dart';
import '../../vm/education_notifier.dart';
import '../shared/admin_style.dart';

class EducationAssignedSports extends ConsumerWidget {
  const EducationAssignedSports({
    super.key,
    required this.staffId,
    required this.managerId,
  });
  final String staffId, managerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(educationAssignedSportsProvider(staffId))
      .when(
        loading: () => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (e, s) => IconButton(
          tooltip: '담당 종목을 불러오지 못했습니다. 다시 시도',
          onPressed: () =>
              ref.invalidate(educationAssignedSportsProvider(staffId)),
          icon: const Icon(Icons.refresh, size: 16),
        ),
        data: (data) {
          final sports = data[managerId];
          return SizedBox(
            width: 72,
            child: Text(
              sports == null
                  ? '미기록'
                  : sports.isEmpty
                  ? '배정 없음'
                  : sports.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          );
        },
      );
}

Future<void> showEducationEvaluations(
  BuildContext context, {
  required String staffId,
  required EducationManager manager,
  required VoidCallback onRetraining,
}) => showDialog<void>(
  context: context,
  builder: (_) => _EvaluationDialog(
    staffId: staffId,
    manager: manager,
    onRetraining: onRetraining,
  ),
);

class _EvaluationDialog extends ConsumerWidget {
  const _EvaluationDialog({
    required this.staffId,
    required this.manager,
    required this.onRetraining,
  });
  final String staffId;
  final EducationManager manager;
  final VoidCallback onRetraining;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (staffId: staffId, managerId: manager.id);
    final evaluations = ref.watch(educationEvaluationsProvider(key));
    return AlertDialog(
      title: Text('${manager.name} · 평가 이력'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: evaluations.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(educationError(e)),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(educationEvaluationsProvider(key)),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
            data: (rows) => rows.isEmpty
                ? const Text('등록된 평가 이력이 없습니다.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final row in rows)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AdminStyle.canvas,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.date?.replaceFirst('T', ' ') ?? '평가일 미기록',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AdminStyle.muted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(row.description ?? '평가 내용 미기록'),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            onRetraining();
          },
          child: const Text('이 매니저 재교육 개설'),
        ),
      ],
    );
  }
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
