// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../service/operations_api.dart';
import '../shared/records_view.dart';

class MatchPage extends ConsumerWidget {
  const MatchPage({super.key, required this.managerId});
  final String managerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = '/match/list/${Uri.encodeComponent(managerId)}';
    return RecordsView(
      path: path,
      builder: (data) {
        final rows = (data['reservations'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        if (rows.isEmpty) {
          return const Center(child: Text('배정된 구장의 예약 경기가 없습니다.'));
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(operationsDataProvider(path));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${row['g_name']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${row['r_date']} · ${row['rs_time']} – ${row['re_time']}',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${row['c_name']} · ${row['c_position'] ?? '포지션 미등록'} · 예약 ${row['r_seq']}',
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('출석 등록'),
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => AttendanceDialog(
                                managerId: managerId,
                                reservation: row,
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            icon: const Icon(Icons.scoreboard_outlined),
                            label: const Text('경기 결과 등록'),
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => ScoreDialog(
                                managerId: managerId,
                                reservation: row,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class AttendanceDialog extends ConsumerStatefulWidget {
  const AttendanceDialog({
    super.key,
    required this.managerId,
    required this.reservation,
  });
  final String managerId;
  final Map<String, dynamic> reservation;
  @override
  ConsumerState<AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends ConsumerState<AttendanceDialog> {
  bool attendance = true;
  bool saving = false;
  String? error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.reservation['c_name']} 출석 등록'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('등록된 출석은 현재 API에서 수정할 수 없습니다.'),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('출석')),
            ButtonSegment(value: false, label: Text('결석')),
          ],
          selected: {attendance},
          onSelectionChanged: saving
              ? null
              : (values) => setState(() => attendance = values.first),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                setState(() {
                  saving = true;
                  error = null;
                });
                try {
                  await ref
                      .read(operationsApiProvider)
                      .request(
                        '/match/attendance/${Uri.encodeComponent(widget.managerId)}/${widget.reservation['r_seq']}',
                        json: {'c_r_r_attendance': attendance},
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('출석이 등록되었습니다.')),
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) setState(() => error = '$e');
                } finally {
                  if (mounted) setState(() => saving = false);
                }
              },
        child: Text(saving ? '등록 중…' : '등록 확정'),
      ),
    ],
  );
}

class ScoreDialog extends ConsumerStatefulWidget {
  const ScoreDialog({
    super.key,
    required this.managerId,
    required this.reservation,
  });
  final String managerId;
  final Map<String, dynamic> reservation;
  @override
  ConsumerState<ScoreDialog> createState() => _ScoreDialogState();
}

class _ScoreDialogState extends ConsumerState<ScoreDialog> {
  final form = GlobalKey<FormState>();
  final controllers = List.generate(4, (_) => TextEditingController());
  bool saving = false;
  String? error;
  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.reservation['c_name']} 경기 결과'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('출석 등록을 완료한 회원의 경기 결과를 입력해 주세요.'),
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextFormField(
                    controller: controllers[i],
                    enabled: !saving,
                    maxLength: [50, 20, 50, 20][i],
                    decoration: InputDecoration(
                      labelText: ['팀명', '종목 코드', '스탯 코드', '최종 스코어'][i],
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? '필수 입력 항목입니다.' : null,
                  ),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                if (!form.currentState!.validate()) return;
                setState(() {
                  saving = true;
                  error = null;
                });
                try {
                  await ref
                      .read(operationsApiProvider)
                      .request(
                        '/match/score/${Uri.encodeComponent(widget.managerId)}/${widget.reservation['r_seq']}',
                        json: {
                          'c_r_r_team': controllers[0].text.trim(),
                          'e_code': controllers[1].text.trim(),
                          'c_r_r_statcode': controllers[2].text.trim(),
                          'c_r_r_score': controllers[3].text.trim(),
                        },
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('경기 결과가 등록되었습니다.')),
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) setState(() => error = '$e');
                } finally {
                  if (mounted) setState(() => saving = false);
                }
              },
        child: Text(saving ? '등록 중…' : '결과 등록'),
      ),
    ],
  );
}
// 최종 수정일 : 2026-10-24
