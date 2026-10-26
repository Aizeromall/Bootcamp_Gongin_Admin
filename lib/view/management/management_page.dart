// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/records_view.dart';
import '../../service/operations_api.dart';

class ManagementPage extends ConsumerStatefulWidget {
  const ManagementPage({super.key, required this.managers});
  final bool managers;
  @override
  ConsumerState<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends ConsumerState<ManagementPage> {
  String keyword = '';
  @override
  Widget build(BuildContext context) {
    final category = widget.managers ? 'managers' : 'members';
    final path =
        '/management/$category?keyword=${Uri.encodeQueryComponent(keyword)}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: TextFormField(
            decoration: const InputDecoration(
              labelText: '이름 · 아이디 · 전화번호 검색',
              prefixIcon: Icon(Icons.search),
            ),
            textInputAction: TextInputAction.search,
            onFieldSubmitted: (value) => setState(() => keyword = value.trim()),
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
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(operationsDataProvider(path));
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final id = '${row[widget.managers ? 'm_id' : 'c_id_seq']}';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            widget.managers
                                ? Icons.badge_outlined
                                : Icons.person_outline,
                          ),
                        ),
                        title: Text(
                          '${row[widget.managers ? 'm_name' : 'c_name']}',
                        ),
                        subtitle: Text(
                          '$id · ${widget.managers ? '제재 ${row['sanction_count'] ?? 0}건' : '경기 ${row['match_count'] ?? 0}회 / 경고 ${row['warning_count'] ?? 0}회'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              appBar: AppBar(
                                title: Text(
                                  widget.managers ? '매니저 상세' : '회원 상세',
                                ),
                              ),
                              body: RecordsView(
                                path:
                                    '/management/$category/${Uri.encodeComponent(id)}',
                                builder: (record) => SingleChildScrollView(
                                  padding: const EdgeInsets.all(24),
                                  child: RecordDetails(record: record),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
// 최종 수정일 : 2026-10-24
