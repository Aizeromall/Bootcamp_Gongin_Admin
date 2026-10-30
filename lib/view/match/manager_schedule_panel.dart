// 수정 일 : 2026-10-29 / 작업자 : 양태건
// 지난 매치의 통합 목록에서 담당 실력매칭·팀매칭과 경기 상세를 표시합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/manager_schedule_model.dart';
import '../../model/manager_result_model.dart';
import '../../model/match_updates_model.dart';
import '../../vm/manager_schedule_notifier.dart';
import '../../vm/manager_result_notifier.dart';
import '../../model/headquarters_model.dart';
import '../../vm/headquarters_notifier.dart';
import '../headquarters/admin_components.dart';
import '../shared/admin_style.dart';
import '../shared/admin_split_view.dart';
import '../../service/operations_api.dart';
import 'match_page.dart';

class ManagerSchedulePanel extends ConsumerStatefulWidget {
  const ManagerSchedulePanel({
    super.key,
    required this.managerId,
    this.history = false,
    this.showAllUpcoming = false,
    this.onCompleted,
  });
  final bool history;
  final bool showAllUpcoming;
  final VoidCallback? onCompleted;
  final String managerId;
  @override
  ConsumerState<ManagerSchedulePanel> createState() =>
      _ManagerSchedulePanelState();
}

class _ManagerSchedulePanelState extends ConsumerState<ManagerSchedulePanel> {
  late DateTime day;
  late bool allUpcoming;
  @override
  void initState() {
    super.initState();
    day = ref.read(managerTodayProvider);
    allUpcoming = widget.showAllUpcoming;
  }

  DateTime get today => ref.read(managerTodayProvider);
  DateTime get displayedDay =>
      !widget.history && day.isBefore(today) ? today : day;
  String? groundFilter, selected;
  String sport = 'all';
  String get date =>
      '${displayedDay.year.toString().padLeft(4, '0')}-${displayedDay.month.toString().padLeft(2, '0')}-${displayedDay.day.toString().padLeft(2, '0')}';
  // 수정 일 : 2026-10-29 / 작업자 : 양태건
  // 내 매치에서 과거 날짜를 선택하지 않으며 지난 매치는 기존 조회 범위를 유지합니다.
  void changeDay(DateTime value) => setState(() {
    allUpcoming = false;
    day = !widget.history && value.isBefore(today) ? today : value;
    groundFilter = null;
    selected = null;
  });
  String identity(ScheduleGround ground, ScheduleSlot slot) =>
      '${slot.date == null ? '' : '${slot.date}|'}${ground.code}|${slot.start}|${slot.teamCode}';
  void refreshMatches() {
    ref.invalidate(managerUpcomingProvider(widget.managerId));
    ref.invalidate(
      managerScheduleProvider((managerId: widget.managerId, date: date)),
    );
    ref.invalidate(operationsDataProvider('/match/operations'));
    ref.invalidate(
      managerMatchDayProvider((
        managerId: widget.managerId,
        date: date,
        history: widget.history,
      )),
    );
  }

