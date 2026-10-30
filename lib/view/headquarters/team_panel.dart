import '../shared/async_screen_state.dart';

// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 팀 목록·상세를 실제 팀 ID로 연결하고 기록이 없는 등급·승률은 미기록으로 둡니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../service/headquarters_service.dart';
import 'admin_components.dart';
import '../shared/admin_split_view.dart';

class TeamPanel extends ConsumerStatefulWidget {
  const TeamPanel({super.key, required this.staffId});
  final String staffId;
  @override
  ConsumerState<TeamPanel> createState() => _TeamPanelState();
}

class _TeamPanelState extends ConsumerState<TeamPanel>
    with AsyncScreenState<TeamPanel> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {
    'keyword': '',
    'category': null,
    'selected': null,
  };
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  String get keyword => screenValue<String>('keyword');
  set keyword(String value) => setScreenValue('keyword', value);
  String? get category => screenValue<String?>('category');
  set category(String? value) => setScreenValue('category', value);
  int? get selected => screenValue<int?>('selected');
  set selected(int? value) => setScreenValue('selected', value);
  @override
  Widget build(BuildContext context) {
    watchScreen();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: '팀명 · 팀장 검색',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (v) => updateScreen(() {
                    keyword = v.trim();
                    selected = null;
                  }),
                ),
              ),
              DropdownButton<String>(
                value: category ?? '전체 종목',
                items: [
                  for (final v in ['전체 종목', '축구', '농구', '배구', '야구'])
                    DropdownMenuItem(value: v, child: Text(v)),
                ],
                onChanged: (v) => updateScreen(() {
                  category = v == '전체 종목' ? null : v;
                  selected = null;
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: AdminSplitView(
            selected: selected != null,
            onBack: () => updateScreen(() => selected = null),
            list: AdminData(
              staffId: widget.staffId,
              path: adminPath('/management/teams', {
                'keyword': keyword,
                'category': category,
              }),
              builder: (p) => ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Text('전체 ${p.number('total') ?? p.rows.length}팀'),
                  const SizedBox(height: 12),
                  if (p.rows.isEmpty) const Text('조회된 팀이 없습니다.'),
                  for (final row in p.rows)
                    InkWell(
                      onTap: () =>
                          updateScreen(() => selected = adminInt(row['t_id'])),
                      child: AdminCard(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            child: Text(
                              adminText(row['t_name']).characters.first,
                            ),
                          ),
                          title: Text(adminText(row['t_name'])),
                          subtitle: Text(
                            '${adminText(row['category'])} · 팀장 ${adminText(row['captain_name'])} · ${adminText(row['member_count'])}명',
                          ),
                          trailing: Text('등급 ${adminText(row['grade'])} ›'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            detail: selected == null
                ? const Center(child: Text('팀을 선택해 상세 정보를 확인하세요.'))
                : AdminData(
                    staffId: widget.staffId,
                    path: '/management/teams/$selected',
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
                              label: const Text('팀 목록으로'),
                            ),
                          ),
                          AdminCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                adminTitle(adminText(r['t_name'])),
                                adminFields({
                                  '종목': r['category'],
                                  '팀장': r['captain_name'],
                                  '지역': r['region'],
                                  '개설일': r['created_date'],
                                  '팀 등급': r['grade'],
                                  '전적':
                                      '${adminText(r['wins'])}승 ${adminText(r['draws'])}무 ${adminText(r['losses'])}패',
                                  '승률': r['win_rate'] == null
                                      ? '기록 없음'
                                      : '${r['win_rate']}%',
                                  '득점': r['points_for'],
                                  '실점': r['points_against'],
                                }),
                              ],
                            ),
                          ),
                          AdminCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                adminTitle('팀원'),
                                for (final member in adminRows(r['members']))
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(adminText(member['c_name'])),
                                    subtitle: Text(
                                      '${adminText(member['c_id_seq'])} · ${adminText(member['c_position'])}',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          AdminCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                adminTitle('최근 경기'),
                                if (adminRows(r['recent_matches']).isEmpty)
                                  const Text('경기 기록이 없습니다.'),
                                for (final match in adminRows(
                                  r['recent_matches'],
                                ))
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      '${adminText(match['opponent_t_name'])} · ${adminText(match['score'])}',
                                    ),
                                    subtitle: Text(
                                      '${adminText(match['t_r_r_date'])} · ${adminText(match['g_name'])} · ${adminText(match['m_name'])}',
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
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
