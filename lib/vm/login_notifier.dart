// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../model/login_role.dart';

final loginProvider = NotifierProvider<LoginNotifier, AsyncValue<String?>>(
  LoginNotifier.new,
);

class LoginNotifier extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() => const AsyncData(null);

  // DB 환경변수는 앱에 포함하지 않습니다. API 주소만 빌드 인자로 전달합니다.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  Future<void> login(LoginRole role, String id, String password) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    try {
      final response = await http
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
      if (response.statusCode != 200) {
        final message = switch (response.statusCode) {
          400 || 422 => '아이디와 비밀번호를 확인해 주세요.',
          401 => '아이디 또는 비밀번호가 올바르지 않습니다.',
          503 => '로그인 서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.',
          _ => '로그인 처리에 실패했습니다. 잠시 후 다시 시도해 주세요.',
        };
        throw Exception(message);
      }
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final userId = data['${role.fieldPrefix}_id'];
      if (data['result'] != 'OK' || userId is! String) {
        throw Exception('로그인 응답을 확인할 수 없습니다.');
      }
      // 현재 API는 토큰을 발급하지 않으므로 비밀번호나 영구 세션은 저장하지 않습니다.
      state = AsyncData(userId);
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
