// [이 파일의 역할]
// 관리자 앱 로그인 화면 : 본사 관리자 / 매치 매니저 탭을 고르고 아이디·비밀번호로 로그인
//   - 왼쪽 : 서비스 소개 영역 (넓은 화면에서만 표시)
//   - 오른쪽 : 역할 탭 + 입력 폼 + 로그인 버튼
// 로그인에 성공하면 AdminShell(사이드바가 있는 메인 화면)로 이동
// 상태관리 : adminLoginControllerProvider(요청 상태), adminSessionProvider(로그인 정보)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vm/admin_auth_notifier.dart';
import '../admin_shell.dart';
import '../common/app_theme.dart';
import '../common/common_widgets.dart';

class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final _idController = TextEditingController();
  final _pwController = TextEditingController();
  // 현재 선택한 역할 탭 (화면 안에서만 쓰는 값이라 로컬 상태로 관리)
  AdminRole _role = AdminRole.hq;

  // 아이디·비밀번호를 모두 입력했을 때만 로그인 버튼 활성화
  bool get _canSubmit => _idController.text.trim().isNotEmpty && _pwController.text.isNotEmpty;

  @override
  void dispose() {
    _idController.dispose();
    _pwController.dispose();
    super.dispose();
  }

  // 로그인 버튼 : 성공하면 메인 화면으로 이동(이전 화면은 모두 제거). 실패 문구는 버튼 위에 표시됨
  Future<void> _login() async {
    final ok = await ref
        .read(adminLoginControllerProvider.notifier)
        .login(_role, _idController.text, _pwController.text);
    if (ok && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AdminShell()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(adminLoginControllerProvider);
    final width = MediaQuery.of(context).size.width;
    // 화면 너비가 900 이상(iPad 가로)일 때만 왼쪽 소개 영역을 보여줌
    final showHero = width >= 900;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Row(
        children: [
          if (showHero) const Expanded(flex: 11, child: _HeroPanel()),
          Expanded(
            flex: 10,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('로그인', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('역할을 선택하고 로그인해주세요',
                          style: TextStyle(fontSize: 14, color: AppColors.textSub)),
                      const SizedBox(height: 24),
                      // 역할 탭 (본사 관리자 / 매치 매니저)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            for (final role in AdminRole.values)
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(9),
                                  onTap: () => setState(() => _role = role),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _role == role ? AppColors.surface : Colors.transparent,
                                      borderRadius: BorderRadius.circular(9),
                                      border: _role == role ? Border.all(color: AppColors.line) : null,
                                    ),
                                    child: Text(role.label,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _role == role ? AppColors.primaryDark : AppColors.textSub,
                                        )),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      LabeledField(
                        label: '아이디',
                        hintText: '아이디 입력',
                        controller: _idController,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      LabeledField(
                        label: '비밀번호',
                        hintText: '비밀번호 입력',
                        controller: _pwController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (loginState.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(loginState.error.toString(),
                              style: const TextStyle(fontSize: 13, color: AppColors.danger)),
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _canSubmit && !loginState.isLoading ? _login : null,
                        child: loginState.isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : Text('${_role.label} 로그인'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 로그인 화면 왼쪽 소개 영역 (진한 초록 배경 + 로고 + 기능 소개)
class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    // 소개 문구 (역할별로 할 수 있는 일)
    const features = [
      (Icons.people_alt_outlined, '회원·매니저 관리', '가입 회원과 매니저 정보, 제재 이력을 한눈에 확인해요'),
      (Icons.question_answer_outlined, '문의 답변', '회원 문의를 확인하고 바로 답변해요'),
      (Icons.sports_soccer, '내 매치 · 경기 기록', '담당 구장의 출석을 확인하고 경기 결과를 등록해요'),
    ];

    return Container(
      color: AppColors.sidebar,
      padding: const EdgeInsets.all(48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.sidebarSelected,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.sports_soccer, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 24),
          // 앱 이름 : "In" 부분만 연한 초록색으로 강조
          const Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 38, fontWeight: FontWeight.w700, color: Colors.white),
              children: [
                TextSpan(text: '공'),
                TextSpan(text: 'In', style: TextStyle(color: Color(0xFF7FE0AE))),
                TextSpan(text: '중개사'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('관리자 대시보드', style: TextStyle(fontSize: 16, color: AppColors.sidebarText)),
          const Spacer(),
          for (final f in features) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.sidebarSelected,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(f.$1, size: 20, color: const Color(0xFF7FE0AE)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.$2,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(f.$3,
                          style: const TextStyle(fontSize: 13, color: AppColors.sidebarText, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}
