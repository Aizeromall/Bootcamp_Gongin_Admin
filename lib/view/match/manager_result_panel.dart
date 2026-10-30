// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 실력매칭·팀매칭 결과를 목록과 점수판·회원별 기록 표로 표시합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../model/manager_result_model.dart';
import '../../vm/manager_result_notifier.dart';
import '../../vm/headquarters_notifier.dart';
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

class _ManagerResultsPanelState extends ConsumerState<ManagerResultsPanel> {
  String sport = 'all';
  String? selected;
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
    final query = (
      managerId: widget.managerId,
      kind: widget.kind,
      sport: sport,
    );
    return Column(
      children: [
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
                      onSelected: (_) => setState(() {
                        sport = option.key;
                        selected = null;
                      }),
                    ),
                  ),
                IconButton(
                  tooltip: '결과 새로고침',
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    ref.invalidate(managerResultsProvider(query));
                    ref.invalidate(managerResultDetailProvider);
                  },
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ref
              .watch(managerResultsProvider(query))
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (value, _) => error(
                  value,
                  () => ref.invalidate(managerResultsProvider(query)),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return const Center(child: Text('등록된 경기 결과가 없습니다.'));
                  }
                  final code =
                      selected ??
                      (MediaQuery.sizeOf(context).width >= 1062
                          ? rows.first.code
                          : null);
                  return AdminSplitView(
                    selected: code != null,
                    onBack: () => setState(() => selected = null),
                    list: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AdminStyle.line),
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
                            onTap: () => setState(() => selected = row.code),
                          ),
                        );
                      },
                    ),
                    detail: code == null
                        ? const Center(child: Text('경기를 선택하면 결과를 확인할 수 있습니다.'))
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
