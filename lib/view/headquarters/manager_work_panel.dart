import '../shared/async_screen_state.dart';

// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 본사는 매니저별 예약을 조회하며 매니저 경기 진행 권한을 사용하지 않습니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import 'admin_components.dart';

class ManagerWorkPanel extends ConsumerStatefulWidget {
  const ManagerWorkPanel({super.key, required this.staffId});
  final String staffId;
  @override
  ConsumerState<ManagerWorkPanel> createState() => _ManagerWorkPanelState();
}

class _ManagerWorkPanelState extends ConsumerState<ManagerWorkPanel>
    with AsyncScreenState<ManagerWorkPanel> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {'manager': null};
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  String? get manager => screenValue<String?>('manager');
  set manager(String? value) => setScreenValue('manager', value);
  @override
  Widget build(BuildContext context) {
    watchScreen();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 850) return _content(context);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 320,
              child: Material(
                color: Colors.white,
                child: AdminData(
                  staffId: widget.staffId,
                  path: '/approval/grounds/managers',
                  builder: (p) => ListView(
                    children: [
                      for (final row in p.rows)
                        ListTile(
                          selected: manager == '${row['m_id']}',
                          title: Text(adminText(row['m_name'])),
                          subtitle: Text(
                            '${adminText(row['m_id'])} · ${adminText(row['m_workplace'])}',
                          ),
                          onTap: () =>
                              updateScreen(() => manager = '${row['m_id']}'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _content(context)),
          ],
        );
      },
    );
  }

  Widget _content(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(18),
        child: AdminData(
          staffId: widget.staffId,
          path: '/approval/grounds/managers',
          builder: (p) => DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: '담당 매니저 선택'),
            items: [
              for (final r in p.rows)
                DropdownMenuItem(
                  value: '${r['m_id']}',
                  child: Text(
                    '${adminText(r['m_name'])} · ${adminText(r['m_workplace'])}',
                  ),
                ),
            ],
            onChanged: (v) => updateScreen(() => manager = v),
          ),
        ),
      ),
      Expanded(
        child: manager == null
            ? Center(child: Text('예약을 조회할 매니저를 선택해 주세요.'))
            : AdminData(
                staffId: widget.staffId,
                path: '/match/list/${Uri.encodeComponent(manager!)}',
                builder: (p) {
                  final rows = adminRows(p.data['reservations']);
                  return ListView(
                    padding: const EdgeInsets.all(22),
                    children: [
                      Text('예약 ${rows.length}건 · 예약자별 내역'),
                      const SizedBox(height: 12),
                      if (rows.isEmpty) const Text('조회된 내역이 없습니다.'),
                      for (final row in rows)
                        AdminCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              adminTitle(adminText(row['g_name'])),
                              adminFields({
                                '예약자': row['c_name'],
                                '예약 번호': row['r_seq'],
                                '예약일': row['r_date'],
                                '시간':
                                    '${adminText(row['rs_time'])}~${adminText(row['re_time'])}',
                                '포지션': row['c_position'],
                              }),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    ],
  );
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
