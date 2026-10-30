// 수정 일 : 2026-10-27 / 작업자 : 양태건
// Figma 3:32의 212px 사이드바·선택 행·하단 담당자 영역입니다.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../vm/headquarters_notifier.dart';

import 'admin_style.dart';

class EducationShell extends ConsumerWidget {
  const EducationShell({
    super.key,
    required this.child,
    required this.headquarters,
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onSelected,
    required this.userId,
    this.userName,
    this.department,
    required this.onLogout,
  });
  final Widget child;
  // 수정 일 : 2026-10-29 / 작업자 : 양태건
  // 메뉴 수가 바뀌어도 본사 배지·정렬·아이콘을 유지합니다.
  final bool headquarters;
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onSelected;
  final String userId;
  final String? userName, department;
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: AdminStyle.canvas,
    // 수정 일 : 2026-10-27 / 작업자 : 양태건
    // 기존 본사 화면도 밝은 배경과 파란 동작 색상을 공유합니다.
    body: Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: AdminStyle.blue)
            .copyWith(primary: AdminStyle.blue, surface: Colors.white),
        dividerColor: AdminStyle.line,
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: AdminStyle.line),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (constraints.maxWidth >= 760)
                SizedBox(
                  width: 212,
                  child: ColoredBox(
                    color: AdminStyle.ink,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(60, 24, 12, 20),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '공'),
                                TextSpan(
                                  text: 'In',
                                  style: TextStyle(color: Color(0xFF5EA2FF)),
                                ),
                                TextSpan(text: '중개사'),
                              ],
                            ),
                            style: TextStyle(
                              fontFamily: 'IBM Plex Sans KR',
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
                          child: Text(
                            headquarters ? '본사 관리자' : '매치 매니저',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              color: AdminStyle.sidebarMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              for (final i
                                  in headquarters
                                      ? [
                                          6,
                                          12,
                                          10,
                                          11,
                                          2,
                                          4,
                                          8,
                                          5,
                                          0,
                                          1,
                                          9,
                                          3,
                                          7,
                                        ]
                                      : List.generate(labels.length, (i) => i))
                                Material(
                                  color: selected == i
                                      ? AdminStyle.sidebarSelected
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    key: ValueKey(
                                      i == 5
                                          ? 'nav-education'
                                          : 'education-nav-$i',
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => onSelected(i),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 9.5,
                                      ),
                                      child: Row(
                                        children: [
                                          _icon(i),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              labels[i],
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: selected == i
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: selected == i
                                                    ? Colors.white
                                                    : AdminStyle.sidebarText,
                                              ),
                                            ),
                                          ),
                                          _count(i, ref),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Divider(
                                height: 1,
                                color: Color(0xFF2A3A5E),
                              ),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  userName ?? userId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  '$userId${department == null ? '' : ' · $department'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AdminStyle.sidebarMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AdminStyle.sidebarText,
                                  side: const BorderSide(
                                    color: Color(0xFF33456D),
                                  ),
                                  minimumSize: const Size(0, 35),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: onLogout,
                                child: const Text(
                                  '로그아웃',
                                  style: TextStyle(fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: MediaQuery.sizeOf(context).width < 760
        ? SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: const ValueKey('mobile-admin-menu'),
                  isExpanded: true,
                  value: selected,
                  items: [
                    for (var i = 0; i < labels.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Row(
                          children: [
                            Icon(icons[i], size: 20),
                            const SizedBox(width: 12),
                            Text(labels[i]),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) onSelected(value);
                  },
                ),
              ),
            ),
          )
        : null,
  );
  // 수정 일 : 2026-10-27 / 작업자 : 양태건
  // 서버에서 조회된 대기 건수만 배지로 표시하고 조회 실패를 0건으로 숨기지 않습니다.
  Widget _count(int index, WidgetRef ref) {
    if (!headquarters) return const SizedBox.shrink();
    final path = switch (index) {
      2 => '/inquiry/list',
      4 => '/report/list',
      8 => '/appeal/list',
      5 => '/education/courses',
      _ => null,
    };
    if (path == null) return const SizedBox.shrink();
    final data = ref
        .watch(adminDataProvider((staffId: userId, path: path)))
        .asData
        ?.value;
    if (data == null) return const SizedBox.shrink();
    final count = index == 2
        ? [
            ...data.rows,
            ...data.rows.expand((r) => adminRows(r['follow_ups'])),
          ].where((r) => '${r['i_state']}' != '1').length
        : data.number(index == 5 ? 'required_pending' : 'pending_count');
    if (count == null || count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AdminStyle.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _icon(int i) {
    if (!headquarters) {
      return Icon(
        icons[i],
        size: 18,
        color: selected == i ? Colors.white : AdminStyle.sidebarText,
      );
    }
    final asset = switch (i) {
      0 => 'members',
      2 => 'inquiries',
      4 => 'reports',
      5 => 'education',
      _ => null,
    };
    return asset == null
        ? Icon(icons[i], size: 18, color: AdminStyle.sidebarText)
        : SvgPicture.asset(
            'assets/figma/admin/$asset.svg',
            width: 18,
            height: 18,
            colorFilter: ColorFilter.mode(
              selected == i ? Colors.white : AdminStyle.sidebarText,
              BlendMode.srcIn,
            ),
          );
  }
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건
