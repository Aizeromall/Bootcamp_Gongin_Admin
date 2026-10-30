import '../shared/async_screen_state.dart';

// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 본사 신고 업무를 상태·종목 필터와 목록/상세 분할 화면으로 제공합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/report_model.dart';
import '../../vm/report_notifier.dart';

const _ink = Color(0xFF17233B);
const _muted = Color(0xFF788399);
const _canvas = Color(0xFFF4F6FB);
const _line = Color(0xFFE4E8F1);
const _blue = Color(0xFF1976F3);

String _date(String? value) =>
    value == null ? '일시 미기록' : value.replaceFirst('T', ' ').split('.').first;
Color _statusColor(String status) => switch (status) {
  '접수' => _blue,
  '심의중' => const Color(0xFFAC6A0C),
  '처리완료' => const Color(0xFF168351),
  _ => _muted,
};
Widget _badge(String status) {
  final color = _statusColor(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      status,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key, required this.staffId});
  final String staffId;
  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage>
    with AsyncScreenState<ReportPage> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {'selectedId': null};
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  int? get selectedId => screenValue<int?>('selectedId');
  set selectedId(int? value) => setScreenValue('selectedId', value);
  @override
  Widget build(BuildContext context) {
    watchScreen();
    final filters = ref.watch(reportFilterProvider).requireValue;
    final query = (
      staffId: widget.staffId,
      state: filters.state,
      sport: filters.sport,
    );
    final result = ref.watch(reportListProvider(query));
    final collection = result.asData?.value;
    return ColoredBox(
      color: _canvas,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '신고 내역',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          '접수된 신고를 확인하고 심의를 진행하세요.',
                          style: TextStyle(color: _muted),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4E4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '처리 대기 ${collection?.pending ?? '—'}건',
                            style: const TextStyle(
                              color: Color(0xFFAA6915),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '신고 목록 새로고침',
                          onPressed: () {
                            ref.invalidate(reportListProvider(query));
                            ref.invalidate(reportDetailProvider);
                          },
                          icon: const Icon(Icons.refresh, color: _muted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final status in ['전체', '접수', '심의중', '처리완료', '기각'])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              '$status${collection?.statusCounts[status] == null ? '' : ' ${collection!.statusCounts[status]}'}',
                            ),
                            selected:
                                filters.state ==
                                (status == '전체' ? null : status),
                            selectedColor: _ink,
                            backgroundColor: Colors.white,
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(
                              color:
                                  filters.state ==
                                      (status == '전체' ? null : status)
                                  ? Colors.white
                                  : _muted,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) {
                              updateScreen(() => selectedId = null);
                              ref
                                  .read(reportFilterProvider.notifier)
                                  .selectState(status == '전체' ? null : status);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('전체 종목'),
                      selected: filters.sport == null,
                      onSelected: (_) {
                        updateScreen(() => selectedId = null);
                        ref
                            .read(reportFilterProvider.notifier)
                            .selectSport(null);
                      },
                    ),
                    for (final sport
                        in collection?.sports ?? <Map<String, dynamic>>[])
                      FilterChip(
                        label: Text(
                          '${sport['sport_name']}${reportInt(sport['count']) == null ? '' : ' ${sport['count']}'}',
                        ),
                        selected: filters.sport == sport['sport'],
                        onSelected: (_) {
                          updateScreen(() => selectedId = null);
                          ref
                              .read(reportFilterProvider.notifier)
                              .selectSport('${sport['sport']}');
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: result.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator(color: _blue)),
              error: (error, _) => _ReportError(
                message: reportErrorText(error),
                retry: () => ref.invalidate(reportListProvider(query)),
              ),
              data: (data) {
                if (data.reports.isEmpty) {
                  return const _ReportEmpty(
                    icon: Icons.fact_check_outlined,
                    title: '해당하는 신고가 없습니다.',
                    subtitle: '다른 처리 상태나 종목을 선택해 보세요.',
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 960;
                    final selected =
                        data.reports
                            .where((r) => r.id == selectedId)
                            .firstOrNull ??
                        (wide ? data.reports.first : null);
                    final list = _ReportList(
                      reports: data.reports,
                      total: data.total,
                      selectedId: selected?.id,
                      onSelected: (id) => updateScreen(() => selectedId = id),
                    );
                    if (!wide && selected == null) return list;
                    final detail = _ReportDetail(
                      key: ValueKey('${widget.staffId}:${selected!.id}'),
                      detailKey: (staffId: widget.staffId, id: selected.id),
                      onBack: wide
                          ? null
                          : () => updateScreen(() => selectedId = null),
                    );
                    return wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 340, child: list),
                              const VerticalDivider(width: 1, color: _line),
                              Expanded(child: detail),
                            ],
                          )
                        : detail;
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({
    required this.reports,
    required this.total,
    required this.selectedId,
    required this.onSelected,
  });
  final List<ReportRecord> reports;
  final int? total, selectedId;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: Column(
      children: [
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line)),
          ),
          child: Text(
            '신고 ${total ?? reports.length}건',
            style: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: reports.length,
            separatorBuilder: (_, _) => const Divider(height: 1, color: _line),
            itemBuilder: (context, index) {
              final report = reports[index];
              final selected = report.id == selectedId;
              return Material(
                color: selected ? const Color(0xFFEBF2FF) : Colors.white,
                child: InkWell(
                  onTap: () => onSelected(report.id),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: selected ? _blue : Colors.transparent,
                          width: 4,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '#${report.id.toString().padLeft(4, '0')}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            _badge(report.status),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          report.category,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${report.reporter} → ${report.target}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _ink),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${report.sportName} · ${_date(report.reportedAt)}',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _ReportDetail extends ConsumerWidget {
  const _ReportDetail({super.key, required this.detailKey, this.onBack});
  final ReportDetailKey detailKey;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(reportDetailProvider(detailKey));
    final review = ref.watch(reportReviewProvider(detailKey));
    return result.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: _blue)),
      error: (error, _) => Column(
        children: [
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('목록으로'),
              ),
            ),
          Expanded(
            child: _ReportError(
              message: reportErrorText(error),
              retry: () => ref.invalidate(reportDetailProvider(detailKey)),
            ),
          ),
        ],
      ),
      data: (report) => ListView(
        key: const ValueKey('report-detail-scroll'),
        padding: const EdgeInsets.all(24),
        children: [
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('목록으로'),
              ),
            ),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _badge(report.status),
                    const SizedBox(width: 8),
                    Text(
                      report.sportName,
                      style: const TextStyle(color: _muted),
                    ),
                    const Spacer(),
                    Text(
                      '#${report.id.toString().padLeft(4, '0')}',
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  report.category,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '접수일 ${_date(report.reportedAt)}',
                  style: const TextStyle(color: _muted),
                ),
                const Divider(height: 36, color: _line),
                Wrap(
                  spacing: 48,
                  runSpacing: 16,
                  children: [
                    _person('신고자', report.reporter, Icons.person_outline),
                    _person(
                      '피신고자',
                      report.target,
                      Icons.person_search_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
          _panel(
            title: '신고 내용',
            child: SelectableText(
              report.description ?? '등록된 상황 설명이 없습니다.',
              style: const TextStyle(color: _ink, height: 1.7, fontSize: 15),
            ),
          ),
          _panel(
            title: '관련 경기',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field('구장', report.ground),
                _field(
                  '경기 일시',
                  report.matchDate == null
                      ? null
                      : '${report.matchDate} ${report.matchTime ?? ''}',
                ),
                _field('담당 매니저', report.manager),
                if (report.matchCode != null) _field('경기 번호', report.matchCode),
              ],
            ),
          ),
          _panel(
            title: '첨부 자료 ${report.evidence.length}건',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (report.evidence.isEmpty)
                  const Text('첨부된 자료가 없습니다.', style: TextStyle(color: _muted)),
                for (var i = 0; i < report.evidence.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.attach_file, size: 18, color: _muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            report.evidence[i],
                            style: const TextStyle(color: _ink, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _panel(
            title: '피신고자 이력',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final items = [
                  _stat(
                    '누적 경고',
                    report.warnings == null ? '—' : '${report.warnings}회',
                    const Color(0xFFD04C3F),
                  ),
                  _stat(
                    '받은 신고',
                    report.receivedReports == null
                        ? '—'
                        : '${report.receivedReports}건',
                    _ink,
                  ),
                  _stat('계정 상태', report.accountState ?? '확인되지 않음', _ink),
                ];
                return constraints.maxWidth >= 460
                    ? Row(
                        children: [
                          for (final item in items) Expanded(child: item),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: items,
                      );
              },
            ),
          ),
          _panel(
            title: '처리 상태',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (report.reviewer != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '심의 담당자 · ${report.reviewer}',
                      style: const TextStyle(color: _ink),
                    ),
                  ),
                if (review.hasError)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      reportErrorText(review.error!),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (report.canStartReview) ...[
                  const Text(
                    '신고 내용과 첨부 자료를 확인한 후 심의를 시작하세요.',
                    style: TextStyle(color: _muted, height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: review.isLoading
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('심의를 시작할까요?'),
                                content: const Text(
                                  '로그인한 본사 직원이 심의 담당자로 등록됩니다.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('취소'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('심의 시작'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !context.mounted) return;
                            final success = await ref
                                .read(reportReviewProvider(detailKey).notifier)
                                .start();
                            if (success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('심의를 시작했습니다.')),
                              );
                            }
                          },
                    icon: review.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fact_check_outlined),
                    label: Text(review.isLoading ? '처리 중…' : '심의 시작'),
                  ),
                ] else
                  Text(
                    report.status == '심의중'
                        ? '심의가 진행 중인 신고입니다.'
                        : report.status == '처리완료'
                        ? '처리가 완료된 신고입니다.'
                        : '현재 상태에서는 심의를 시작할 수 없습니다.',
                    style: const TextStyle(color: _muted, height: 1.6),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _panel({String? title, required Widget child}) => Container(
  margin: const EdgeInsets.only(bottom: 20),
  padding: const EdgeInsets.all(24),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _line),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null) ...[
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 20),
      ],
      child,
    ],
  ),
);
Widget _field(String label, String? value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 7),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 90,
        child: Text(label, style: const TextStyle(color: _muted)),
      ),
      Expanded(
        child: SelectableText(
          value ?? '정보 없음',
          style: const TextStyle(color: _ink),
        ),
      ),
    ],
  ),
);
Widget _person(String label, String name, IconData icon) => ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 260),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(
        backgroundColor: _canvas,
        child: Icon(icon, color: _muted),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  ),
);
Widget _stat(String label, String value, Color color) => Container(
  margin: const EdgeInsets.all(4),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: _canvas,
    borderRadius: BorderRadius.circular(10),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
      const SizedBox(height: 10),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 21,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  ),
);

class _ReportError extends StatelessWidget {
  const _ReportError({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, color: _muted, size: 36),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: retry, child: const Text('다시 시도')),
        ],
      ),
    ),
  );
}

class _ReportEmpty extends StatelessWidget {
  const _ReportEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: _muted),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
        ],
      ),
    ),
  );
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