  Widget problem(Object error, VoidCallback retry) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(adminError(error)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: retry, child: const Text('다시 시도')),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final query = (
      managerId: widget.managerId,
      date: date,
      history: widget.history,
    );
    final result = allUpcoming && !widget.history
        ? ref.watch(managerUpcomingProvider(widget.managerId))
        : ref.watch(managerMatchDayProvider(query));
    final kind = ref.watch(managerMatchKindProvider(widget.managerId));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: '이전 날짜',
                onPressed: !widget.history && !displayedDay.isAfter(today)
                    ? null
                    : () => changeDay(
                        displayedDay.subtract(const Duration(days: 1)),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(allUpcoming ? '오늘 이후 전체' : date),
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: displayedDay,
                    firstDate: widget.history ? DateTime(2020) : today,
                    lastDate: DateTime(2100),
                  );
                  if (!mounted || value == null) return;
                  changeDay(value);
                },
              ),
              IconButton(
                tooltip: '다음 날짜',
                onPressed: () =>
                    changeDay(displayedDay.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: () => changeDay(today),
                child: const Text('오늘'),
              ),
              if (widget.showAllUpcoming)
                TextButton(
                  onPressed: () => setState(() {
                    allUpcoming = true;
                    selected = null;
                  }),
                  child: const Text('오늘 이후 전체'),
                ),
              IconButton(
                tooltip: '담당 일정 새로고침',
                onPressed: () {
                  ref.invalidate(managerUpcomingProvider(widget.managerId));
                  ref.invalidate(managerMatchDayProvider(query));
                  ref.invalidate(
                    managerScheduleProvider((
                      managerId: widget.managerId,
                      date: date,
                    )),
                  );
                  ref.invalidate(operationsDataProvider('/match/operations'));
                  ref.invalidate(scheduledTeamMatchProvider);
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in const {
                ManagerMatchKind.all: '전체',
                ManagerMatchKind.pickup: '실력매칭',
                ManagerMatchKind.team: '팀매칭',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: kind == entry.key,
                  onSelected: (_) {
                    ref
                        .read(
                          managerMatchKindProvider(widget.managerId).notifier,
                        )
                        .select(entry.key);
                    setState(() => selected = null);
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: result.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => problem(error, refreshMatches),
            data: (schedule) {
              final entries = schedule.entries
                  .where(
                    (entry) =>
                        (groundFilter == null ||
                            groundFilter == entry.ground.code) &&
                        (sport == 'all' ||
                            normalizeManagerSport(entry.sport) == sport) &&
                        (kind == ManagerMatchKind.all ||
                            (kind == ManagerMatchKind.pickup &&
                                entry.slot.type == 'pickup') ||
                            (kind == ManagerMatchKind.team &&
                                entry.slot.type == 'team_match')),
                  )
                  .toList();
              final matching = entries.where(
                (entry) => identity(entry.ground, entry.slot) == selected,
              );
              final chosen = matching.isEmpty ? null : matching.first;
              final list = Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('$date:$groundFilter'),
                      initialValue: groundFilter ?? 'all',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '담당 구장'),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('전체 담당 구장'),
                        ),
                        for (final ground in schedule.grounds)
                          DropdownMenuItem(
                            value: ground.code,
                            child: Text(ground.name),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        groundFilter = value == 'all' ? null : value;
                        selected = null;
                      }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '담당 매치 ${entries.length}건',
                      style: const TextStyle(color: AdminStyle.muted),
                    ),
                  ),
                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text('선택한 조건에 해당하는 매치가 없습니다.'),
                            ),
                          )
                        : ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: AdminStyle.line,
                            ),
                            itemBuilder: (_, index) {
                              final entry = entries[index];
                              final slot = entry.slot;
                              return Material(
                                color: selected == identity(entry.ground, slot)
                                    ? AdminStyle.selected
                                    : Colors.white,
                                child: ListTile(
                                  key: ValueKey(
                                    'schedule:${identity(entry.ground, slot)}',
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  title: Text(
                                    slot.type == 'pickup'
                                        ? entry.ground.name
                                        : slot.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${slot.date ?? date} · ${slot.type == 'team_match' ? '팀매칭' : '실력매칭'} · ${slot.start} ~ ${slot.end}\n${entry.ground.name}',
                                  ),
                                  isThreeLine: true,
                                  trailing: Icon(
                                    slot.type == 'team_match'
                                        ? Icons.sports_soccer
                                        : Icons.schedule,
                                    color: AdminStyle.blue,
                                  ),
                                  onTap: () => setState(
                                    () =>
                                        selected = identity(entry.ground, slot),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
              return AdminSplitView(
                selected: chosen != null,
                onBack: () => setState(() => selected = null),
                list: list,
                detail: chosen == null
                    ? const Center(child: Text('매치를 선택하면 경기 정보를 확인할 수 있습니다.'))
                    : detail(chosen),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget detail(ManagerMatchEntry entry) {
    final ground = entry.ground;
    final slot = entry.slot;
    if (entry.operation != null) {
      return MatchWorkflowPage(
        key: ValueKey('embedded:${entry.operation!['r_seq']}'),
        match: entry.operation!,
        managerId: widget.managerId,
        embedded: true,
        onPublished: () {
          ref.invalidate(operationsDataProvider('/match/operations'));
          ref.invalidate(managerMatchDayProvider);
          ref.invalidate(managerUpcomingProvider(widget.managerId));
          widget.onCompleted?.call();
        },
      );
    }

    final summary = AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: adminTitle(ground.name)),
              adminBadge(slot.label),
            ],
          ),
          const SizedBox(height: 16),
          adminFields({
            '경기 일자': slot.date ?? date,
            '시간': '${slot.start} ~ ${slot.end}',
            '구장 정원': ground.capacity == null ? null : '${ground.capacity}명',
            if (slot.count != null) '실력매칭 예약': '${slot.count}명',
            if (slot.type == 'team_match') '대여 회원': slot.renter,
          }),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        summary,
        if (entry.team != null) _teamResult(entry.team!),
        if (entry.team != null && !widget.history)
          ref
              .watch(
                managerTeamRosterProvider((
                  managerId: widget.managerId,
                  code: entry.team!.code,
                )),
              )
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => problem(
                  error,
                  () => ref.invalidate(
                    managerTeamRosterProvider((
                      managerId: widget.managerId,
                      code: entry.team!.code,
                    )),
                  ),
                ),
                data: (data) => AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      adminTitle('현재 팀원 명단'),
                      for (final player in adminRows(data['members']))
                        ListTile(
                          title: Text(adminText(player['name'])),
                          subtitle: Text(
                            '${adminText(player['current_tier'])} · ${adminText(player['position'])} · ${adminText(player['team'])}',
                          ),
                          trailing: const Text('출석 확인 미지원'),
                        ),
                      const Text(
                        '현재 팀원 명단이며 출전·출석 확정 명단이 아닙니다. 팀 경기 출석과 실시간 진행 API가 없어 이 화면에서는 경기 시작을 처리할 수 없습니다.',
                        style: TextStyle(color: AdminStyle.muted),
                      ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }

  Widget _teamResult(TeamMatchRecord match) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AdminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            adminTitle('경기 결과'),
            const SizedBox(height: 20),
            Text(
              '${match.home.name}  vs  ${match.away.name}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              match.score,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: AdminStyle.ink,
              ),
            ),
            const SizedBox(height: 12),
            Center(child: adminBadge(match.statusName)),
          ],
        ),
      ),
      for (final team in [match.home, match.away])
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              adminTitle(team.name),
              const SizedBox(height: 10),
              adminFields({
                '현재 팀장': team.captain,
                '연락처': team.phone,
                '팀 등급': team.grade,
                '팀원 수': team.members,
                '승': team.wins,
                '무': team.draws,
                '패': team.losses,
                '승률': team.winRate == null ? '기록 없음' : '${team.winRate}%',
              }),
            ],
          ),
        ),
    ],
  );
}
// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
