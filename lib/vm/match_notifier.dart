// ###  2026.10.23 본사 구장 관리 - 구장 조회 Riverpod 상태관리 구성   - 신현진
//
// [이 파일의 역할]
// 본사 관리자 앱에서 전체 구장(Ground) 현황을 서버(FastAPI)로부터 가져오고 상태를 보관하는 ViewModel
// (Bootcamp_Gongin_User 앱의 vm과 동일한 로직, 주석만 본사 관리자 기준으로 정리)
//   View  : 본사 구장 관리 화면. ref.watch(...)로 상태를 구독 → 데이터가 바뀌면 화면이 자동으로 다시 그려짐
//   VM    : 이 파일. 서버 호출 + 상태(로딩/데이터/에러) 관리
//   Model : lib/model/ground_model.dart (JSON ↔ Ground 객체 변환)
//
// [연결된 서버 API] (python/FastAPI/match/ground_search.py)
//   GET /match/ground                 전체 구장 목록 (?keyword= 로 구장명/주소 검색)
//   GET /match/ground/{g_code}        구장 1건 상세
//
// [본사 관리 화면에서 사용하는 방법]
//   1) 구장 관리 목록 화면
//      final groundsAsync = ref.watch(groundListProvider);
//      groundsAsync.when(
//        data: (grounds) => ListView(...),                 // 조회 성공
//        loading: () => CircularProgressIndicator(),       // 조회 중
//        error: (error, stack) => Text('$error'),          // 조회 실패
//      );
//   2) 구장 검색 버튼 (구장명/주소로 관리 대상 구장 찾기)
//      ref.read(groundListProvider.notifier).searchGrounds('영등포');
//   3) 구장 상세 화면 (본사에서 구장 정보 확인)
//      final groundAsync = ref.watch(groundDetailProvider('1'));

// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 공통 HTTP 계층을 사용하고 검색 조건을 provider 키로 관리하여 늦은 응답을 분리합니다.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/ground_model.dart';
import '../service/operations_api.dart';
import 'login_notifier.dart';

final groundKeywordProvider = NotifierProvider<GroundKeyword, String>(
  GroundKeyword.new,
);

class GroundKeyword extends Notifier<String> {
  @override
  String build() {
    ref.watch(loginProvider);
    return '';
  }

  void select(String value) => state = value.trim();
}

final groundListProvider = FutureProvider.autoDispose<List<Ground>>((
  ref,
) async {
  final api = ref.watch(operationsApiProvider);
  final keyword = ref.watch(groundKeywordProvider);
  final path = Uri(
    path: '/match/ground',
    queryParameters: keyword.isEmpty ? null : {'keyword': keyword},
  ).toString();
  final data = await api.request(path);
  return (data['results'] as List)
      .map((row) => Ground.fromJson(Map<String, dynamic>.from(row as Map)))
      .toList();
}, retry: (_, _) => null);

final groundDetailProvider = FutureProvider.autoDispose.family<Ground, String>((
  ref,
  code,
) async {
  final data = await ref
      .watch(operationsApiProvider)
      .request('/match/ground/${Uri.encodeComponent(code)}');
  return Ground.fromJson(data);
}, retry: (_, _) => null);
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
