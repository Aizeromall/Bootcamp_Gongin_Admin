// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 새 본사 팀 매칭 API와 역할별 취소 내역을 기존 매치 화면 안에서 제공합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../model/match_updates_model.dart';
import '../../vm/match_updates_notifier.dart';
import '../../vm/headquarters_notifier.dart';
import '../shared/admin_split_view.dart';
import '../match/manager_schedule_panel.dart';
import 'admin_components.dart';
import 'manager_work_panel.dart';

Widget _problem(Object error, VoidCallback retry) => Center(
  child: Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(adminError(error)),
        TextButton(onPressed: retry, child: const Text('다시 시도')),
      ],
    ),
  ),
);

class HeadquartersMatchWorkbench extends StatefulWidget {
  const HeadquartersMatchWorkbench({super.key, required this.staffId});
  final String staffId;
  @override
  State<HeadquartersMatchWorkbench> createState() =>
      _HeadquartersMatchWorkbenchState();
}

class _HeadquartersMatchWorkbenchState
    extends State<HeadquartersMatchWorkbench> {
  String tab = 'social';
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'social', label: Text('매니저별 예약')),
              ButtonSegment(value: 'team', label: Text('팀 대 팀 매칭')),
              ButtonSegment(value: 'cancel', label: Text('취소 경기')),
            ],
            selected: {tab},
            onSelectionChanged: (v) => setState(() => tab = v.first),
          ),
        ),
      ),
      Expanded(
        child: switch (tab) {
          'team' => TeamMatchPanel(staffId: widget.staffId),
          'cancel' => CancelledMatchPanel(staffId: widget.staffId),
          _ => ManagerWorkPanel(staffId: widget.staffId),
        },
      ),
    ],
  );
}

class ManagerHistoryWorkbench extends StatefulWidget {
  const ManagerHistoryWorkbench({super.key, required this.managerId});
  final String managerId;
  @override
  State<ManagerHistoryWorkbench> createState() =>
      _ManagerHistoryWorkbenchState();
}

class _ManagerHistoryWorkbenchState extends State<ManagerHistoryWorkbench> {
  // 수정 일 : 2026-10-29 / 작업자 : 양태건
  // 내 매치의 통합 목록을 지난 매치로 이동하고 완료 기록·취소 내역을 유지합니다.
  String tab = 'completed';
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'completed', label: Text('완료 매치')),
              ButtonSegment(value: 'cancelled', label: Text('담당 구장 취소')),
            ],
            selected: {tab},
            onSelectionChanged: (value) => setState(() => tab = value.single),
          ),
        ),
      ),
      Expanded(
        child: switch (tab) {
          'cancelled' => CancelledMatchPanel(
            staffId: widget.managerId,
            managerId: widget.managerId,
          ),
          _ => ManagerSchedulePanel(managerId: widget.managerId, history: true),
        },
      ),
    ],
  );
}

class TeamMatchPanel extends ConsumerStatefulWidget {
  const TeamMatchPanel({super.key, required this.staffId});
  final String staffId;
  @override
  ConsumerState<TeamMatchPanel> createState() => _TeamMatchPanelState();
}

