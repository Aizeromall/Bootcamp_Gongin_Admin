import '../shared/async_screen_state.dart';

// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vm/login_notifier.dart';
import '../dashboard/dashboard_page.dart';
import '../shared/admin_style.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with AsyncScreenState<LoginPage> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {'_obscure': true};
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  final _form = GlobalKey<FormState>();
  late final _id = screenTextController('_id');
  late final _password = screenTextController('_password');
  bool get _obscure => screenValue<bool>('_obscure');
  set _obscure(bool value) => setScreenValue('_obscure', value);

  @override
  void dispose() {
    _id.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(loginProvider).isLoading || !_form.currentState!.validate()) {
      return;
    }
    await ref.read(loginProvider.notifier).login(_id.text, _password.text);
    if (!mounted) return;
    if (ref.read(loginProvider).value != null) {
      _password.clear();
      updateScreen(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    watchScreen();
    final state = ref.watch(loginProvider);
    final loggedIn = state.asData?.value;
    if (loggedIn != null) {
      return DashboardPage(
        key: ValueKey('${loggedIn.role.name}:${loggedIn.userId}'),
        role: loggedIn.role,
        userId: loggedIn.userId,
        userName: loggedIn.name,
        // 작업자 : 양태건
        // 수정일 : 2026-10-26
        // 인증된 부서를 담당자 표시 영역에 전달합니다.
        department: loggedIn.department,
        onLogout: () => ref.read(loginProvider.notifier).reset(),
      );
    }
    return PopScope(
      canPop: !state.isLoading,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) ref.read(loginProvider.notifier).reset();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final login = Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(
                              Icons.sports_soccer,
                              size: 40,
                              color: AdminStyle.blue,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '담당자 로그인',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              '발급받은 아이디와 비밀번호를 입력해 주세요.',
                              style: TextStyle(color: AdminStyle.muted),
                            ),
                            const SizedBox(height: 32),
                            TextFormField(
                              controller: _id,
                              enabled: !state.isLoading,
                              decoration: const InputDecoration(
                                labelText: '아이디',
                              ),
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  (value ?? '')
                                      .replaceAll(RegExp(r'\s'), '')
                                      .isEmpty
                                  ? '아이디를 입력해 주세요.'
                                  : null,
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _password,
                              enabled: !state.isLoading,
                              obscureText: _obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: '비밀번호',
                                suffixIcon: IconButton(
                                  tooltip: _obscure ? '비밀번호 표시' : '비밀번호 숨기기',
                                  onPressed: () =>
                                      updateScreen(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              onFieldSubmitted: (_) => _submit(),
                              validator: (value) =>
                                  (value ?? '')
                                      .replaceAll(RegExp(r'\s'), '')
                                      .isEmpty
                                  ? '비밀번호를 입력해 주세요.'
                                  : null,
                            ),
                            if (state.hasError)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  state.error.toString().replaceFirst(
                                    'Exception: ',
                                    '',
                                  ),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 28),
                            FilledButton(
                              onPressed: state.isLoading ? null : _submit,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.all(20),
                              ),
                              child: state.isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('로그인'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
              if (constraints.maxWidth < 760) return login;
              return Row(
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: AdminStyle.ink,
                      child: Padding(
                        padding: const EdgeInsets.all(42),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Spacer(),
                            const Text(
                              '공In중개사\n관리자',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '본사와 경기매니저의 운영 업무를 한 곳에서 확인하세요.',
                              style: TextStyle(
                                color: AdminStyle.sidebarText,
                                fontSize: 14,
                                height: 1.8,
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              '계정에 부여된 권한에 따라 담당 업무가 표시됩니다.',
                              style: TextStyle(
                                color: AdminStyle.sidebarMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: login),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
// 최종 수정일 : 2026-10-24

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
