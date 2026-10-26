// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vm/match_notifier.dart';
import '../shared/records_view.dart';

class GroundPage extends ConsumerWidget {
  const GroundPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(24),
        child: TextFormField(
          decoration: const InputDecoration(
            labelText: '구장명 · 주소 검색',
            prefixIcon: Icon(Icons.search),
          ),
          onFieldSubmitted: (value) =>
              ref.read(groundListProvider.notifier).searchGrounds(value),
        ),
      ),
      Expanded(
        child: ref
            .watch(groundListProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('구장을 불러올 수 없습니다. 서버의 구장 조회 API 연결을 확인해 주세요.'),
                    OutlinedButton(
                      onPressed: () => ref
                          .read(groundListProvider.notifier)
                          .refreshGrounds(),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
              data: (grounds) => grounds.isEmpty
                  ? const Center(child: Text('등록된 구장이 없습니다.'))
                  : ListView(
                      children: grounds
                          .map(
                            (ground) => Card(
                              child: ListTile(
                                title: Text(ground.g_name),
                                subtitle: Text(ground.g_address),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => Consumer(
                                      builder: (context, ref, child) => Scaffold(
                                        appBar: AppBar(
                                          title: Text(ground.g_name),
                                        ),
                                        body: ref
                                            .watch(
                                              groundDetailProvider(
                                                ground.g_code,
                                              ),
                                            )
                                            .when(
                                              loading: () => const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                              error: (error, stack) =>
                                                  Center(child: Text('$error')),
                                              data: (detail) =>
                                                  SingleChildScrollView(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          24,
                                                        ),
                                                    child: RecordDetails(
                                                      record: detail.toJson(),
                                                    ),
                                                  ),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
      ),
    ],
  );
}
// 최종 수정일 : 2026-10-24
