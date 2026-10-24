// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';

import '../../model/login_role.dart';
import 'login_page.dart';

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.sports_soccer,
                  size: 44,
                  color: Color(0xFF34734F),
                ),
                const SizedBox(height: 16),
                const Text(
                  '공IN 중개사',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 52),
                const Text(
                  '함께 뛰는 즐거움,\n운영의 시작은 여기서.',
                  style: TextStyle(
                    fontSize: 36,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF203B2B),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '담당 역할을 선택하고 로그인해 주세요.',
                  style: TextStyle(fontSize: 16, color: Color(0xFF68756C)),
                ),
                const SizedBox(height: 32),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = LoginRole.values
                        .map(
                          (role) => SizedBox(
                            width: constraints.maxWidth < 620
                                ? constraints.maxWidth
                                : (constraints.maxWidth - 20) / 2,
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              elevation: 0,
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                                side: const BorderSide(
                                  color: Color(0xFFDCE5DB),
                                ),
                              ),
                              child: InkWell(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => LoginPage(role: role),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(28),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        role == LoginRole.headquarters
                                            ? Icons.business_outlined
                                            : Icons.sports_outlined,
                                        size: 36,
                                        color: const Color(0xFF34734F),
                                      ),
                                      const SizedBox(height: 28),
                                      Text(
                                        role.label,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        role == LoginRole.headquarters
                                            ? '회원과 매니저를 관리하는 본사 전용 공간'
                                            : '현장 운영을 함께하는 매니저 전용 공간',
                                        style: const TextStyle(
                                          color: Color(0xFF68756C),
                                        ),
                                      ),
                                      const SizedBox(height: 28),
                                      const Row(
                                        children: [
                                          Text(
                                            '로그인하기',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Spacer(),
                                          Icon(Icons.arrow_forward),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList();
                    return Wrap(spacing: 20, runSpacing: 16, children: cards);
                  },
                ),
                const SizedBox(height: 36),
                const Text(
                  'GONGIN  /  OPERATIONS',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: Color(0xFF68756C),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
// 최종 수정일 : 2026-10-24
