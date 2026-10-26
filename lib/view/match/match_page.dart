// 작업자 : 양태건
// 수정일 : 2026-10-26
// [수정 시작] 예약별 입력 창을 경기별 출석·팀 설정·실시간 기록 흐름으로 변경합니다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../service/operations_api.dart';
import '../shared/records_view.dart';

const statLabels = {
  'goal': '골',
  'assist': '도움',
  'shot': '슈팅',
  'yellow': '경고',
  'red': '퇴장',
};
const bibColors = {
  'blue': Colors.blue,
  'grey': Colors.blueGrey,
  'red': Colors.red,
  'green': Colors.green,
  'orange': Colors.orange,
  'navy': Color(0xFF15213B),
};
String clockText(int seconds) =>
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

class MatchPage extends ConsumerWidget {
  const MatchPage({
    super.key,
    required this.managerId,
    this.history = false,
    this.onCompleted,
  });
  final String managerId;
  final bool history;
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) => RecordsView(
    path: '/match/operations',
    builder: (data) {
      final rows = (data['results'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .where((r) => (r['status'] == 'completed') == history)
          .toList();
      if (history) {
        rows.sort(
          (a, b) => '${b['r_date']} ${b['rs_time']}'.compareTo(
            '${a['r_date']} ${a['rs_time']}',
          ),
        );
      }
      if (rows.isEmpty) {
        return Center(
          child: Text(history ? '등록된 지난 매치가 없습니다.' : '배정된 요일·시간의 경기가 없습니다.'),
        );
      }
      return RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(operationsDataProvider('/match/operations'));
          await ref.read(operationsDataProvider('/match/operations').future);
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final status = switch (row['status']) {
              'completed' => '종료',
              'live' => '진행 중',
              'review' => '결과 확인',
              'teams' => '팀 설정',
              _ => '예정',
            };
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: const CircleAvatar(child: Icon(Icons.sports_soccer)),
                title: Text(
                  '${row['g_name']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${row['r_date']} · ${row['rs_time']}\n예약 ${row['count']}명${row['result_summary'] == null ? '' : ' · ${row['result_summary']}'}${row['scores'] == null ? '' : ' · ${row['scores']['A']} : ${row['scores']['B']}'}',
                ),
                isThreeLine: true,
                trailing: Chip(label: Text(status)),
                onTap: () async {
                  final completed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => MatchWorkflowPage(match: row),
                    ),
                  );
                  if (!context.mounted) return;
                  ref.invalidate(operationsDataProvider('/match/operations'));
                  if (completed == true) onCompleted?.call();
                },
              ),
            );
          },
        ),
      );
    },
  );
}

// 작업자 : 양태건
// 수정일 : 2026-10-26
// [추가 시작] 화면을 떠나도 서버에서 출석·팀·시간·기록을 복원합니다.
class MatchWorkflowPage extends ConsumerStatefulWidget {
  const MatchWorkflowPage({super.key, required this.match});
  final Map<String, dynamic> match;
  @override
  ConsumerState<MatchWorkflowPage> createState() => _MatchWorkflowPageState();
}

