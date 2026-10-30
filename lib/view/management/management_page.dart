// 작업자 : 최현준 / 작업 일 : 2026-10-24
// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 기존 회원·매니저 목록과 실제 ID 상세를 목업의 좌우 분할 화면으로 연결합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/records_view.dart';
import '../shared/admin_split_view.dart';
import '../shared/admin_style.dart';
import '../headquarters/admin_components.dart';
import '../../service/operations_api.dart';

class ManagementPage extends ConsumerStatefulWidget {
  const ManagementPage({super.key, required this.managers});
  final bool managers;
  @override
  ConsumerState<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends ConsumerState<ManagementPage> {
  String keyword = '';
  String? selected;
  @override
  Widget build(BuildContext context) {
    final category = widget.managers ? 'managers' : 'members';
    final path =
        '/management/$category?keyword=${Uri.encodeQueryComponent(keyword)}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  decoration: const InputDecoration(
                    labelText: '이름 · 아이디 · 전화번호 검색',
                    prefixIcon: Icon(Icons.search),
                  ),
                  textInputAction: TextInputAction.search,
                  onFieldSubmitted: (v) => setState(() {
                    keyword = v.trim();
                    selected = null;
                  }),
                ),
              ),
              IconButton(
                tooltip: '목록 새로고침',
                onPressed: () => ref.invalidate(operationsDataProvider(path)),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: RecordsView(
            path: path,
            builder: (data) {
              final rows = (data['results'] as List? ?? [])
                  .cast<Map<String, dynamic>>();
              if (rows.isEmpty) {
                return const Center(child: Text('검색 결과가 없습니다.'));
              }
              final idKey = widget.managers ? 'm_id' : 'c_id_seq';
              final nameKey = widget.managers ? 'm_name' : 'c_name';
              final id = selected ?? '${rows.first[idKey]}';
              return AdminSplitView(
                selected: selected != null,
                onBack: () => setState(() => selected = null),
                list: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '전체 ${data['total'] ?? rows.length}명',
                        style: const TextStyle(color: AdminStyle.muted),
                      ),
                    ),
                    for (final r in rows)
                      Material(
                        color: id == '${r[idKey]}'
                            ? AdminStyle.selected
                            : Colors.white,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: AdminStyle.canvas,
                            child: Text('${r[nameKey]}'.characters.first),
                          ),
                          title: Text(
                            '${r[nameKey]}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${r[idKey]} · ${widget.managers ? '제재 ${r['sanction_count'] ?? '—'}건' : '경기 ${r['match_count'] ?? '—'}회 · 경고 ${r['warning_count'] ?? '—'}회'}',
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => setState(() => selected = '${r[idKey]}'),
                        ),
                      ),
                  ],
                ),
                detail: RecordsView(
                  path: '/management/$category/${Uri.encodeComponent(id)}',
                  builder: (record) => ListView(
                    padding: const EdgeInsets.all(22),
                    children: [
                      AdminCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            adminTitle('${record[nameKey] ?? '상세 정보'}'),
                            const SizedBox(height: 12),
                            RecordDetails(
                              record: {
                                for (final e in record.entries)
                                  if (e.value is! List) e.key: e.value,
                              },
                            ),
                          ],
                        ),
                      ),
                      for (final e in record.entries)
                        if (e.value is List)
                          AdminCard(
                            child: RecordDetails(record: {e.key: e.value}),
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
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
