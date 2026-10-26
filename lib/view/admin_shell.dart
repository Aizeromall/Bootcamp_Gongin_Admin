// [이 파일의 역할]
// 로그인 후 보이는 메인 틀 : 왼쪽 사이드바 + 오른쪽 내용 영역 (iPad 가로 화면 기준)
//   본사 관리자 : 회원 관리 / 문의 내역
//   매치 매니저 : 내 매치
// 사이드바 메뉴 위치는 adminNavProvider, 로그인 정보는 adminSessionProvider(Riverpod)에서 가져옴

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../vm/admin_auth_notifier.dart';
import 'auth/admin_login_page.dart';
import 'common/app_theme.dart';
import 'hq/inquiry_page.dart';
import 'hq/member_page.dart';
import 'manager/my_match_page.dart';

// 사이드바 메뉴 1개 정의 : 아이콘 + 이름 + 눌렀을 때 보여줄 화면
class _NavItem {
  final IconData icon;
  final String label;
  final Widget page;
  const _NavItem(this.icon, this.label, this.page);
}

// 역할별 메뉴 목록
List<_NavItem> _navItemsFor(AdminRole role) {
  switch (role) {
    case AdminRole.hq:
      return const [
        _NavItem(Icons.people_alt_outlined, '회원 관리', MemberPage()),
        _NavItem(Icons.chat_bubble_outline, '문의 내역', InquiryPage()),
      ];
    case AdminRole.manager:
      return const [
        _NavItem(Icons.sports_soccer, '내 매치', MyMatchPage()),
      ];
  }
}

class AdminShell extends ConsumerWidget {
  const AdminShell({super.key});

  // 로그아웃 : 확인 후 세션을 비우고 로그인 화면으로 이동(이전 화면은 모두 제거)
  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('로그아웃할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('로그아웃', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    ref.read(adminSessionProvider.notifier).logout();
    ref.read(adminNavProvider.notifier).go(0);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AdminLoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminSessionProvider);
    final navIndex = ref.watch(adminNavProvider);

    // 세션이 없으면(로그아웃 직후 등) 빈 화면 (곧 로그인 화면으로 교체됨)
    if (session == null) return const Scaffold();

    final items = _navItemsFor(session.role);
    // 역할이 바뀌어 메뉴 수가 줄었을 때 범위를 벗어나지 않게 보정
    final index = navIndex.clamp(0, items.length - 1);

    return Scaffold(
      body: Row(
        children: [
          // ---------- 왼쪽 사이드바 ----------
          Container(
            width: 220,
            color: AppColors.sidebar,
            padding: const EdgeInsets.fromLTRB(14, 24, 14, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 앱 이름
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                      children: [
                        TextSpan(text: '공'),
                        TextSpan(text: 'In', style: TextStyle(color: Color(0xFF7FE0AE))),
                        TextSpan(text: '중개사'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                // 역할 표시
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(session.role.label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.sidebarText)),
                ),
                const SizedBox(height: 8),
                // 메뉴 목록 : 선택된 항목은 밝은 배경
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => ref.read(adminNavProvider.notifier).go(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: i == index ? AppColors.sidebarSelected : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(items[i].icon,
                                size: 20, color: i == index ? Colors.white : AppColors.sidebarText),
                            const SizedBox(width: 12),
                            Text(items[i].label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                                  color: i == index ? Colors.white : AppColors.sidebarText,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                // 로그인 정보 + 로그아웃
                const Divider(color: AppColors.sidebarSelected),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.id,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(session.role.label,
                          style: const TextStyle(fontSize: 12, color: AppColors.sidebarText)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _logout(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.sidebarSelected),
                    minimumSize: const Size.fromHeight(42),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('로그아웃'),
                ),
              ],
            ),
          ),
          // ---------- 오른쪽 내용 영역 ----------
          // IndexedStack : 메뉴를 바꿔도 각 화면의 검색어·선택 상태가 유지됨
          Expanded(
            child: IndexedStack(
              index: index,
              children: [for (final item in items) item.page],
            ),
          ),
        ],
      ),
    );
  }
}
