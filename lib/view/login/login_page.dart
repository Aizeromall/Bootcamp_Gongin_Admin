// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vm/login_notifier.dart';
import '../dashboard/dashboard_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _id.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await ref.read(loginProvider.notifier).login(_id.text, _password.text);
    if (!mounted) return;
    if (ref.read(loginProvider).value != null) {
      _password.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
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
        appBar: AppBar(
          title: const Text('공IN 중개사'),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.sports_soccer,
                            size: 40,
                            color: Color(0xFF34734F),
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
                            style: TextStyle(color: Color(0xFF68756C)),
                          ),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _id,
                            enabled: !state.isLoading,
                            decoration: const InputDecoration(labelText: '아이디'),
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
                                    setState(() => _obscure = !_obscure),
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
            ),
          ),
        ),
      ),
    );
  }
}
// 최종 수정일 : 2026-10-24
