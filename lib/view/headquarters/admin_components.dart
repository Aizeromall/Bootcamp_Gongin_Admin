// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 관리자 목업의 흰 카드·배지와 조회 오류/재시도 표현을 공유합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../vm/headquarters_notifier.dart';
import '../../service/operations_api.dart';
import '../shared/admin_style.dart';

class AdminCard extends StatelessWidget {
  const AdminCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    // 수정 일 : 2026-10-28 / 작업자 : 양태건
    // 상세의 ListTile·펼침 항목도 카드 위에서 잉크 효과를 표시합니다.
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AdminStyle.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ),
  );
}

Widget adminBadge(String value, {bool alert = false}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
  decoration: BoxDecoration(
    color: alert ? const Color(0xFFFDE8EB) : AdminStyle.selected,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(
    value,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: alert ? AdminStyle.red : AdminStyle.blue,
    ),
  ),
);
Widget adminTitle(String value) => Text(
  value,
  style: const TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: AdminStyle.ink,
  ),
);
Widget adminFields(Map<String, Object?> fields) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (final e in fields.entries)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.key,
              style: const TextStyle(fontSize: 12, color: AdminStyle.muted),
            ),
            const SizedBox(height: 4),
            SelectableText(
              adminText(e.value),
              style: const TextStyle(fontSize: 14, color: AdminStyle.ink),
            ),
          ],
        ),
      ),
  ],
);

class AdminData extends ConsumerWidget {
  const AdminData({
    super.key,
    required this.staffId,
    required this.path,
    required this.builder,
  });
  final String staffId, path;
  final Widget Function(AdminPayload) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (staffId: staffId, path: path);
    return ref
        .watch(adminDataProvider(key))
        .when(
          data: builder,
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, s) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(adminError(e)),
                TextButton(
                  onPressed: () {
                    ref.invalidate(operationsDataProvider(path));
                    ref.invalidate(adminDataProvider(key));
                  },
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        );
  }
}

Future<bool> adminConfirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확인'),
          ),
        ],
      ),
    ) ??
    false;
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
