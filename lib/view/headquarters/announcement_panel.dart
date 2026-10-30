import '../shared/async_screen_state.dart';

// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 본사 공지는 서버의 본사 대상 필터·페이지 계약을 유지합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../service/headquarters_service.dart';
import '../../vm/headquarters_notifier.dart';
import 'admin_components.dart';
import 'banner_editor.dart';
import '../../vm/banner_notifier.dart';
import '../../service/operations_api.dart';

class AnnouncementPanel extends ConsumerStatefulWidget {
  const AnnouncementPanel({
    super.key,
    required this.staffId,
    this.manager = false,
  });
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 매니저는 매니저 대상 조회 API만 사용하며 작성 기능을 제공하지 않습니다.
  final bool manager;
  final String staffId;
  @override
  ConsumerState<AnnouncementPanel> createState() => _AnnouncementPanelState();
}

class _AnnouncementPanelState extends ConsumerState<AnnouncementPanel>
    with AsyncScreenState<AnnouncementPanel> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {
    'keyword': '',
    'category': null,
    'offset': 0,
  };
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  String get keyword => screenValue<String>('keyword');
  set keyword(String value) => setScreenValue('keyword', value);
  String? get category => screenValue<String?>('category');
  set category(String? value) => setScreenValue('category', value);
  int get offset => screenValue<int>('offset');
  set offset(int value) => setScreenValue('offset', value);
  String get listPath =>
      adminPath(widget.manager ? '/announce/manager' : '/announce/admin', {
        'keyword': keyword,
        'a_classify': category,
        'limit': '20',
        'offset': '$offset',
      });
  @override
  Widget build(BuildContext context) {
    watchScreen();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: '제목 · 내용 검색',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (v) => updateScreen(() {
                    keyword = v.trim();
                    offset = 0;
                  }),
                ),
              ),
              DropdownButton<String>(
                value: category ?? '전체',
                items: [
                  for (final v in ['전체', '이벤트', '운영', '정책', '점검', '공지'])
                    DropdownMenuItem(value: v, child: Text(v)),
                ],
                onChanged: (v) => updateScreen(() {
                  category = v == '전체' ? null : v;
                  offset = 0;
                }),
              ),
              if (!widget.manager)
                FilledButton(
                  onPressed: () =>
                      showAnnouncementWriter(context, widget.staffId),
                  child: const Text('+ 공지 작성'),
                ),
              IconButton(
                tooltip: '새로고침',
                onPressed: () {
                  ref.invalidate(
                    adminDataProvider((
                      staffId: widget.staffId,
                      path: listPath,
                    )),
                  );
                  ref.invalidate(operationsDataProvider(listPath));
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: AdminData(
            staffId: widget.staffId,
            path: listPath,
            builder: (p) => ListView(
              padding: const EdgeInsets.all(18),
              children: [
                if (p.rows.isEmpty) const Text('조회된 공지가 없습니다.'),
                for (final row in p.rows)
                  InkWell(
                    onTap: () => showAnnouncement(context, row),
                    child: AdminCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          adminBadge(adminText(row['a_classify'])),
                          const SizedBox(height: 10),
                          adminTitle(adminText(row['a_title'])),
                          const SizedBox(height: 8),
                          Text(
                            '${adminText(row['h_name'])} · ${adminText(row['a_date'])}',
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: offset > 0
                          ? () => updateScreen(() => offset -= 20)
                          : null,
                      child: const Text('이전'),
                    ),
                    Text(
                      '${offset ~/ 20 + 1}페이지 · 전체 ${p.number('total') ?? '—'}건',
                    ),
                    TextButton(
                      onPressed:
                          offset + p.rows.length < (p.number('total') ?? 0)
                          ? () => updateScreen(() => offset += 20)
                          : null,
                      child: const Text('다음'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showAnnouncement(BuildContext context, AdminRow row) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(adminText(row['a_title'])),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: adminFields({
              '분류': row['a_classify'],
              '작성자': row['h_name'],
              '작성일': row['a_date'],
              '대상': (row['a_target'] as List? ?? []).join(' · '),
              '내용': row['a_detail'],
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
Future<void> showAnnouncementWriter(BuildContext context, String staffId) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AnnouncementWriter(staffId: staffId),
    );

class _AnnouncementWriter extends ConsumerStatefulWidget {
  const _AnnouncementWriter({required this.staffId});
  final String staffId;
  @override
  ConsumerState<_AnnouncementWriter> createState() =>
      _AnnouncementWriterState();
}

class _AnnouncementWriterState extends ConsumerState<_AnnouncementWriter>
    with AsyncScreenState<_AnnouncementWriter> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {
    'category': '공지',
    'targets': <String>{'본사'},
    'showBanners': false,
  };
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
    'targets': Set<String>.from(values['targets'] as Set),
  };

  late final title = screenTextController('title'),
      body = screenTextController('body');
  final form = GlobalKey<FormState>();
  String get category => screenValue<String>('category');
  set category(String value) => setScreenValue('category', value);
  Set<String> get targets => screenValue<Set<String>>('targets');
  set targets(Set<String> value) => setScreenValue('targets', value);
  bool get showBanners => screenValue<bool>('showBanners');
  set showBanners(bool value) => setScreenValue('showBanners', value);
  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    watchScreen();
    final mutation = ref.watch(adminMutationProvider(widget.staffId));
    // 수정 일 : 2026-10-28 / 작업자 : 양태건
    // 업로드 중 공지 등록·닫기를 막아 저장 동작이 서로 겹치지 않게 합니다.
    final bannerBusy = ref
        .watch(bannerMutationProvider(widget.staffId))
        .isLoading;
    final busy = mutation.isLoading || bannerBusy;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('공지 작성'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('이 목록에는 본사를 대상으로 지정한 공지만 표시됩니다.'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: '분류'),
                    items: [
                      for (final c in ['이벤트', '운영', '정책', '점검', '공지'])
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => updateScreen(() => category = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: title,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: '제목'),
                    validator: (v) => v!.trim().isEmpty ? '제목을 입력해 주세요.' : null,
                  ),
                  TextFormField(
                    controller: body,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: 16000,
                    decoration: const InputDecoration(labelText: '내용'),
                    validator: (v) => v!.trim().isEmpty ? '내용을 입력해 주세요.' : null,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => updateScreen(() => showBanners = !showBanners),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(showBanners ? '배너 설정 접기' : '배너 이미지 선택·등록'),
                  ),
                  if (showBanners)
                    BannerEditor(
                      staffId: widget.staffId,
                      disabled: mutation.isLoading,
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    children: [
                      for (final v in ['사용자', '매니저', '본사'])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(v),
                            selected: targets.contains(v),
                            onSelected: busy
                                ? null
                                : (s) => updateScreen(
                                    () =>
                                        s ? targets.add(v) : targets.remove(v),
                                  ),
                          ),
                        ),
                    ],
                  ),
                  if (targets.isEmpty) const Text('대상을 하나 이상 선택해 주세요.'),
                  if (mutation.hasError)
                    Text(
                      adminError(mutation.error!),
                      style: const TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!form.currentState!.validate() || targets.isEmpty) {
                      return;
                    }
                    final saved = await ref
                        .read(adminMutationProvider(widget.staffId).notifier)
                        .save('/announce/write', {
                          'h_id': widget.staffId,
                          'a_classify': category,
                          'a_title': title.text.trim(),
                          'a_detail': body.text.trim(),
                          'a_target': targets.toList(),
                        });
                    if (!context.mounted) return;
                    if (saved) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('공지를 등록했습니다.')),
                      );
                    }
                  },
            child: Text(mutation.isLoading ? '등록 중…' : '공지 등록'),
          ),
        ],
      ),
    );
  }
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
