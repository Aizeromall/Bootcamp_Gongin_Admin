import '../shared/async_screen_state.dart';

// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 기존 품의 문서와 단계별 결재 기록을 구분하며 최종 판단은 서버가 수행합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../vm/headquarters_notifier.dart';
import '../../vm/screen_state_notifier.dart';
import 'admin_components.dart';
import '../shared/admin_split_view.dart';
import 'approval_writer.dart';

class ApprovalPanel extends ConsumerStatefulWidget {
  const ApprovalPanel({super.key, required this.staffId, this.write = false});
  final String staffId;
  final bool write;
  @override
  ConsumerState<ApprovalPanel> createState() => _ApprovalPanelState();
}

class _ApprovalPanelState extends ConsumerState<ApprovalPanel>
    with AsyncScreenState<ApprovalPanel> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {'offset': 0, 'selected': null};
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  int get offset => screenValue<int>('offset');
  set offset(int value) => setScreenValue('offset', value);
  int? get selected => screenValue<int?>('selected');
  set selected(int? value) => setScreenValue('selected', value);
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 결재 행의 처리자가 아니라 원문 작성자로 본인 품의를 구분합니다.
  bool ownDocument(Object? content) =>
      adminDocument(adminDocument(content)['작성자'])['h_id'] == widget.staffId;

  @override
  void didUpdateWidget(covariant ApprovalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.staffId != widget.staffId) {
      resetScreenScope();
    }
  }

  @override
  Widget build(BuildContext context) {
    watchScreen();
    if (widget.write) return ApprovalWriter(staffId: widget.staffId);
    return AdminSplitView(
      selected: selected != null,
      onBack: () => updateScreen(() => selected = null),
      list: AdminData(
        staffId: widget.staffId,
        path: '/approval/requests?limit=50&offset=$offset',
        builder: (p) {
          // 한 품의에 여러 결재 행이 존재하므로 목록은 결재 기록임을 명시합니다.
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              adminTitle('품의 결재 기록'),
              const SizedBox(height: 8),
              const Text('품의별 상신·승인·반려 이력을 최신순으로 표시합니다.'),
              const SizedBox(height: 16),
              if (p.rows.isEmpty) const Text('조회된 품의 내역이 없습니다.'),
              for (final row in p.rows)
                InkWell(
                  onTap: () =>
                      updateScreen(() => selected = adminInt(row['m_code'])),
                  child: AdminCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${approvalKind(row['m_content']) ?? '품의'} · ${adminText(row['a_reason'])}',
                      ),
                      subtitle: Text(
                        '${adminText(row['h_name'])} · ${adminText(row['a_date'])} · ${adminText(row['a_step'])}단계',
                      ),
                      trailing: adminBadge(adminText(row['a_state'])),
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: offset == 0
                        ? null
                        : () => updateScreen(() => offset -= 50),
                    child: const Text('이전'),
                  ),
                  Text('${offset ~/ 50 + 1}페이지'),
                  TextButton(
                    onPressed: p.rows.length == 50
                        ? () => updateScreen(() => offset += 50)
                        : null,
                    child: const Text('다음'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      detail: selected == null
          ? const Center(child: Text('품의를 선택해 결재 내역을 확인하세요.'))
          : AdminData(
              staffId: widget.staffId,
              path: '/approval/requests/$selected',
              builder: (p) {
                final r = p.data;
                final document = adminDocument(r['m_content']);
                final content = adminDocument(document['내용']);
                final history = adminRows(r['approval']);
                final latest = history.isEmpty
                    ? <String, dynamic>{}
                    : history.last;
                final mutation = ref.watch(
                  adminMutationProvider(widget.staffId),
                );
                return ListView(
                  padding: const EdgeInsets.all(22),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => updateScreen(() => selected = null),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('품의 내역으로'),
                      ),
                    ),
                    AdminCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          adminTitle(
                            '${approvalKind(r['m_content']) ?? '품의'} · $selected',
                          ),
                          if (document.isEmpty)
                            SelectableText(adminText(r['m_content']))
                          else ...[
                            adminFields({
                              '작성자': adminDocument(document['작성자'])['h_name'],
                              '유형': document['유형'],
                            }),
                            _documentFields(content),
                            adminTitle('결재선'),
                            for (final row in adminRows(document['결재선']))
                              Text(
                                '${adminText(row['h_position'])} · ${adminText(row['h_name'])}',
                              ),
                          ],
                        ],
                      ),
                    ),
                    AdminCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          adminTitle('결재 기록'),
                          for (final row in history)
                            adminFields({
                              '처리': row['a_state'],
                              '단계': row['a_step'],
                              '담당자': row['h_name'],
                              '일시': row['a_date'],
                              '사유': row['a_reason'],
                              '의견': adminDocument(
                                row['a_signatures'],
                              )['comment'],
                            }),
                        ],
                      ),
                    ),
                    // 수정 일 : 2026-10-30 / 작업자 : 양태건
                    // 본인 작성 문서는 열람하되 승인·반려 동작은 표시하지 않습니다.
                    if (latest['a_state'] == '심사중' &&
                        document.isNotEmpty &&
                        !ownDocument(r['m_content']))
                      AdminCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('결재 순서와 휴가 대리 여부는 서버에서 확인합니다.'),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              children: [
                                OutlinedButton(
                                  onPressed: mutation.isLoading
                                      ? null
                                      : () => _sign(false),
                                  child: const Text('반려'),
                                ),
                                FilledButton(
                                  onPressed: mutation.isLoading
                                      ? null
                                      : () => _sign(true),
                                  child: const Text('승인'),
                                ),
                              ],
                            ),
                            if (mutation.hasError)
                              Text(
                                adminError(mutation.error!),
                                style: const TextStyle(color: Colors.red),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _documentFields(AdminRow c) => adminFields({
    for (final e in const {
      'h_start': '휴가 시작',
      'h_end': '휴가 종료',
      'h_deputy': '대리인',
      'g_code': '구장 번호',
      'c_seq': '계약 번호',
      'c_treaty': '계약 조건',
      'c_rentalfee': '계약 대관료',
    }.entries)
      if (c.containsKey(e.key)) e.value: c[e.key],
    if (c['new_ground'] is Map) '구장': adminDocument(c['new_ground'])['g_name'],
    if (c['assignments'] is List)
      '매니저 배정': adminRows(c['assignments'])
          .map(
            (r) =>
                '${adminText(r['m_id'])} · ${adminText(r['a_day'])} · ${adminText(r['a_time'])}',
          )
          .join('\n'),
  });
  Future<void> _sign(bool approve) async {
    final scope = ScreenStateScope(
      () => {'input': ''},
      (values) => {...values},
    );
    final form = GlobalKey<FormState>();
    final comment = await showDialog<String>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, dialogRef, _) {
          final input =
              dialogRef.watch(screenStateProvider(scope)).requireValue['input']
                  as String;
          return AlertDialog(
            title: Text(approve ? '품의 승인' : '품의 반려'),
            content: Form(
              key: form,
              child: TextFormField(
                onChanged: (value) => dialogRef
                    .read(screenStateProvider(scope).notifier)
                    .setValue('input', value),
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: approve ? '의견 (선택)' : '반려 사유',
                ),
                validator: (v) =>
                    !approve && v!.trim().isEmpty ? '반려 사유를 입력해 주세요.' : null,
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
                    Navigator.pop(context, input.trim());
                  }
                },
                child: const Text('확인'),
              ),
            ],
          );
        },
      ),
    );
    if (comment == null || !mounted) return;
    await ref.read(adminMutationProvider(widget.staffId).notifier).save(
      '/approval/requests/$selected/sign',
      {'h_id': widget.staffId, 'approve': approve, 'comment': comment},
    );
  }
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