class _MatchWorkflowPageState extends ConsumerState<MatchWorkflowPage> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  int? selected;
  DateTime syncedAt = DateTime.now();
  Timer? timer;
  final search = TextEditingController();
  final teamNames = [TextEditingController(), TextEditingController()];
  Map<String, String> assignments = {};
  List<String> colors = ['blue', 'grey'];
  String get path => '/match/operations/${widget.match['r_seq']}';
  Map<String, dynamic> get state => Map<String, dynamic>.from(data!['state']);
  List<Map<String, dynamic>> get players =>
      (state['players'] as List).cast<Map<String, dynamic>>();
  String get status => '${data!['status']}';
  int get seconds =>
      (data!['elapsed_seconds'] as num).toInt() +
      (state['running_since'] == null
          ? 0
          : DateTime.now().difference(syncedAt).inSeconds);

  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && data != null && status == 'live') setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    for (final c in teamNames) {
      c.dispose();
    }
    super.dispose();
  }

  void accept(Map<String, dynamic> value) {
    data = value;
    syncedAt = DateTime.now();
    assignments = Map<String, String>.from(state['assignments']);
    colors = (state['team_colors'] as List).cast<String>().toList();
    final names = state['team_names'] as List;
    for (var i = 0; i < 2; i++) {
      teamNames[i].text = '${names[i]}';
    }
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref.read(operationsApiProvider).request(path);
      if (mounted) setState(() => accept(result));
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> command(
    String action, [
    Map<String, dynamic> values = const {},
  ]) async {
    if (busy) return false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref
          .read(operationsApiProvider)
          .request(
            path,
            json: {'version': data!['version'], 'action': action, ...values},
          );
      if (mounted) setState(() => accept(result));
      if (mounted) {
        ref.invalidate(operationsDataProvider('/match/operations'));
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error!)));
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Map<String, dynamic>> teamPlayers(String team) =>
      players.where((p) => assignments['${p['r_seq']}'] == team).toList();
  String statsText(Map<String, dynamic> p) {
    final stats = Map<String, dynamic>.from(data!['stats']['${p['r_seq']}']);
    final values = statLabels.entries
        .where((e) => (stats[e.key] as num) > 0)
        .map((e) => '${e.value} ${stats[e.key]}')
        .join(' · ');
    return values.isEmpty ? '기록 없음' : values;
  }

  Widget section(String title, Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );
  Widget actionButton(String text, VoidCallback? action, {IconData? icon}) =>
      FilledButton.icon(
        onPressed: busy ? null : action,
        icon: Icon(icon ?? Icons.chevron_right),
        label: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
      );

  @override
  Widget build(BuildContext context) {
    final isLive = data != null && status == 'live';
    final theme = isLive
        ? ThemeData.dark(useMaterial3: true).copyWith(
            scaffoldBackgroundColor: const Color(0xFF0E172D),
            cardColor: const Color(0xFF18243F),
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
          )
        : Theme.of(context);
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              data == null
                  ? '경기 불러오기'
                  : switch (status) {
                      'teams' => '팀 설정',
                      'live' => '경기 진행',
                      'review' => '결과 확인 · 등록',
                      'completed' => '지난 매치 · 경기 결과',
                      _ => '내 매치 · 출석 확인',
                    },
            ),
            actions: [
              IconButton(
                tooltip: '다시 불러오기',
                onPressed: busy ? null : load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: data == null
              ? Center(
                  child: busy
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(error ?? '경기를 불러올 수 없습니다.'),
                            OutlinedButton(
                              onPressed: load,
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                )
              : Column(
                  children: [
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      MaterialBanner(
                        content: Text(error!),
                        actions: [
                          TextButton(
                            onPressed: busy ? null : load,
                            child: const Text('다시 불러오기'),
                          ),
                        ],
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                      child: Text(
                        '${widget.match['g_name']} · ${widget.match['r_date']} ${widget.match['rs_time']}',
                      ),
                    ),
                    // 작업자 : 양태건
                    // 수정일 : 2026-10-26
                    // 새 테이블 없이 보관하는 진행 기록의 유지 범위를 안내합니다.
                    if (state['storage_mode'] == 'memory')
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Text(
                          '미등록 경기 진행 기록은 서버 재시작 시 사라집니다. 출석·부상 기록과 확정 결과는 DB에 저장됩니다.',
                        ),
                      ),
                    Expanded(
                      child: switch (status) {
                        'teams' => teamSetup(),
                        'live' => liveScreen(),
                        'review' || 'completed' => resultScreen(),
                        _ => attendanceScreen(),
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget attendanceScreen() {
    final attendance = Map<String, dynamic>.from(state['attendance']);
    final filtered = players
        .where(
          (p) => '${p['c_name']} ${p['r_seq']}'.contains(search.text.trim()),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        section(
          '예약자 명단 · 출석 확인 (${attendance.values.where((v) => v == true).length}/${players.length}명)',
          Column(
            children: [
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '이름 또는 예약번호 검색',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              for (final p in filtered)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text('${p['c_name']}'.substring(0, 1)),
                  ),
                  title: Text('${p['c_name']}'),
                  subtitle: Text(
                    '${p['c_position'] ?? '포지션 미등록'} · 예약 ${p['r_seq']}',
                  ),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      FilterChip(
                        label: const Text('출석'),
                        selected: attendance['${p['r_seq']}'] == true,
                        onSelected: busy
                            ? null
                            : (_) => command('attendance', {
                                'r_seq': p['r_seq'],
                                'attendance': true,
                              }),
                      ),
                      FilterChip(
                        label: const Text('결석'),
                        selected: attendance['${p['r_seq']}'] == false,
                        onSelected: busy
                            ? null
                            : (_) => command('attendance', {
                                'r_seq': p['r_seq'],
                                'attendance': false,
                              }),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        section(
          '출석 확인 후 팀을 배정해 주세요',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('모든 예약자를 출석 또는 결석으로 확인해 주세요. 출석한 회원만 팀에 배정됩니다.'),
              const SizedBox(height: 16),
              actionButton(
                '경기 시작 · 팀 설정',
                attendance.length == players.length
                    ? () => command('teams')
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget teamSetup() {
    final present = players
        .where((p) => state['attendance']['${p['r_seq']}'] == true)
        .toList();
    final a = teamPlayers('A').length, b = teamPlayers('B').length;
    final valid =
        assignments.length == present.length &&
        a > 0 &&
        b > 0 &&
        (a - b).abs() <= 1;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              for (var i = 0; i < 2; i++)
                section(
                  '${i == 0 ? a : b}명',
                  Column(
                    children: [
                      TextField(
                        controller: teamNames[i],
                        maxLength: 50,
                        decoration: const InputDecoration(labelText: '팀 이름'),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final e in bibColors.entries)
                            Tooltip(
                              message: e.key,
                              child: InkWell(
                                onTap: busy
                                    ? null
                                    : () => setState(() => colors[i] = e.key),
                                child: CircleAvatar(
                                  backgroundColor: e.value,
                                  radius: 18,
                                  child: colors[i] == e.key
                                      ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ];
            return constraints.maxWidth > 700
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 20),
                      Expanded(child: cards[1]),
                    ],
                  )
                : Column(children: cards);
          },
        ),
        section(
          '출석자 팀 배정 · 미배정 ${present.length - assignments.length}명',
          Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => assignments.clear()),
                  child: const Text('배정 초기화'),
                ),
              ),
              for (final p in present)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${p['c_name']}'),
                  subtitle: Text('${p['c_position'] ?? ''}'),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'A', label: Text('A팀')),
                      ButtonSegment(value: 'B', label: Text('B팀')),
                    ],
                    emptySelectionAllowed: true,
                    selected: assignments['${p['r_seq']}'] == null
                        ? {}
                        : {assignments['${p['r_seq']}']!},
                    onSelectionChanged: busy
                        ? null
                        : (v) => setState(() {
                            if (v.isEmpty) {
                              assignments.remove('${p['r_seq']}');
                            } else {
                              assignments['${p['r_seq']}'] = v.first;
                            }
                          }),
                  ),
                ),
            ],
          ),
        ),
        const Text('전원을 배정하고 두 팀의 인원 차이를 1명 이하로 맞춰 주세요. 조끼 색은 서로 다르게 선택해 주세요.'),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: busy ? null : () => command('back'),
          child: const Text('출석으로 돌아가기'),
        ),
        actionButton(
          '경기 시작',
          valid
              ? () async {
                  final saved = await command('teams', {
                    'assignments': assignments,
                    'team_names': teamNames.map((c) => c.text.trim()).toList(),
                    'team_colors': colors,
                  });
                  if (saved) await command('start');
                }
              : null,
          icon: Icons.play_arrow,
        ),
      ],
    );
  }

  Widget scoreboard() => section(
    '경기 ${status == 'live' ? '진행 중' : '결과'}',
    Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 24,
          children: [
            Text(
              '${state['team_names'][0]}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(
              '${data!['scores']['A']} : ${data!['scores']['B']}',
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900),
            ),
            Text(
              '${state['team_names'][1]}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        // 작업자 : 양태건
        // 수정일 : 2026-10-26
        // 기록된 경기 시간이 없는 결과에서는 시간 영역을 표시하지 않습니다.
        if (state['duration_unknown'] != true)
          Text(
            clockText(seconds),
            style: const TextStyle(
              fontSize: 28,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        Text(
          '기록 ${(state['events'] as List).length}건${status == 'live' && state['running_since'] == null ? ' · 일시정지' : ''}',
        ),
      ],
    ),
  );

  Widget playerList(String team) => section(
    '${state['team_names'][team == 'A' ? 0 : 1]} · ${teamPlayers(team).length}명',
    Column(
      children: [
        for (final p in teamPlayers(team))
          Card(
            color: selected == p['r_seq']
                ? Colors.blue.withValues(alpha: 0.3)
                : null,
            shape: selected == p['r_seq']
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.amber, width: 2),
                  )
                : null,
            child: ListTile(
              onTap: busy
                  ? null
                  : () => setState(() => selected = p['r_seq'] as int),
              leading: CircleAvatar(
                backgroundColor: bibColors[colors[team == 'A' ? 0 : 1]],
                child: Text(
                  '${p['c_name']}'.substring(0, 1),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text('${p['c_name']}'),
              subtitle: Text(statsText(p)),
            ),
          ),
      ],
    ),
  );

  Widget liveScreen() {
    final chosen = players.where((p) => p['r_seq'] == selected).firstOrNull;
    final controls = section(
      chosen == null ? '① 선수 선택 ② 기록 버튼' : '${chosen['c_name']} 기록',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final e in statLabels.entries)
                SizedBox(
                  width: 130,
                  child: actionButton(
                    e.value,
                    selected == null
                        ? null
                        : () => command('event', {
                            'r_seq': selected,
                            'kind': e.key,
                          }),
                    icon: e.key == 'goal' ? Icons.sports_soccer : Icons.add,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: busy || (state['events'] as List).isEmpty
                ? null
                : () => command('undo'),
            child: const Text('마지막 기록 취소'),
          ),
          OutlinedButton.icon(
            onPressed: busy || chosen == null
                ? null
                : () async {
                    final values =
                        await showModalBottomSheet<Map<String, dynamic>>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => InjurySheet(
                            playerName: '${chosen['c_name']}',
                            elapsed: seconds,
                          ),
                        );
                    if (values != null && mounted) {
                      await command('injury', {'r_seq': selected, ...values});
                    }
                  },
            icon: const Icon(Icons.medical_services, color: Colors.red),
            label: const Text('응급 · 부상 기록'),
          ),
          const Divider(height: 32),
          if ((state['events'] as List).isEmpty) const Text('아직 기록이 없습니다.'),
          for (final event in (state['events'] as List).reversed.take(20))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '${clockText((event['elapsed_seconds'] as num).toInt())} · ${event['name']} · ${statLabels[event['kind']]}',
              ),
            ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        scoreboard(),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 1000
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: playerList('A')),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: controls),
                    const SizedBox(width: 16),
                    Expanded(child: playerList('B')),
                  ],
                )
              : Column(children: [playerList('A'), playerList('B'), controls]),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 16,
          children: [
            actionButton(
              state['running_since'] == null ? '경기 재개' : '일시정지',
              () =>
                  command(state['running_since'] == null ? 'resume' : 'pause'),
              icon: state['running_since'] == null
                  ? Icons.play_arrow
                  : Icons.pause,
            ),
            actionButton('경기 종료', () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('경기를 종료할까요?'),
                  content: const Text(
                    '결과 확인 후 등록할 수 있습니다. 잘못된 기록은 다시 돌아와 수정할 수 있습니다.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('경기 종료'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await command('end');
            }, icon: Icons.stop),
          ],
        ),
        const SizedBox(height: 20),
        injuryRecords(),
      ],
    );
  }

  // 작업자 : 양태건
  // 수정일 : 2026-10-26
  // [수정 시작] 이전 결과의 점수·스탯은 새 형식으로 추정하지 않고 원문으로 표시합니다.
  Widget legacyResultScreen() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      section(
        '기존 경기 결과',
        const Text('이전 방식으로 등록한 결과입니다. 저장된 값을 그대로 표시하며 재등록하거나 수정하지 않습니다.'),
      ),
      for (final raw in state['legacy_records'] as List)
        section(
          '${raw['c_name'] ?? raw['c_id_seq']}',
          RecordDetails(
            record: {
              'c_id_seq': raw['c_id_seq'],
              'c_r_r_team': raw['c_r_r_team'],
              'c_r_r_score': raw['c_r_r_score'],
              'e_code': raw['e_code'],
              'c_r_r_statcode': raw['c_r_r_statcode'],
              'c_r_r_attendance': raw['c_r_r_attendance'] == 1 ? '출석' : '결석',
              'c_r_r_date': raw['c_r_r_date'],
            },
          ),
        ),
      injuryRecords(),
      actionButton(
        '지난 매치 목록으로',
        () => Navigator.of(context).pop(true),
        icon: Icons.arrow_back,
      ),
    ],
  );
  // [수정 끝]

  Widget resultScreen() => data!['legacy'] == true
      ? legacyResultScreen()
      : ListView(
          padding: const EdgeInsets.all(24),
          children: [
            scoreboard(),
            for (final team in ['A', 'B'])
              section(
                '${state['team_names'][team == 'A' ? 0 : 1]} · 회원별 기록',
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      const DataColumn(label: Text('회원')),
                      for (final name in statLabels.values)
                        DataColumn(label: Text(name), numeric: true),
                    ],
                    rows: [
                      for (final p in teamPlayers(team))
                        DataRow(
                          cells: [
                            DataCell(Text('${p['c_name']}')),
                            for (final key in statLabels.keys)
                              DataCell(
                                Text('${data!['stats']['${p['r_seq']}'][key]}'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            injuryRecords(),
            if (status == 'review')
              section(
                '결과를 등록할까요?',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '등록하면 모든 회원의 결과가 함께 저장되고 지난 매치로 이동합니다. 등록 후에는 수정할 수 없습니다.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: busy ? null : () => command('edit'),
                          child: const Text('기록으로 돌아가기'),
                        ),
                        actionButton('결과 등록', () async {
                          final saved = await command('publish');
                          if (saved && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '결과가 등록되었습니다. 지난 매치에서 확인할 수 있습니다.',
                                ),
                              ),
                            );
                            Navigator.of(context).pop(true);
                          }
                        }, icon: Icons.save),
                      ],
                    ),
                  ],
                ),
              ),
            if (status == 'completed')
              actionButton(
                '지난 매치 목록으로',
                () => Navigator.of(context).pop(true),
                icon: Icons.check_circle,
              ),
          ],
        );

  Widget injuryRecords() => section(
    '부상 기록 ${(state['injuries'] as List).length}건',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((state['injuries'] as List).isEmpty) const Text('등록된 부상 기록이 없습니다.'),
        for (final injury in state['injuries'] as List)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${injury['name']} · ${(injury['body_parts'] as List).join(', ')}',
            ),
            subtitle: Text(
              '${injury['elapsed_seconds'] is num ? clockText((injury['elapsed_seconds'] as num).toInt()) : '시각 미기록'} · ${switch (injury['severity']) {
                'mild' => '경미',
                'moderate' => '중등도',
                'severe' => '심각',
                _ => '정도 미기록',
              }} · 접촉 ${injury['contact'] == null
                  ? '미기록'
                  : injury['contact'] == true
                  ? '있음'
                  : '없음'}\n${injury['description']}\n조치: ${(injury['measures'] as List).join(', ')}',
            ),
            isThreeLine: true,
          ),
      ],
    ),
  );
}