class _TeamMatchPanelState extends ConsumerState<TeamMatchPanel> {
  String keyword = '';
  String? status;
  int? selected;
  @override
  Widget build(BuildContext context) {
    final query = (staffId: widget.staffId, status: status, keyword: keyword);
    final list = ref.watch(teamMatchesProvider(query));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 250,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: '홈 · 원정 팀 이름 검색',
                    prefixIcon: Icon(Icons.search),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (v) => setState(() {
                    keyword = v.trim();
                    selected = null;
                  }),
                ),
              ),
              DropdownButton<String>(
                value: status ?? 'all',
                items: [
                  for (final e in const {
                    'all': '전체 상태',
                    'scheduled': '경기 예정',
                    'waiting_result': '결과 대기',
                    'finished': '경기 종료',
                  }.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() {
                  status = v == 'all' ? null : v;
                  selected = null;
                }),
              ),
              IconButton(
                tooltip: '팀 매칭 새로고침',
                onPressed: () {
                  ref.invalidate(teamMatchesProvider(query));
                  if (selected != null) {
                    ref.invalidate(
                      teamMatchProvider((
                        staffId: widget.staffId,
                        code: selected!,
                      )),
                    );
                  }
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) =>
                _problem(e, () => ref.invalidate(teamMatchesProvider(query))),
            data: (rows) {
              if (rows.isEmpty) {
                return const Center(child: Text('조회된 팀 매칭이 없습니다.'));
              }
              return AdminSplitView(
                selected: selected != null,
                onBack: () => setState(() => selected = null),
                list: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('전체 ${rows.length}경기'),
                    const SizedBox(height: 12),
                    for (final row in rows)
                      AdminCard(
                        child: ListTile(
                          key: ValueKey('team-match:${row.code}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${row.home.name} vs ${row.away.name}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${row.start.replaceFirst('T', ' ')}\n${row.ground} · ${row.score}',
                          ),
                          isThreeLine: true,
                          trailing: adminBadge(row.statusName),
                          onTap: () => setState(() => selected = row.code),
                        ),
                      ),
                  ],
                ),
                detail: selected == null
                    ? const Center(child: Text('팀 매칭을 선택해 결과를 확인하세요.'))
                    : ref
                          .watch(
                            teamMatchProvider((
                              staffId: widget.staffId,
                              code: selected!,
                            )),
                          )
                          .when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (e, s) => _problem(
                              e,
                              () => ref.invalidate(
                                teamMatchProvider((
                                  staffId: widget.staffId,
                                  code: selected!,
                                )),
                              ),
                            ),
                            data: (match) => ListView(
                              padding: const EdgeInsets.all(22),
                              children: [
                                AdminCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      adminTitle(
                                        '${match.home.name} vs ${match.away.name}',
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        match.score,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      adminFields({
                                        '상태': match.statusName,
                                        '시작': match.start,
                                        '종료': match.end,
                                        '구장': match.ground,
                                        '담당 매니저': match.manager,
                                        '경기 인원': match.capacity,
                                        '결과 등록일': match.resultDate,
                                      }),
                                    ],
                                  ),
                                ),
                                for (final team in [match.home, match.away])
                                  AdminCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        adminTitle(team.name),
                                        adminFields({
                                          '현재 팀장': team.captain,
                                          '연락처': team.phone,
                                          '팀 등급': team.grade,
                                          '팀원 수': team.members,
                                          '전적':
                                              '${adminText(team.wins)}승 ${adminText(team.draws)}무 ${adminText(team.losses)}패',
                                          '승률': team.winRate == null
                                              ? '기록 없음'
                                              : '${team.winRate}%',
                                        }),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class CancelledMatchPanel extends ConsumerStatefulWidget {
  const CancelledMatchPanel({super.key, required this.staffId, this.managerId});
  final String staffId;
  final String? managerId;
  @override
  ConsumerState<CancelledMatchPanel> createState() =>
      _CancelledMatchPanelState();
}

class _CancelledMatchPanelState extends ConsumerState<CancelledMatchPanel> {
  int? reason;
  CancelledMatch? selected;
  @override
  Widget build(BuildContext context) {
    final query = (
      staffId: widget.staffId,
      managerId: widget.managerId,
      reason: reason,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<int>(
                  value: reason ?? 0,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('전체 취소 사유')),
                    for (final e in cancellationReasons.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() {
                    reason = v == 0 ? null : v;
                    selected = null;
                  }),
                ),
              ),
              IconButton(
                tooltip: '취소 내역 새로고침',
                onPressed: () {
                  selected = null;
                  ref.invalidate(cancelledMatchesProvider(query));
                  setState(() {});
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: ref
              .watch(cancelledMatchesProvider(query))
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => _problem(
                  e,
                  () => ref.invalidate(cancelledMatchesProvider(query)),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return const Center(child: Text('조회된 취소 경기가 없습니다.'));
                  }
                  return AdminSplitView(
                    selected: selected != null,
                    onBack: () => setState(() => selected = null),
                    list: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final row in rows)
                          AdminCard(
                            child: ListTile(
                              key: ValueKey('cancelled:${row.identity}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(row.ground),
                              subtitle: Text(
                                '${row.date} · ${row.start}\n${row.reasonName} · 예약 ${adminText(row.count)}건',
                              ),
                              isThreeLine: true,
                              onTap: () => setState(() => selected = row),
                            ),
                          ),
                      ],
                    ),
                    detail: selected == null
                        ? const Center(child: Text('취소 경기를 선택해 내역을 확인하세요.'))
                        : _details(selected!),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _details(CancelledMatch row) {
    final summary = AdminCard(
      child: adminFields({
        '구장': row.ground,
        '경기일': row.date,
        '시작': row.start,
        '종료': row.end,
        '취소 사유': row.reasonName,
        '취소 예약 수': row.count,
        '구장 정원': row.capacity,
        '취소일': row.cancelDate,
      }),
    );
    if (widget.managerId != null) {
      return ListView(padding: const EdgeInsets.all(22), children: [summary]);
    }
    final key = (staffId: widget.staffId, match: row);
    return ref
        .watch(cancelledDetailProvider(key))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) =>
              _problem(e, () => ref.invalidate(cancelledDetailProvider(key))),
          data: (data) => ListView(
            padding: const EdgeInsets.all(22),
            children: [
              summary,
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    adminTitle('취소 예약자'),
                    for (final member in adminRows(data['members']))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: adminFields({
                          '회원': member['c_name'],
                          '연락처': member['c_phone'],
                          '출석': member['attendance'] == null
                              ? '확인 전'
                              : member['attendance'] == true
                              ? '출석'
                              : '결석',
                          '결제 기록': member['is_refunded'] == true
                              ? '정리됨'
                              : '확인 필요',
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
  }
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
