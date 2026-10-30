// 수정 일 : 2026-10-28 / 작업자 : 양태건
// iPad에서는 목록과 상세를 나란히, 휴대폰에서는 선택한 상세와 복귀 버튼을 표시합니다.
import 'package:flutter/material.dart';

import 'admin_style.dart';

class AdminSplitView extends StatelessWidget {
  const AdminSplitView({
    super.key,
    required this.list,
    required this.detail,
    required this.selected,
    required this.onBack,
    this.listWidth = 360,
  });
  final Widget list, detail;
  final bool selected;
  final VoidCallback onBack;
  final double listWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth >= 850) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: listWidth,
              child: ColoredBox(color: Colors.white, child: list),
            ),
            const VerticalDivider(width: 1, color: AdminStyle.line),
            Expanded(
              child: ColoredBox(color: AdminStyle.canvas, child: detail),
            ),
          ],
        );
      }
      if (!selected) return list;
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('목록으로'),
            ),
          ),
          Expanded(child: detail),
        ],
      );
    },
  );
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