// 작업자 : 양태건
// 수정일 : 2026-10-26
// [추가 시작] 선택한 선수의 부상 정보를 저장하는 입력 창입니다.
class InjurySheet extends StatefulWidget {
  const InjurySheet({
    super.key,
    required this.playerName,
    required this.elapsed,
  });
  final String playerName;
  final int elapsed;
  @override
  State<InjurySheet> createState() => _InjurySheetState();
}

class _InjurySheetState extends State<InjurySheet> {
  final parts = <String>{};
  final measures = <String>{};
  String severity = 'mild';
  bool contact = false;
  final description = TextEditingController();
  String? error;
  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Widget chips(List<String> choices, Set<String> selected) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final choice in choices)
        FilterChip(
          label: Text(choice),
          selected: selected.contains(choice),
          onSelected: (v) => setState(() {
            if (v) {
              selected.add(choice);
            } else {
              selected.remove(choice);
            }
          }),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .88,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '부상 기록 · ${widget.playerName}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text(
            '긴급 상황이면 먼저 119에 신고하고 경기장 AED·구급함 위치를 확인해 주세요. 기록은 나중에 해도 됩니다.',
            style: TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 20),
          const Text('부상 부위 (복수 선택)'),
          chips([
            '머리·얼굴',
            '목·어깨',
            '팔·손목',
            '손가락',
            '허리·등',
            '무릎',
            '발목·발',
            '기타',
          ], parts),
          const SizedBox(height: 16),
          const Text('부상 정도'),
          Wrap(
            spacing: 8,
            children: [
              for (final e in {
                'mild': '경미 · 현장 처치 후 계속 경기',
                'moderate': '중등도 · 경기 이탈 · 병원 권유',
                'severe': '심각 · 119 · 병원 이송',
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: severity == e.key,
                  onSelected: (_) => setState(() => severity = e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('조치'),
          chips([
            '아이싱',
            '응급처치·밴드',
            '경기 일시 중단',
            '교체·퇴장',
            '119 신고',
            '병원 이송',
            '보호자 연락',
          ], measures),
          const SizedBox(height: 16),
          TextField(
            controller: description,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: '상황 · 부상 내용'),
          ),
          SwitchListTile(
            title: const Text('상대 선수와 접촉'),
            value: contact,
            onChanged: (v) => setState(() => contact = v),
          ),
          Text('발생 시각 ${clockText(widget.elapsed)}'),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () {
                  if (parts.isEmpty || description.text.trim().isEmpty) {
                    setState(() => error = '부상 부위와 상황을 입력해 주세요.');
                    return;
                  }
                  Navigator.pop(context, <String, dynamic>{
                    'occurred_seconds': widget.elapsed,
                    'body_parts': parts.toList(),
                    'severity': severity,
                    'measures': measures.toList(),
                    'description': description.text.trim(),
                    'contact': contact,
                  });
                },
                child: const Text('부상 기록 저장'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
// [추가 끝]
