// 작업자 : 최현준 / 작업 일 : 2026-10-24
// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 문의 목록·대화·답변을 좌우 분할하고 저장 실패 시 작성 내용을 보존합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../vm/headquarters_notifier.dart';
import '../headquarters/admin_components.dart';
import '../shared/records_view.dart';
import '../shared/admin_style.dart';
import '../shared/admin_split_view.dart';

class InquiryPage extends ConsumerStatefulWidget {
  const InquiryPage({super.key, required this.staffId});
  final String staffId;
  @override
  ConsumerState<InquiryPage> createState() => _InquiryPageState();
}

class _InquiryPageState extends ConsumerState<InquiryPage> {
  String filter = '';
  int? selected;
  @override
  Widget build(BuildContext context) {
    final path = '/inquiry/list${filter.isEmpty ? '' : '?i_state=$filter'}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '', label: Text('전체')),
                ButtonSegment(value: '0', label: Text('답변 대기')),
                ButtonSegment(value: '1', label: Text('답변 완료')),
              ],
              selected: {filter},
              onSelectionChanged: (v) => setState(() {
                filter = v.first;
                selected = null;
              }),
            ),
          ),
        ),
        Expanded(
          child: RecordsView(
            path: path,
            builder: (data) {
              final rows = adminRows(data['results']);
              if (rows.isEmpty) return const Center(child: Text('문의가 없습니다.'));
              final id = selected ?? adminInt(rows.first['i_seq']);
              return AdminSplitView(
                selected: selected != null,
                onBack: () => setState(() => selected = null),
                list: ListView(
                  children: [
                    for (final row in rows)
                      Material(
                        color: adminInt(row['i_seq']) == id
                            ? AdminStyle.selected
                            : Colors.white,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          title: Text(
                            adminText(row['title']),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${adminText(row['c_name'] ?? row['c_id_seq'])} · ${adminText(row['i_date'])}',
                            maxLines: 2,
                          ),
                          trailing: adminBadge(
                            '${row['i_state']}' == '1' ? '답변 완료' : '대기',
                            alert: '${row['i_state']}' != '1',
                          ),
                          onTap: () =>
                              setState(() => selected = adminInt(row['i_seq'])),
                        ),
                      ),
                  ],
                ),
                detail: id == null
                    ? const SizedBox()
                    : _InquiryContent(sequence: id, staffId: widget.staffId),
              );
            },
          ),
        ),
      ],
    );
  }
}

class InquiryDetailPage extends StatelessWidget {
  const InquiryDetailPage({
    super.key,
    required this.sequence,
    required this.staffId,
  });
  final dynamic sequence;
  final String staffId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('문의 상세')),
    body: _InquiryContent(sequence: adminInt(sequence)!, staffId: staffId),
  );
}

class _InquiryContent extends ConsumerWidget {
  const _InquiryContent({required this.sequence, required this.staffId});
  final int sequence;
  final String staffId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => RecordsView(
    path: '/inquiry/detail/$sequence',
    builder: (data) {
      final items = [data, ...adminRows(data['follow_ups'])];
      return ListView(
        padding: const EdgeInsets.all(22),
        children: [
          adminTitle(adminText(data['title'] ?? '문의 상세')),
          const SizedBox(height: 16),
          for (var i = 0; i < items.length; i++)
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      adminBadge(i == 0 ? '문의' : '추가 문의'),
                      const Spacer(),
                      Text(
                        adminText(items[i]['i_date']),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdminStyle.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    adminText(items[i]['post']),
                    style: const TextStyle(fontSize: 15, height: 1.7),
                  ),
                  const SizedBox(height: 16),
                  if ('${items[i]['i_state']}' == '1')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AdminStyle.canvas,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '본사 답변',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(adminText(items[i]['inquiry_detail'])),
                          const SizedBox(height: 8),
                          Text(
                            '${adminText(items[i]['h_name'] ?? items[i]['h_id'])} · ${adminText(items[i]['i_answer_date'])}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AdminStyle.muted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.reply, size: 18),
                        label: const Text('답변 작성'),
                        onPressed: adminInt(items[i]['i_seq']) == null
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => AnswerDialog(
                                  sequence: adminInt(items[i]['i_seq'])!,
                                  staffId: staffId,
                                ),
                              ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class AnswerDialog extends ConsumerStatefulWidget {
  const AnswerDialog({
    super.key,
    required this.sequence,
    required this.staffId,
  });
  final int sequence;
  final String staffId;
  @override
  ConsumerState<AnswerDialog> createState() => _AnswerDialogState();
}

class _AnswerDialogState extends ConsumerState<AnswerDialog> {
  final text = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mutation = ref.watch(adminMutationProvider(widget.staffId));
    return PopScope(
      canPop: !mutation.isLoading,
      child: AlertDialog(
        title: const Text('문의 답변 작성'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: text,
                    enabled: !mutation.isLoading,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: '답변 내용'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? '답변 내용을 입력해 주세요.' : null,
                  ),
                  if (mutation.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        adminError(mutation.error!),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: mutation.isLoading ? null : () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: mutation.isLoading
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    final saved = await ref
                        .read(adminMutationProvider(widget.staffId).notifier)
                        .answer(widget.sequence, text.text.trim());
                    if (saved && context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('답변을 등록했습니다.')),
                      );
                    }
                  },
            child: Text(mutation.isLoading ? '등록 중…' : '답변 등록'),
          ),
        ],
      ),
    );
  }
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
