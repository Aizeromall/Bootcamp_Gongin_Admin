// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../model/login_role.dart';

// 2026-10-26: 인증된 담당자와 역할을 한 세션에 보관합니다.
// 작업자 : 양태건
// 수정일 : 2026-10-26
// [수정 시작] 인증 토큰을 담당자 세션에 함께 보관합니다.
class StaffSession {
  const StaffSession({
    required this.userId,
    required this.role,
    this.name,
    this.accessToken,
    this.department,
  });
  final String userId;
  final LoginRole role;
  final String? name;
  final String? accessToken;
  final String? department;
}

final loginClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final loginProvider =
    NotifierProvider<LoginNotifier, AsyncValue<StaffSession?>>(
      LoginNotifier.new,
    );

class LoginNotifier extends Notifier<AsyncValue<StaffSession?>> {
  @override
  AsyncValue<StaffSession?> build() => const AsyncData(null);

  // DB 환경변수는 앱에 포함하지 않습니다. API 주소만 빌드 인자로 전달합니다.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // 역할 선택 없이 두 로그인 API의 인증 결과로 화면을 결정합니다.
  // 동일 자격증명이 양쪽에서 인증되면 임의로 본사 권한을 선택하지 않습니다.
  Future<StaffSession?> _authenticate(
    LoginRole role,
    String id,
    String password,
  ) async {
    final response = await ref
        .read(loginClientProvider)
        .post(
          Uri.parse(
            '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/${role.path}/login',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            '${role.fieldPrefix}_id': id.replaceAll(RegExp(r'\s'), ''),
            '${role.fieldPrefix}_pw': password.replaceAll(RegExp(r'\s'), ''),
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 401) return null;
    if (response.statusCode != 200) {
      throw Exception(switch (response.statusCode) {
        400 || 422 => '아이디와 비밀번호를 확인해 주세요.',
        503 => '로그인 서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.',
        _ => '로그인 처리에 실패했습니다. 잠시 후 다시 시도해 주세요.',
      });
    }
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final userId = data['${role.fieldPrefix}_id'];
    // 작업자 : 양태건
    // 수정일 : 2026-10-26
    // [수정 시작] 서버 역할과 매니저 부서가 일치해야 해당 화면으로 진입합니다.
    final returnedRole = data['role'];
    if (data['result'] != 'OK' ||
        userId is! String ||
        userId.isEmpty ||
        returnedRole != role.name ||
        (role == LoginRole.manager && data['m_department'] != '매니저')) {
      throw Exception('로그인 응답을 확인할 수 없습니다.');
    }
    // 이름과 인증 토큰은 서버가 반환한 값을 사용합니다.
    final name = data['${role.fieldPrefix}_name'];
    return StaffSession(
      userId: userId,
      role: role,
      name: name is String && name.isNotEmpty ? name : null,
      accessToken: data['access_token'] as String?,
      department: data['${role.fieldPrefix}_department'] as String?,
    );
  }

  Future<void> login(String id, String password) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    try {
      final results = await Future.wait([
        for (final role in LoginRole.values) _authenticate(role, id, password),
      ]);
      final sessions = results.whereType<StaffSession>().toList();
      if (sessions.isEmpty) {
        throw Exception('아이디 또는 비밀번호가 올바르지 않습니다.');
      }
      if (sessions.length != 1) {
        throw Exception('본사와 매니저에 동일한 로그인 정보가 등록되어 있습니다. 계정 담당자에게 문의해 주세요.');
      }
      state = AsyncData(sessions.single);
    } on TimeoutException catch (error, stack) {
      state = AsyncError(Exception('응답 시간이 초과되었습니다. 다시 시도해 주세요.'), stack);
    } on http.ClientException catch (error, stack) {
      state = AsyncError(Exception('서버 연결을 확인해 주세요.'), stack);
    } catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }

  void reset() => state = const AsyncData(null);
}
// 최종 수정일 : 2026-10-24

// [수정 끝]
