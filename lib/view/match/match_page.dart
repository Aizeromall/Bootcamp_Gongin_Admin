// 작업자 : 양태건
// 수정일 : 2026-10-26
// [수정 시작] 예약별 입력 창을 경기별 출석·팀 설정·실시간 기록 흐름으로 변경합니다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../service/operations_api.dart';
import '../../vm/manager_result_notifier.dart';
import '../shared/records_view.dart';
import '../shared/admin_style.dart';
import '../headquarters/admin_components.dart';
import 'match_cancel_dialog.dart';

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
      final list = RefreshIndicator(
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
                      builder: (_) =>
                          MatchWorkflowPage(match: row, managerId: managerId),
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
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 850) return list;
          final row = rows.first;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 360,
                child: ColoredBox(color: Colors.white, child: list),
              ),
              const VerticalDivider(width: 1, color: AdminStyle.line),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(22),
                  children: [
                    AdminCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          adminTitle('${row['g_name']}'),
                          adminFields({
                            '일시': '${row['r_date']} · ${row['rs_time']}',
                            '예약 인원': row['count'],
                            '결과':
                                row['result_summary'] ??
                                (row['scores'] == null
                                    ? '—'
                                    : "${row['scores']['A']} : ${row['scores']['B']}"),
                          }),
                          FilledButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: Text(history ? '경기 결과 보기' : '출석 · 경기 운영 열기'),
                            onPressed: () async {
                              final completed = await Navigator.of(context)
                                  .push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => MatchWorkflowPage(
                                        match: row,
                                        managerId: managerId,
                                      ),
                                    ),
                                  );
                              if (!context.mounted) return;
                              ref.invalidate(
                                operationsDataProvider('/match/operations'),
                              );
                              if (completed == true) onCompleted?.call();
                            },
                          ),
                        ],
                      ),
                    ),
                    AdminCard(
                      child: Text(
                        history
                            ? '목록에서 경기를 선택하면 저장된 경기 결과를 확인할 수 있습니다.'
                            : '목록에서 경기를 선택해 출석 확인, 팀 설정, 경기 기록을 진행하세요.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

// 작업자 : 양태건
// 수정일 : 2026-10-26
// [추가 시작] 화면을 떠나도 서버에서 출석·팀·시간·기록을 복원합니다.
class MatchWorkflowPage extends ConsumerStatefulWidget {
  const MatchWorkflowPage({
    super.key,
    required this.match,
    this.managerId,
    this.embedded = false,
    this.onPublished,
  });
  final bool embedded;
  final VoidCallback? onPublished;
  final Map<String, dynamic> match;
  final String? managerId;
  @override
  ConsumerState<MatchWorkflowPage> createState() => _MatchWorkflowPageState();
}

class _MatchWorkflowPageState extends ConsumerState<MatchWorkflowPage> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  bool checkingAll = false;
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
      if (mounted && !widget.embedded) {
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
  // 작업자 : 신현진
  // 수정일 : 2026-10-29
  // [수정 시작] 4종목 지원 : 서버가 보내는 종목 정보(sport)로 기록 버튼·스탯 이름을 그립니다.
  // 종목 정보가 없는 응답(이전 서버)은 기존 축구 버튼(statLabels)으로 표시합니다.
  List<Map<String, dynamic>> get sportEvents {
    final events = data?['sport']?['events'] as List?;
    if (events == null) {
      return [
        for (final e in statLabels.entries)
          {'kind': e.key, 'label': e.value, 'own': e.key == 'goal' ? 1 : 0},
      ];
    }
    return events.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  List<Map<String, dynamic>> get sportStats {
    final stats = data?['sport']?['stats'] as List?;
    if (stats == null) {
      return [
        for (final e in statLabels.entries) {'key': e.key, 'label': e.value},
      ];
    }
    return stats.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // 점수가 나는 버튼 아이콘 (종목별)
  IconData get scoreIcon => switch (data?['sport']?['e_code']) {
    'BASKETBALL' => Icons.sports_basketball,
    'VOLLEYBALL' => Icons.sports_volleyball,
    'BASEBALL' => Icons.sports_baseball,
    _ => Icons.sports_soccer,
  };

  String eventLabel(String? kind) =>
      sportEvents.firstWhere(
            (e) => e['kind'] == kind,
            orElse: () => {'label': kind ?? ''},
          )['label']
          as String;

  // 기록 목록 표시 (야구 홈런은 "홈런 2점 · 홈인 선수3" 처럼 점수·홈인 주자를 함께 표시)
  String eventText(Map event) {
    final label = eventLabel(event['kind'] as String?);
    final names = (event['runner_names'] as List?) ?? const [];
    final isRunnerEvent = sportEvents.any(
      (e) => e['kind'] == event['kind'] && e['runners'] == true,
    );
    if (!isRunnerEvent) return label;
    final points = names.length + 1;
    return names.isEmpty
        ? '$label $points점'
        : '$label $points점 · 홈인 ${names.join(', ')}';
  }

  // 야구 홈런 : 같은 팀 출전 선수 중 홈인한 주자를 최대 3명 선택 (취소하면 null)
  Future<List<int>?> pickRunners() {
    final team = '${assignments['$selected']}';
    final candidates = teamPlayers(team)
        .where((p) => p['r_seq'] != selected)
        .toList();
    final chosen = <int>{};
    return showDialog<List<int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('홈인한 주자 선택 · ${chosen.length + 1}점 홈런'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text('주자 없이 솔로 홈런이면 선택하지 않고 기록하세요. (최대 3명 = 만루 홈런)'),
                for (final p in candidates)
                  CheckboxListTile(
                    value: chosen.contains(p['r_seq']),
                    title: Text('${p['c_name']}'),
                    // 3명을 고르면 나머지는 선택할 수 없음
                    onChanged:
                        !chosen.contains(p['r_seq']) && chosen.length >= 3
                        ? null
                        : (checked) => setDialog(
                            () => checked == true
                                ? chosen.add(p['r_seq'] as int)
                                : chosen.remove(p['r_seq']),
                          ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, chosen.toList()),
              child: Text('${chosen.length + 1}점 홈런 기록'),
            ),
          ],
        ),
      ),
    );
  }

  String statsText(Map<String, dynamic> p) {
    final stats = Map<String, dynamic>.from(data!['stats']['${p['r_seq']}']);
    final values = sportStats
        .where((e) => ((stats[e['key']] ?? 0) as num) > 0)
        .map((e) => '${e['label']} ${stats[e['key']]}')
        .join(' · ');
    return values.isEmpty ? '기록 없음' : values;
  }
  // [수정 끝]

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
        onPressed: busy || checkingAll ? null : action,
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
            textTheme: Theme.of(context).textTheme
                .apply(bodyColor: Colors.white, displayColor: Colors.white),
            cardTheme: const CardThemeData(
              color: Color(0xFF18243F),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
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
          appBar: widget.embedded
              ? null
              : AppBar(
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
                        [
                              widget.match['g_name'],
                              widget.match['r_date'],
                              widget.match['rs_time'],
                            ]
                            .whereType<String>()
                            .where((v) => v.isNotEmpty)
                            .join(' · '),
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
    final rules = ref.watch(managerRatingRulesProvider);
    final filtered = players
        .where(
          (p) => '${p['c_name']} ${p['r_seq']}'.contains(search.text.trim()),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 수정 일 : 2026-10-29 / 작업자 : 양태건
        // 선택한 예정 경기의 실제 정보와 현재 출석 현황을 같은 상세 영역에 표시합니다.
        section(
          '${widget.match['g_name'] ?? '구장'}',
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              Text(
                '일시\n${widget.match['r_date'] ?? ''} ${widget.match['rs_time'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('유형\n실력매칭'),
              Text('종목\n${data?['sport']?['name'] ?? '미확인'}'),
              Text(
                '출석\n${attendance.values.where((value) => value == true).length} / ${players.length}명',
              ),
            ],
          ),
        ),
        if (rules.hasError)
          TextButton(
            onPressed: () => ref.invalidate(managerRatingRulesProvider),
            child: const Text('레벨 기준을 불러오지 못했습니다. 다시 시도'),
          ),
        section(
          '시간 · 출석 안내',
          const Text(
            '경기 전 예약자 명단을 확인하고 도착한 회원의 출석을 체크해 주세요.\n시작 이후 미확인 인원은 현장에서 확인해 주세요. 자동 알림 발송 기능은 연결되어 있지 않습니다.',
          ),
        ),
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
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: busy || checkingAll
                      ? null
                      : () async {
                          setState(() => checkingAll = true);
                          try {
                            for (final player in players) {
                              if (state['attendance']['${player['r_seq']}'] ==
                                  true) {
                                continue;
                              }
                              final saved = await command('attendance', {
                                'r_seq': player['r_seq'],
                                'attendance': true,
                              });
                              if (!mounted || !saved) break;
                            }
                          } finally {
                            if (mounted) setState(() => checkingAll = false);
                          }
                        },
                  child: Text(checkingAll ? '출석 확인 중…' : '전원 출석'),
                ),
              ),
              for (final p in filtered)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text('${p['c_name']}'.substring(0, 1)),
                  ),
                  title: Text('${p['c_name']}'),
                  subtitle: Text(
                    '${rules.asData?.value.tier(p['c_rating']) ?? '레벨 미확인'} · ${p['c_position'] ?? '포지션 미등록'} · 예약 ${p['r_seq']}',
                  ),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      FilterChip(
                        label: const Text('출석'),
                        selected: attendance['${p['r_seq']}'] == true,
                        onSelected: busy || checkingAll
                            ? null
                            : (_) => command('attendance', {
                                'r_seq': p['r_seq'],
                                'attendance': true,
                              }),
                      ),
                      FilterChip(
                        label: const Text('결석'),
                        selected: attendance['${p['r_seq']}'] == false,
                        onSelected: busy || checkingAll
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
              if (widget.managerId != null && widget.match['g_code'] != null)
                TextButton.icon(
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('경기 취소'),
                  onPressed: busy
                      ? null
                      : () async {
                          final date = '${widget.match['r_date'] ?? ''}';
                          final time = '${widget.match['rs_time'] ?? ''}';
                          if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
                              !RegExp(r'^([01]\d|2[0-3]):[0-5]\d(:00)?$')
                                  .hasMatch(time)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('경기 일시를 확인할 수 없습니다. 다시 불러와 주세요.'),
                              ),
                            );
                            return;
                          }
                          final cancelled = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => MatchCancelDialog(
                              groundName: '${widget.match['g_name'] ?? '구장'}',
                              target: (
                                managerId: widget.managerId!,
                                groundCode: '${widget.match['g_code']}',
                                date: date,
                                start: time.substring(0, 5),
                              ),
                            ),
                          );
                          if (cancelled == true && mounted) {
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.of(context).pop(false);
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('경기 예약 취소가 처리되었습니다.'),
                              ),
                            );
                          }
                        },
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

  // 수정 일 : 2026-10-28 / 작업자 : 양태건
  // 진행 중 점수판은 상단 한 줄로 모으고 기록 버튼은 두 열로 배치합니다.
  Widget scoreboard() => status == 'live'
      ? Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1326),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${state['team_names'][0]}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Column(
                children: [
                  Text(
                    '${data!['scores']['A']} : ${data!['scores']['B']}',
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (state['duration_unknown'] != true)
                    Text(
                      clockText(seconds),
                      style: const TextStyle(
                        fontSize: 24,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  Text(
                    state['running_since'] == null ? '일시정지' : '경기 진행 중',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9AAAC8),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Text(
                  '${state['team_names'][1]}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        )
      : section(
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
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${data!['scores']['A']} : ${data!['scores']['B']}',
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${state['team_names'][1]}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
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
          // 수정 일 : 2026-10-29 / 작업자 : 양태건
          // 새 종목별 기록·주자 선택을 기존 모바일 두 열 배치와 병합합니다.
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // 작업자 : 신현진 / 수정일 : 2026-10-29 종목별 기록 버튼
                for (final e in sportEvents)
                  SizedBox(
                    width: (constraints.maxWidth - 12) / 2,
                    child: actionButton(
                      '${e['label']}',
                      selected == null
                          ? null
                          : () async {
                              if (e['runners'] == true) {
                                final runners = await pickRunners();
                                if (runners == null || !mounted) return;
                                await command('event', {
                                  'r_seq': selected,
                                  'kind': e['kind'],
                                  'runners': runners,
                                });
                                return;
                              }
                              await command('event', {
                                'r_seq': selected,
                                'kind': e['kind'],
                              });
                            },
                      icon: ((e['own'] ?? 0) as num) > 0
                          ? scoreIcon
                          : Icons.add,
                    ),
                  ),
              ],
            ),
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
                '${clockText((event['elapsed_seconds'] as num).toInt())} · ${event['name']} · ${eventText(event as Map)}',
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
        '실력매칭 결과 목록으로',
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
                    // 작업자 : 신현진 / 수정일 : 2026-10-29 종목별 스탯 열
                    columns: [
                      const DataColumn(label: Text('회원')),
                      for (final stat in sportStats)
                        DataColumn(
                          label: Text('${stat['label']}'),
                          numeric: true,
                        ),
                    ],
                    rows: [
                      for (final p in teamPlayers(team))
                        DataRow(
                          cells: [
                            DataCell(Text('${p['c_name']}')),
                            for (final stat in sportStats)
                              DataCell(
                                Text(
                                  '${data!['stats']['${p['r_seq']}'][stat['key']] ?? 0}',
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            // 작업자 : 신현진
            // 수정일 : 2026-10-29
            // [추가 시작] 결과 등록 후 회원별 등급 점수 변동 (팀 승패 + 개인 스탯 보너스)
            if ((state['rating_changes'] as List?)?.isNotEmpty ?? false)
              section(
                '등급 점수 변동',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final change in state['rating_changes'] as List)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '${players.where((p) => p['c_id_seq'] == change['c_id_seq']).firstOrNull?['c_name'] ?? change['c_id_seq']}'
                          ' · ${change['result']} · ${change['rating_before']} → ${change['rating_after']}'
                          ' (${(change['rating_change'] as num) >= 0 ? '+' : ''}${change['rating_change']})'
                          ' · ${change['tier_before']} → ${change['tier_after']}',
                        ),
                      ),
                  ],
                ),
              ),
            // [추가 끝]
            injuryRecords(),
            if (status == 'review')
              section(
                '결과를 등록할까요?',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '등록하면 모든 회원의 결과가 함께 저장되고 실력매칭 결과로 이동합니다. 등록 후에는 수정할 수 없습니다.',
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
                                  '결과가 등록되었습니다. 실력매칭에서 확인할 수 있습니다.',
                                ),
                              ),
                            );
                            ref.invalidate(managerResultsProvider);
                            ref.invalidate(managerResultDetailProvider);
                            if (widget.embedded) {
                              widget.onPublished?.call();
                            } else {
                              Navigator.of(context).pop(true);
                            }
                          }
                        }, icon: Icons.save),
                      ],
                    ),
                  ],
                ),
              ),
            if (status == 'completed')
              actionButton('실력매칭 결과 목록으로', () {
                if (widget.embedded) {
                  widget.onPublished?.call();
                } else {
                  Navigator.of(context).pop(true);
                }
              }, icon: Icons.check_circle),
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

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
