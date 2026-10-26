// ###  2026.10.23 회원·매니저 관리 Riverpod 상태관리 구성
//
// [이 파일의 역할]
// 본사 관리자 앱 "회원 관리" 화면의 목록 조회·검색, 선택한 항목, 상세 조회를 관리하는 ViewModel
//   View  : lib/view/hq/member_page.dart
//   VM    : 이 파일
//
// [연결된 서버 API] (python/FastAPI/management)
//   GET /management/members?keyword=       회원 목록 + 전체 인원(total)
//   GET /management/members/{c_id_seq}     회원 상세 (제재 이력, 받은 신고 포함)
//   GET /management/managers?keyword=      매니저 목록 + 전체 인원(total)
//   GET /management/managers/{m_id}        매니저 상세 (배정·평가·제재·채용 포함)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/management_model.dart';
import 'api_client.dart';

// ------------------------------------------------------------
// 회원 / 매니저 탭 선택
// ------------------------------------------------------------

enum MgmtTab { member, manager }

class MgmtTabNotifier extends Notifier<MgmtTab> {
  @override
  MgmtTab build() => MgmtTab.member;

  void select(MgmtTab tab) => state = tab;
}

final mgmtTabProvider = NotifierProvider<MgmtTabNotifier, MgmtTab>(MgmtTabNotifier.new);

// ------------------------------------------------------------
// 회원 목록 (조회 + 검색)
// ------------------------------------------------------------

class MemberListNotifier extends AsyncNotifier<MemberList> {
  // 현재 검색어 (새로고침할 때 같은 조건을 유지하기 위해 보관)
  String _keyword = '';

  // 화면에 처음 들어오면 전체 회원이 자동으로 조회됨
  @override
  Future<MemberList> build() => _fetch(_keyword);

  Future<MemberList> _fetch(String keyword) async {
    final data = await apiGet(
      '/management/members',
      query: keyword.isEmpty ? null : {'keyword': keyword},
    );
    return MemberList.fromJson(data);
  }

  // 검색 (이름·아이디·전화번호). 빈 문자열이면 전체 목록
  Future<void> search(String keyword) async {
    _keyword = keyword.trim();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(_keyword));
  }

  // 새로고침 (검색어 유지)
  Future<void> refresh() => search(_keyword);
}

final memberListProvider =
    AsyncNotifierProvider<MemberListNotifier, MemberList>(MemberListNotifier.new, retry: noRetry);

// ------------------------------------------------------------
// 매니저 목록 (조회 + 검색)
// ------------------------------------------------------------

class ManagerListNotifier extends AsyncNotifier<ManagerList> {
  String _keyword = '';

  @override
  Future<ManagerList> build() => _fetch(_keyword);

  Future<ManagerList> _fetch(String keyword) async {
    final data = await apiGet(
      '/management/managers',
      query: keyword.isEmpty ? null : {'keyword': keyword},
    );
    return ManagerList.fromJson(data);
  }

  Future<void> search(String keyword) async {
    _keyword = keyword.trim();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(_keyword));
  }

  Future<void> refresh() => search(_keyword);
}

final managerListProvider =
    AsyncNotifierProvider<ManagerListNotifier, ManagerList>(ManagerListNotifier.new, retry: noRetry);

// ------------------------------------------------------------
// 선택한 항목 (목록에서 누른 회원/매니저의 아이디)
// ------------------------------------------------------------

class SelectedIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedMemberIdProvider =
    NotifierProvider<SelectedIdNotifier, String?>(SelectedIdNotifier.new);
final selectedManagerIdProvider =
    NotifierProvider<SelectedIdNotifier, String?>(SelectedIdNotifier.new);

// ------------------------------------------------------------
// 상세 조회 (아이디가 같으면 결과를 재사용)
// ------------------------------------------------------------

final memberDetailProvider =
    FutureProvider.autoDispose.family<MemberDetail, String>((ref, cIdSeq) async {
  final data = await apiGet('/management/members/$cIdSeq');
  return MemberDetail.fromJson(data);
}, retry: noRetry);

final managerDetailProvider =
    FutureProvider.autoDispose.family<ManagerDetail, String>((ref, mId) async {
  final data = await apiGet('/management/managers/$mId');
  return ManagerDetail.fromJson(data);
}, retry: noRetry);
