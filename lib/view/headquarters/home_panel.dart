// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 집계 전용 API가 없는 항목은 추정하지 않고 실제 본사 조회 결과를 표시합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../vm/headquarters_notifier.dart';
import '../../service/operations_api.dart';
import '../shared/admin_style.dart';
import 'admin_components.dart';
import 'announcement_panel.dart';

class HeadquartersHome extends ConsumerWidget {
  const HeadquartersHome({
    super.key,
    required this.staffId,
    required this.onNavigate,
  });
  final String staffId;
  final ValueChanged<int> onNavigate;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${DateTime.now().year}년 ${DateTime.now().month}월 ${DateTime.now().day}일',
                style: const TextStyle(color: AdminStyle.muted),
              ),
            ),
            IconButton(
              tooltip: '대시보드 새로고침',
              onPressed: () {
                ref.invalidate(operationsDataProvider);
                ref.invalidate(adminDataProvider);
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric('답변 대기 문의', '/inquiry/list', 2, (p) {
                final rows = [
                  ...p.rows,
                  ...p.rows.expand((r) => adminRows(r['follow_ups'])),
                ];
                return rows.where((r) => '${r['i_state']}' != '1').length;
              }, c.maxWidth),
              _metric(
                '처리 대기 신고',
                '/report/list',
                4,
                (p) => p.number('pending_count'),
                c.maxWidth,
              ),
              _metric(
                '이의신청 대기',
                '/appeal/list',
                8,
                (p) => p.number('pending_count'),
                c.maxWidth,
              ),
              _metric(
                '미이수 필수 교육',
                '/education/courses',
                5,
                (p) => p.number('required_pending'),
                c.maxWidth,
              ),
              _metric(
                '등록 팀',
                '/management/teams',
                9,
                (p) => p.number('total'),
                c.maxWidth,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final notices = AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: adminTitle('공지사항')),
                      TextButton(
                        onPressed: () => onNavigate(7),
                        child: const Text('전체 보기'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            showAnnouncementWriter(context, staffId),
                        child: const Text('+ 작성하기'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AdminData(
                    staffId: staffId,
                    path: '/announce/admin?limit=3&offset=0',
                    builder: (p) => p.rows.isEmpty
                        ? const Text('등록된 본사 공지가 없습니다.')
                        : Column(
                            children: [
                              for (final row in p.rows)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: InkWell(
                                    onTap: () => showAnnouncement(context, row),
                                    child: AdminCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              adminBadge(
                                                adminText(row['a_classify']),
                                              ),
                                              const Spacer(),
                                              Text(
                                                adminText(row['a_date'])
                                                    .split('T')
                                                    .first,
                                                style: const TextStyle(
                                                  color: AdminStyle.muted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            adminText(row['a_title']),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '작성자 · ${adminText(row['h_name'])}',
                                            style: const TextStyle(
                                              color: AdminStyle.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            adminText(row['a_detail']),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            );
            final tasks = AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  adminTitle('처리할 일'),
                  const SizedBox(height: 16),
                  _tasks(
                    '문의',
                    '/inquiry/list',
                    2,
                    (r) => '${r['i_state']}' != '1',
                    (r) => adminText(r['post']),
                  ),
                  _tasks(
                    '신고',
                    '/report/list',
                    4,
                    (r) => r['state_text'] == '접수' || r['state_text'] == '심의중',
                    (r) =>
                        '${adminText(r['target_name'])} · ${adminText(r['r_option_name'])}',
                  ),
                  _tasks(
                    '이의신청',
                    '/appeal/list',
                    8,
                    (r) =>
                        r['state_text'] == '접수' || r['state_text'] == '재심의 중',
                    (r) => adminText(r['title']),
                  ),
                ],
              ),
            );
            return c.maxWidth >= 820
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: notices),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: tasks),
                    ],
                  )
                : Column(children: [notices, tasks]);
          },
        ),
      ],
    ),
  );
  Widget _metric(
    String title,
    String path,
    int destination,
    int? Function(AdminPayload) count,
    double width,
  ) => SizedBox(
    width: width >= 860
        ? (width - 48) / 5
        : width >= 600
        ? (width - 24) / 3
        : (width - 12) / 2,
    child: AdminCard(
      child: InkWell(
        onTap: () => onNavigate(destination),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: AdminStyle.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            AdminData(
              staffId: staffId,
              path: path,
              builder: (p) => Text(
                '${count(p) ?? '—'}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: AdminStyle.red,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '현황 확인',
              style: TextStyle(color: AdminStyle.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _tasks(
    String name,
    String path,
    int destination,
    bool Function(AdminRow) pending,
    String Function(AdminRow) title,
  ) => AdminData(
    staffId: staffId,
    path: path,
    builder: (p) {
      final rows = p.rows.where(pending).take(3).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '$name 대기 내역이 없습니다.',
                style: const TextStyle(color: AdminStyle.muted),
              ),
            ),
          for (final row in rows)
            InkWell(
              onTap: () => onNavigate(destination),
              child: AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    adminBadge(name, alert: name != '문의'),
                    const SizedBox(height: 8),
                    Text(
                      title(row),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
