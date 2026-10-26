// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../service/operations_api.dart';
import '../shared/records_view.dart';

class InquiryPage extends ConsumerStatefulWidget {
  const InquiryPage({super.key, required this.staffId});
  final String staffId;
  @override
  ConsumerState<InquiryPage> createState() => _InquiryPageState();
}

class _InquiryPageState extends ConsumerState<InquiryPage> {
  String filter = '';
  @override
  Widget build(BuildContext context) {
    final path = '/inquiry/list${filter.isEmpty ? '' : '?i_state=$filter'}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '', label: Text('전체')),
              ButtonSegment(value: '0', label: Text('답변 대기')),
              ButtonSegment(value: '1', label: Text('답변 완료')),
            ],
            selected: {filter},
            onSelectionChanged: (values) =>
                setState(() => filter = values.first),
          ),
        ),
        Expanded(
          child: RecordsView(
            path: path,
            builder: (data) {
              final rows = (data['results'] as List? ?? [])
                  .cast<Map<String, dynamic>>();
              if (rows.isEmpty) return const Center(child: Text('문의가 없습니다.'));
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return Card(
                    child: ListTile(
                      title: Text('${row['title'] ?? '문의'}'),
                      subtitle: Text(
                        '${row['c_name'] ?? row['c_id_seq']} · ${row['i_date'] ?? ''}',
                      ),
                      trailing: Chip(
                        label: Text(
                          '${row['i_state']}' == '1' ? '답변 완료' : '대기',
                        ),
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => InquiryDetailPage(
                              sequence: row['i_seq'],
                              staffId: widget.staffId,
                            ),
                          ),
                        );
                        ref.invalidate(operationsDataProvider(path));
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class InquiryDetailPage extends ConsumerWidget {
  const InquiryDetailPage({
    super.key,
    required this.sequence,
    required this.staffId,
  });
  final dynamic sequence;
  final String staffId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = '/inquiry/detail/$sequence';
    return Scaffold(
      appBar: AppBar(title: const Text('문의 상세')),
      body: RecordsView(
        path: path,
        builder: (data) {
          final items = [
            data,
            ...(data['follow_ups'] as List? ?? []).cast<Map<String, dynamic>>(),
          ];
          return ListView(
            padding: const EdgeInsets.all(24),
            children: items
                .map(
                  (item) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${item['title'] ?? '추가 문의'}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Text('${item['i_date'] ?? ''}'),
                          const SizedBox(height: 16),
                          SelectableText('${item['post'] ?? ''}'),
                          const Divider(height: 32),
                          if ('${item['i_state']}' == '1') ...[
                            const Text(
                              '등록된 답변',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            SelectableText('${item['inquiry_detail'] ?? ''}'),
                            Text('${item['i_answer_date'] ?? ''}'),
                          ] else
                            FilledButton.icon(
                              icon: const Icon(Icons.reply),
                              label: const Text('답변 작성'),
                              onPressed: () async {
                                final answer = await showDialog<String>(
                                  context: context,
                                  builder: (_) => const AnswerDialog(),
                                );
                                if (answer == null) return;
                                try {
                                  await ref
                                      .read(operationsApiProvider)
                                      .request(
                                        '/inquiry/answer',
                                        form: {
                                          'i_seq': '${item['i_seq']}',
                                          'h_id': staffId,
                                          'inquiry_detail': answer,
                                        },
                                      );
                                  ref.invalidate(operationsDataProvider(path));
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$error')),
                                    );
                                  }
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class AnswerDialog extends StatefulWidget {
  const AnswerDialog({super.key});
  @override
  State<AnswerDialog> createState() => _AnswerDialogState();
}

class _AnswerDialogState extends State<AnswerDialog> {
  final text = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('문의 답변 작성'),
    content: SizedBox(
      width: 500,
      child: Form(
        key: form,
        child: TextFormField(
          controller: text,
          maxLines: 6,
          decoration: const InputDecoration(labelText: '답변 내용'),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? '답변 내용을 입력해 주세요.' : null,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, text.text.trim());
          }
        },
        child: const Text('답변 등록'),
      ),
    ],
  );
}
// 최종 수정일 : 2026-10-24
