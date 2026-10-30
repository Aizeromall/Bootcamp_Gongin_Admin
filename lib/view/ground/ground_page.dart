// 작업자 : 최현준 / 작업 일 : 2026-10-24
// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 실제 구장 조회 계약을 사용하고 관리자 디자인의 목록·상세 배치를 공유합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vm/match_notifier.dart';
import '../headquarters/admin_components.dart';
import '../shared/admin_split_view.dart';
import '../shared/admin_style.dart';

class GroundPage extends ConsumerStatefulWidget {
  const GroundPage({super.key});
  @override
  ConsumerState<GroundPage> createState() => _GroundPageState();
}

class _GroundPageState extends ConsumerState<GroundPage> {
  String? selected;
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void submit(String value) {
    setState(() => selected = null);
    ref.read(groundKeywordProvider.notifier).select(value);
  }

  Widget failure(VoidCallback retry) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('구장 정보를 불러올 수 없습니다.'),
        TextButton(onPressed: retry, child: const Text('다시 시도')),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => AdminSplitView(
    selected: selected != null,
    onBack: () => setState(() => selected = null),
    list: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: TextField(
            controller: search,
            onSubmitted: submit,
            decoration: InputDecoration(
              labelText: '구장명 · 주소 검색',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: '검색',
                onPressed: () => submit(search.text),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ),
        Expanded(
          child: ref
              .watch(groundListProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) =>
                    failure(() => ref.invalidate(groundListProvider)),
                data: (grounds) => grounds.isEmpty
                    ? const Center(child: Text('검색된 구장이 없습니다.'))
                    : ListView.separated(
                        itemCount: grounds.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AdminStyle.line),
                        itemBuilder: (_, index) {
                          final ground = grounds[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            selected: selected == ground.g_code,
                            selectedTileColor: AdminStyle.selected,
                            title: Text(
                              ground.g_name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(ground.g_address),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () =>
                                setState(() => selected = ground.g_code),
                          );
                        },
                      ),
              ),
        ),
      ],
    ),
    detail: selected == null
        ? const Center(child: Text('구장을 선택하면 상세 정보를 확인할 수 있습니다.'))
        : ref
              .watch(groundDetailProvider(selected!))
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => failure(
                  () => ref.invalidate(groundDetailProvider(selected!)),
                ),
                data: (ground) => SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdminCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            adminBadge('구장 정보'),
                            const SizedBox(height: 12),
                            adminTitle(ground.g_name),
                            const SizedBox(height: 12),
                            Text(
                              ground.g_address,
                              style: const TextStyle(color: AdminStyle.muted),
                            ),
                          ],
                        ),
                      ),
                      AdminCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            adminTitle('이용 안내'),
                            const SizedBox(height: 12),
                            adminFields({
                              '수용 인원': '${ground.g_num}명',
                              '이용 금액': '${ground.g_price}원',
                              '이용 정보': ground.g_information,
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
  );
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
