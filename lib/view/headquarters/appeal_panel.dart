import '../shared/async_screen_state.dart';

// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 제재 조회와 이의신청 재심의 시작까지만 기존 API의 허용 동작을 연결합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../service/headquarters_service.dart';
import '../../vm/headquarters_notifier.dart';
import 'admin_components.dart';
import '../shared/admin_split_view.dart';

class AppealPanel extends ConsumerStatefulWidget {
  const AppealPanel({super.key, required this.staffId});
  final String staffId;
  @override
  ConsumerState<AppealPanel> createState() => _AppealPanelState();
}

class _AppealPanelState extends ConsumerState<AppealPanel>
    with AsyncScreenState<AppealPanel> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {
    'sanctions': false,
    'state': null,
    'sport': null,
    'selected': null,
  };
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  bool get sanctions => screenValue<bool>('sanctions');
  set sanctions(bool value) => setScreenValue('sanctions', value);
  String? get state => screenValue<String?>('state');
  set state(String? value) => setScreenValue('state', value);
  String? get sport => screenValue<String?>('sport');
  set sport(String? value) => setScreenValue('sport', value);
  int? get selected => screenValue<int?>('selected');
  set selected(int? value) => setScreenValue('selected', value);
  @override
  Widget build(BuildContext context) {
    watchScreen();
    final mutation = ref.watch(adminMutationProvider(widget.staffId));
    final path = adminPath(sanctions ? '/appeal/sanction' : '/appeal/list', {
      'sport': sport,
      if (sanctions) 'tag': state else 'state': state,
    });
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('이의신청')),
                  ButtonSegment(value: true, label: Text('제재 목록')),
                ],
                selected: {sanctions},
                onSelectionChanged: (v) => updateScreen(() {
                  sanctions = v.first;
                  state = null;
                  selected = null;
                }),
              ),
              DropdownButton<String>(
                value: state ?? '전체 상태',
                items: [
                  for (final v in [
                    '전체 상태',
                    if (sanctions) ...[
                      '유효',
                      '소멸',
                    ] else ...[
                      '접수',
                      '재심의 중',
                      '인용',
                      '기각',
                    ],
                  ])
                    DropdownMenuItem(value: v, child: Text(v)),
                ],
                onChanged: (v) => updateScreen(() {
                  state = v == '전체 상태' ? null : v;
                  selected = null;
                }),
              ),
              DropdownButton<String>(
                value: sport ?? '전체',
                items: [
                  for (final e in const {
                    '전체': '전체 종목',
                    'SOCCER': '축구',
                    'BASKETBALL': '농구',
                    'VOLLEYBALL': '배구',
                    'BASEBALL': '야구',
                    'ETC': '기타',
                  }.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => updateScreen(() {
                  sport = v == '전체' ? null : v;
                  selected = null;
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: AdminSplitView(
            selected: selected != null && !sanctions,
            onBack: () => updateScreen(() => selected = null),
            list: AdminData(
              staffId: widget.staffId,
              path: path,
              builder: (p) => ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Text(
                    '${sanctions ? '제재' : '이의신청'} ${p.number('total') ?? p.rows.length}건',
                  ),
                  const SizedBox(height: 12),
                  if (p.rows.isEmpty) const Text('조회된 내역이 없습니다.'),
                  for (final r in p.rows)
                    InkWell(
                      onTap: () => sanctions
                          ? _showSanction(context, r)
                          : updateScreen(() => selected = adminInt(r['a_seq'])),
                      child: AdminCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            adminBadge(
                              adminText(r[sanctions ? 'tag' : 'state_text']),
                              alert: !sanctions,
                            ),
                            const SizedBox(height: 10),
                            adminTitle(
                              sanctions
                                  ? '${adminText(r['member_name'])} · ${adminText(r['label'])}'
                                  : adminText(r['title']),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${adminText(r['sport_name'])} · ${adminText(r[sanctions ? 'cs_date' : 'a_date'])}',
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            detail: selected == null || sanctions
                ? const Center(child: Text('내역을 선택해 상세 정보를 확인하세요.'))
                : AdminData(
                    staffId: widget.staffId,
                    path: '/appeal/detail/$selected',
                    builder: (p) {
                      final r = p.data;
                      return ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () =>
                                  updateScreen(() => selected = null),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('이의신청 목록으로'),
                            ),
                          ),
                          AdminCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                adminTitle(adminText(r['title'])),
                                adminFields({
                                  '상태': r['state_text'],
                                  '신청자': r['member_name'],
                                  '신청일': r['a_date'],
                                  '사유': r['a_reason'],
                                  '증빙': (r['a_evidence'] as List? ?? []).join(
                                    '\n',
                                  ),
                                  '담당자': r['h_name'],
                                }),
                                if (r['sanction'] is Map)
                                  adminFields({
                                    '대상 제재': r['sanction']['label'],
                                    '제재 내용': r['sanction']['cs_detail'],
                                  }),
                                if (mutation.hasError)
                                  Text(
                                    adminError(mutation.error!),
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                if (r['can_start_review'] == true)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton(
                                      onPressed: mutation.isLoading
                                          ? null
                                          : () async {
                                              if (!await adminConfirm(
                                                context,
                                                '재심의 시작',
                                                '이 이의신청의 재심의를 시작할까요?',
                                              )) {
                                                return;
                                              }
                                              if (!mounted) return;
                                              await ref
                                                  .read(
                                                    adminMutationProvider(
                                                      widget.staffId,
                                                    ).notifier,
                                                  )
                                                  .save(
                                                    '/appeal/review/$selected',
                                                    {'h_id': widget.staffId},
                                                  );
                                            },
                                      child: Text(
                                        mutation.isLoading ? '처리 중…' : '재심의 시작',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  void _showSanction(BuildContext context, AdminRow r) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${adminText(r['member_name'])} · ${adminText(r['label'])}',
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: adminFields({
              '상태': r['tag'],
              '제재 내용': r['cs_detail'],
              '제재일': r['cs_date'],
              '소멸일': r['expire_date'],
              '처리자': r['h_name'],
              '이의신청 수': r['appeal_count'],
              '최근 이의신청 상태': r['appeal_state_text'],
            }),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
