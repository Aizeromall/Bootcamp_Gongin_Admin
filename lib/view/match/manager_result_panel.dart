import '../shared/async_screen_state.dart';

// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 실력매칭·팀매칭 결과를 목록과 점수판·회원별 기록 표로 표시합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../model/manager_result_model.dart';
import '../../vm/manager_result_notifier.dart';
import '../../vm/headquarters_notifier.dart';
import '../../vm/manager_schedule_notifier.dart';
import '../shared/admin_split_view.dart';
import '../shared/admin_style.dart';
import '../headquarters/admin_components.dart';

class ManagerResultsPanel extends ConsumerStatefulWidget {
  const ManagerResultsPanel({
    super.key,
    required this.managerId,
    required this.kind,
  });
  final String managerId, kind;
  @override
  ConsumerState<ManagerResultsPanel> createState() =>
      _ManagerResultsPanelState();
}

class _ManagerResultsPanelState extends ConsumerState<ManagerResultsPanel>
    with AsyncScreenState<ManagerResultsPanel> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {
    'sport': 'all',
    'showCancelled': false,
    'selectedDay': null,
    'selected': null,
  };
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  String get sport => screenValue<String>('sport');
  set sport(String value) => setScreenValue('sport', value);
  bool get showCancelled => screenValue<bool>('showCancelled');
  set showCancelled(bool value) => setScreenValue('showCancelled', value);
  DateTime? get selectedDay => screenValue<DateTime?>('selectedDay');
  set selectedDay(DateTime? value) => setScreenValue('selectedDay', value);
  String? get dateFilter => managerGameDate(selectedDay);
  String? get selected => screenValue<String?>('selected');
  set selected(String? value) => setScreenValue('selected', value);
  @override
  void didUpdateWidget(covariant ManagerResultsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind ||
        oldWidget.managerId != widget.managerId) {
      resetScreenScope();
    }
  }

  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 날짜 전환 시 이전 경기 선택을 해제하고 결과·취소 탭에 같은 경기일 필터를 적용합니다.
  void changeDay(DateTime? value) => updateScreen(() {
    selectedDay = value == null
        ? null
        : DateTime(value.year, value.month, value.day);
    selected = null;
  });

  Widget error(Object value, VoidCallback retry) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(adminError(value)),
        TextButton(onPressed: retry, child: const Text('다시 시도')),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    watchScreen();
    final query = (
      managerId: widget.managerId,
      kind: widget.kind,
      sport: sport,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('경기일'),
              IconButton(
                tooltip: '이전 경기일',
                onPressed:
                    selectedDay == null || !selectedDay!.isAfter(DateTime(2000))
                    ? null
                    : () => changeDay(
                        selectedDay!.subtract(const Duration(days: 1)),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              OutlinedButton.icon(
                key: const ValueKey('result-date-picker'),
                icon: const Icon(Icons.calendar_month),
                label: Text(dateFilter ?? '날짜 선택'),
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate:
                        selectedDay ??
                        ref.read(managerTodayProvider).requireValue,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100, 12, 31),
                  );
                  if (mounted && value != null) {
                    changeDay(value);
                  }
                },
              ),
              IconButton(
                tooltip: '다음 경기일',
                onPressed:
                    selectedDay == null ||
                        !selectedDay!.isBefore(DateTime(2100, 12, 31))
                    ? null
                    : () =>
                          changeDay(selectedDay!.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: () =>
                    changeDay(ref.read(managerTodayProvider).requireValue),
                child: const Text('오늘'),
              ),
              TextButton(
                onPressed: selectedDay == null ? null : () => changeDay(null),
                child: const Text('전체 기록'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final option in managerSports.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      backgroundColor: Colors.white,
                      selectedColor: AdminStyle.ink,
                      side: BorderSide(
                        color: sport == option.key
                            ? AdminStyle.ink
                            : AdminStyle.line,
                      ),
                      labelStyle: TextStyle(
                        color: sport == option.key
                            ? Colors.white
                            : AdminStyle.text,
                        fontWeight: sport == option.key
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      label: Text(option.value),
                      selected: sport == option.key,
                      onSelected: (_) => updateScreen(() {
                        sport = option.key;
                        selected = null;
                      }),
                    ),
                  ),
                IconButton(
                  tooltip: showCancelled ? '취소 내역 새로고침' : '결과 새로고침',
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    ref.invalidate(managerResultsProvider(query));
                    ref.invalidate(managerResultDetailProvider);
                    ref.invalidate(managerCancelledResultsProvider(query));
                  },
                ),
              ],
            ),
          ),
        ),
        // 수정 일 : 2026-10-30 / 작업자 : 양태건
        // 기존 결과 페이지에서 유형별 예약 취소 목록을 전환합니다.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('경기 결과'),
                icon: Icon(Icons.scoreboard_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('취소 내역'),
                icon: Icon(Icons.cancel_outlined),
              ),
            ],
            selected: {showCancelled},
            onSelectionChanged: (values) => updateScreen(() {
              showCancelled = values.single;
              selected = null;
            }),
          ),
        ),
        Expanded(
          child: showCancelled
              ? ManagerCancelledResults(query: query, dateFilter: dateFilter)
              : ref
                    .watch(managerResultsProvider(query))
                    .when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (value, _) => error(
                        value,
                        () => ref.invalidate(managerResultsProvider(query)),
                      ),
                      data: (allRows) {
                        final rows = dateFilter == null
                            ? allRows
                            : allRows
                                  .where(
                                    (row) =>
                                        managerGameDate(row.data['date']) ==
                                        dateFilter,
                                  )
                                  .toList();
                        if (rows.isEmpty) {
                          return Center(
                            child: Text(
                              dateFilter == null
                                  ? '등록된 경기 결과가 없습니다.'
                                  : '선택한 경기일의 결과가 없습니다.',
                            ),
                          );
                        }
                        final code =
                            selected ??
                            (MediaQuery.sizeOf(context).width >= 1062
                                ? rows.first.code
                                : null);
                        return AdminSplitView(
                          selected: code != null,
                          onBack: () => updateScreen(() => selected = null),
                          list: ListView.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: AdminStyle.line,
                            ),
                            itemBuilder: (_, index) {
                              final row = rows[index];
                              return Material(
                                color: row.code == code
                                    ? AdminStyle.selected
                                    : Colors.white,
                                child: ListTile(
                                  key: ValueKey('result:${row.code}'),
                                  selected: row.code == code,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 18,
                                  ),
                                  title: Text(
                                    row.ground,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${row.date} ${row.time}\n${row.home} ${row.score} ${row.away}',
                                  ),
                                  isThreeLine: true,
                                  trailing: adminBadge('종료'),
                                  onTap: () =>
                                      updateScreen(() => selected = row.code),
                                ),
                              );
                            },
                          ),
                          detail: code == null
                              ? const Center(
                                  child: Text('경기를 선택하면 결과를 확인할 수 있습니다.'),
                                )
                              : ref
                                    .watch(
                                      managerResultDetailProvider((
                                        managerId: widget.managerId,
                                        code: code,
                                      )),
                                    )
                                    .when(
                                      loading: () => const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                      error: (value, _) => error(
                                        value,
                                        () => ref.invalidate(
                                          managerResultDetailProvider((
                                            managerId: widget.managerId,
                                            code: code,
                                          )),
                                        ),
                                      ),
                                      data: (row) =>
                                          ManagerResultDetails(result: row),
                                    ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 취소된 예약의 구장·시간대·사유와 실제 예약 회원을 기존 목록/상세 배치에 표시합니다.
class ManagerCancelledResults extends ConsumerStatefulWidget {
  const ManagerCancelledResults({
    super.key,
    required this.query,
    this.dateFilter,
  });
  final ManagerResultQuery query;
  final String? dateFilter;
  @override
  ConsumerState<ManagerCancelledResults> createState() =>
      _ManagerCancelledResultsState();
}

class _ManagerCancelledResultsState
    extends ConsumerState<ManagerCancelledResults>
    with AsyncScreenState<ManagerCancelledResults> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {'selected': null};
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  String? get selected => screenValue<String?>('selected');
  set selected(String? value) => setScreenValue('selected', value);
  @override
  void didUpdateWidget(covariant ManagerCancelledResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query ||
        oldWidget.dateFilter != widget.dateFilter) {
      resetScreenScope();
    }
  }

  @override
  Widget build(BuildContext context) {
    watchScreen();
    return ref
        .watch(managerCancelledResultsProvider(widget.query))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(adminError(error)),
                TextButton(
                  onPressed: () => ref.invalidate(
                    managerCancelledResultsProvider(widget.query),
                  ),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
          data: (allRows) {
            final rows = widget.dateFilter == null
                ? allRows
                : allRows
                      .where(
                        (row) => managerGameDate(row.date) == widget.dateFilter,
                      )
                      .toList();
            final label = widget.query.kind == 'team' ? '팀매칭' : '실력매칭';
            if (rows.isEmpty) {
              return Center(
                child: Text(
                  widget.dateFilter == null
                      ? '취소된 $label이 없습니다.'
                      : '선택한 경기일에 취소된 $label이 없습니다.',
                ),
              );
            }
            final row =
                rows.where((r) => r.identity == selected).firstOrNull ??
                (MediaQuery.sizeOf(context).width >= 1062 ? rows.first : null);
            return AdminSplitView(
              selected: row != null,
              onBack: () => updateScreen(() => selected = null),
              list: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AdminStyle.line),
                itemBuilder: (_, index) {
                  final item = rows[index];
                  return Material(
                    color: row?.identity == item.identity
                        ? AdminStyle.selected
                        : Colors.white,
                    child: ListTile(
                      key: ValueKey('cancelled:${item.identity}'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      title: Text(
                        item.ground,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${item.date} · ${item.start}\n${item.reasonName} · ${item.count ?? '—'}건',
                      ),
                      trailing: adminBadge('취소', alert: true),
                      onTap: () => updateScreen(() => selected = item.identity),
                    ),
                  );
                },
              ),
              detail: row == null
                  ? const Center(child: Text('취소 경기를 선택하면 내역을 확인할 수 있습니다.'))
                  : ListView(
                      padding: const EdgeInsets.all(22),
                      children: [
                        AdminCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: adminTitle('$label 취소 내역')),
                                  adminBadge('취소', alert: true),
                                ],
                              ),
                              const SizedBox(height: 18),
                              adminFields({
                                '구장': row.ground,
                                '경기 일시':
                                    '${row.date} · ${row.start} ~ ${row.end}',
                                '취소 사유': row.reasonName,
                                '취소 일시': row.cancelDate.replaceAll('T', ' '),
                                '취소 예약': row.count == null
                                    ? null
                                    : '${row.count}건',
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        AdminCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              adminTitle('취소 예약 회원'),
                              const SizedBox(height: 12),
                              if (row.members.isEmpty)
                                const Text('예약 회원 정보가 없습니다.'),
                              for (final member in row.members)
                                // 수정 일 : 2026-10-30 / 작업자 : 양태건
                                // 저장된 노쇼 차감 이력을 표시하고 없는 기록을 -30으로 만들지 않습니다.
                                ListTile(
                                  key: ValueKey(
                                    'cancel-member:${member['r_seq']}',
                                  ),
                                  title: Text(adminText(member['name'])),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '현재 소속팀 · ${adminText(member['current_team'])}',
                                      ),
                                      Text(
                                        member['attendance'] == null
                                            ? '출석 미확인'
                                            : member['attendance'] == true
                                            ? '출석'
                                            : '결석',
                                      ),
                                      if (row.reason == 3 &&
                                          member['attendance'] == false) ...[
                                        Text(
                                          member['rating_change'] == null
                                              ? '패널티 기록 없음'
                                              : '${member['penalty_applied'] == true ? '노쇼 패널티' : '점수 변동'} ${signedRating(member['rating_change'])}점',
                                          style: TextStyle(
                                            color:
                                                member['penalty_applied'] ==
                                                    true
                                                ? AdminStyle.red
                                                : AdminStyle.muted,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (member['rating_before'] != null &&
                                            member['rating_after'] != null)
                                          Text(
                                            '${member['rating_before']}점 → ${member['rating_after']}점',
                                          ),
                                      ] else
                                        Text(
                                          row.reason == 3 &&
                                                  member['attendance'] == null
                                              ? '패널티 기록 없음'
                                              : '패널티 없음',
                                        ),
                                    ],
                                  ),
                                  trailing: Text(
                                    '예약 ${adminText(member['r_seq'])}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            );
          },
        );
  }
}

class ManagerResultDetails extends StatelessWidget {
  const ManagerResultDetails({super.key, required this.result});
  final ManagerResult result;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      AdminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: adminTitle('경기 결과')),
                Text(
                  '기록 · ${adminText(result.data['manager_name'])}',
                  style: const TextStyle(color: AdminStyle.muted),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 20,
              runSpacing: 10,
              children: [
                Text(
                  result.home,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  result.score,
                  style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    color: AdminStyle.ink,
                  ),
                ),
                Text(
                  result.away,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (result.data['raw_score'] != null)
              Text('원본 스코어: ${result.data['raw_score']}'),
            if (result.sides.isEmpty) const Text('저장된 회원별 경기 기록이 없습니다.'),
            for (final side in result.sides) ...[
              const SizedBox(height: 20),
              adminTitle(adminText(side['name'])),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 22,
                  columns: [
                    const DataColumn(label: Text('회원')),
                    const DataColumn(label: Text('현재 레벨')),
                    const DataColumn(label: Text('현재 점수')),
                    const DataColumn(label: Text('경기 반영')),
                    for (final column in result.columns)
                      DataColumn(label: Text(adminText(column['label']))),
                  ],
                  rows: [
                    for (final member in adminRows(side['members']))
                      DataRow(
                        cells: [
                          DataCell(
                            Text(
                              member['record_text'] == null
                                  ? adminText(member['name'])
                                  : '${adminText(member['name'])}\n기록 원문: ${member['record_text']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataCell(Text(adminText(member['current_tier']))),
                          DataCell(Text(adminText(member['current_rating']))),
                          DataCell(
                            Text(
                              signedRating(member['rating_change']),
                              style: TextStyle(
                                color:
                                    (adminInt(member['rating_change']) ?? 0) < 0
                                    ? AdminStyle.red
                                    : AdminStyle.blue,
                              ),
                            ),
                          ),
                          for (final column in result.columns)
                            DataCell(
                              Text(
                                adminText(
                                  adminDocument(member['stats'])[column['key']],
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              '현재 점수·레벨은 최신 값입니다. 과거 경기의 변동이 저장되지 않은 경우 ‘변동 기록 없음’으로 표시합니다.',
              style: TextStyle(color: AdminStyle.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      if (adminRows(result.data['team_summary']).isNotEmpty) teamSummary(),
    ],
  );
  Widget teamSummary() => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        adminTitle('팀별 경기 요약'),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final team in adminRows(result.data['team_summary']))
                SizedBox(
                  width: constraints.maxWidth >= 560
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: team['result'] == '패'
                          ? const Color(0xFFFFF3F4)
                          : const Color(0xFFF0FAF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: team['result'] == '패'
                            ? AdminStyle.red
                            : Colors.green,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        adminTitle(adminText(team['name'])),
                        const SizedBox(height: 10),
                        adminBadge(
                          '${adminText(team['result'])} · ${signedRating(team['rating_change'])}',
                          alert: team['result'] == '패',
                        ),
                        const SizedBox(height: 12),
                        adminFields({
                          '팀 스코어': team['score'],
                          '현재 팀 점수': team['current_rating'],
                        }),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            for (final column in result.columns)
                              Text(
                                '${column['label']} ${adminText(adminDocument(team['stats'])[column['key']])}',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
