// ###  2026.10.23 관리자·매니저 로그인 Riverpod 상태관리 구성
//
// [이 파일의 역할]
// 로그인한 사람(본사 관리자 또는 매치 매니저)의 세션과 로그인 요청, 사이드바 메뉴 선택 위치를 관리하는 ViewModel
//   View  : lib/view/auth/admin_login_page.dart, lib/view/admin_shell.dart
//   VM    : 이 파일
//
// [연결된 서버 API] (python/FastAPI/login)
//   POST /admin/login     본사 관리자 로그인 {h_id, h_pw} → {result, h_id}
//   POST /manager/login   매치 매니저 로그인 {m_id, m_pw} → {result, m_id}
//
// 두 로그인 API 모두 아이디만 돌려주므로 화면에는 이름 대신 아이디를 표시

import 'dart:async'; // FutureOr : Notifier의 build()를 동기로 반환하기 위해 사용

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

// 로그인 역할 : 역할에 따라 사이드바 메뉴와 화면이 달라짐
enum AdminRole {
  hq('본사 관리자'),
  manager('매치 매니저');

  final String label; // 화면 표시 이름
  const AdminRole(this.label);
}

// 로그인 세션 : 역할 + 아이디 (null이면 로그아웃 상태)
class AdminSession {
  final AdminRole role;
  final String id; // 본사 관리자는 h_id, 매니저는 m_id

  const AdminSession({required this.role, required this.id});
}

class AdminSessionNotifier extends Notifier<AdminSession?> {
  // 처음에는 로그아웃 상태
  @override
  AdminSession? build() => null;

  // 로그인 성공 시 세션 저장
  void login(AdminSession session) => state = session;

  // 로그아웃 : 세션을 비움 (세션을 보고 있는 목록들은 자동으로 초기화됨)
  void logout() => state = null;
}

// 화면에서 세션에 접근하는 Provider
//   ref.watch(adminSessionProvider)                    → 현재 세션 구독
//   ref.read(adminSessionProvider.notifier).logout()   → 함수 호출
final adminSessionProvider =
    NotifierProvider<AdminSessionNotifier, AdminSession?>(AdminSessionNotifier.new);

// ------------------------------------------------------------
// 로그인 요청
// ------------------------------------------------------------

// 로그인 API 호출 상태 (대기 / 로딩 / 오류). 화면은 이 상태로 버튼 로딩과 오류 문구를 표시
class AdminLoginController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {} // 동기 반환 : 처음부터 "대기" 상태로 시작 (async면 첫 프레임이 로딩으로 보임)

  // 로그인 요청 : 성공하면 세션에 저장하고 true, 실패하면 오류를 state에 담고 false
  Future<bool> login(AdminRole role, String id, String pw) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final trimmedId = id.trim();
      // 역할에 따라 서버 주소와 요청 필드 이름이 다름
      final data = role == AdminRole.hq
          ? await apiPost('/admin/login', {'h_id': trimmedId, 'h_pw': pw})
          : await apiPost('/manager/login', {'m_id': trimmedId, 'm_pw': pw});
      final loginId = (role == AdminRole.hq ? data['h_id'] : data['m_id']) ?? trimmedId;
      ref.read(adminNavProvider.notifier).go(0); // 새로 로그인하면 첫 메뉴부터
      ref.read(adminSessionProvider.notifier).login(AdminSession(role: role, id: '$loginId'));
    });
    return !state.hasError;
  }
}

final adminLoginControllerProvider =
    AsyncNotifierProvider<AdminLoginController, void>(AdminLoginController.new, retry: noRetry);

// ------------------------------------------------------------
// 사이드바 메뉴 위치
// ------------------------------------------------------------

class AdminNavNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void go(int index) => state = index;
}

final adminNavProvider = NotifierProvider<AdminNavNotifier, int>(AdminNavNotifier.new);
