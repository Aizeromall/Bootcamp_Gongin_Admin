// ###  2026.10.23 문의 관리 Riverpod 상태관리 구성
//
// [이 파일의 역할]
// 본사 관리자 앱 "문의 내역" 화면의 목록 조회(필터), 선택한 문의, 상세 조회, 답변 등록을 관리하는 ViewModel
//   View  : lib/view/hq/inquiry_page.dart
//   VM    : 이 파일
//
// [연결된 서버 API] (python/FastAPI/inquiry, main.py에서 /inquiry 접두사)
//   GET  /inquiry/list?i_state=      문의 목록 (미답변이 위, 오래된 순 / 그 아래 답변 완료 최신순)
//   GET  /inquiry/detail/{i_seq}     문의 상세 (추가 문의 follow_ups 포함)
//   POST /inquiry/answer             답변 등록 (Form : i_seq, h_id, inquiry_detail)
//
// 서버는 문의가 없거나 이미 답변된 경우에도 200 응답 안에 {"result": "Error", "message": ...}를 줌 → 아래에서 오류로 변환

import 'dart:async'; // FutureOr : Notifier의 build()를 동기로 반환하기 위해 사용

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/admin_inquiry_model.dart';
import 'admin_auth_notifier.dart';
import 'api_client.dart';

// ------------------------------------------------------------
// 목록 필터 (전체 / 답변 대기 / 답변 완료)
// ------------------------------------------------------------

// null = 전체, '0' = 답변 대기, '1' = 답변 완료 (서버 i_state 값)
class InquiryFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? value) => state = value;
}

final inquiryFilterProvider =
    NotifierProvider<InquiryFilterNotifier, String?>(InquiryFilterNotifier.new);

// ------------------------------------------------------------
// 문의 목록
// ------------------------------------------------------------

class AdminInquiryListNotifier extends AsyncNotifier<List<AdminInquiry>> {
  // 필터가 바뀌면 build가 다시 실행되어 목록이 자동으로 새로 조회됨
  @override
  Future<List<AdminInquiry>> build() async {
    final filter = ref.watch(inquiryFilterProvider);
    return _fetch(filter);
  }

  Future<List<AdminInquiry>> _fetch(String? filter) async {
    final data = await apiGet('/inquiry/list', query: filter == null ? null : {'i_state': filter});
    // 서버 오류가 200 응답 안에 담겨 오는 경우
    if (data is Map && data['result'] == 'Error') {
      throw ApiException('문의 목록을 불러오지 못했어요.');
    }
    final List results = data['results'] ?? [];
    return results.map((e) => AdminInquiry.fromJson(e)).toList();
  }

  // 새로고침 (답변 등록 후, 아래로 당겨서 새로고침)
  Future<void> refresh() async {
    final filter = ref.read(inquiryFilterProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(filter));
  }
}

final adminInquiryListProvider = AsyncNotifierProvider<AdminInquiryListNotifier, List<AdminInquiry>>(
  AdminInquiryListNotifier.new,
  retry: noRetry,
);

// ------------------------------------------------------------
// 선택한 문의 + 상세 조회
// ------------------------------------------------------------

class SelectedInquiryNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? iSeq) => state = iSeq;
}

final selectedInquiryProvider =
    NotifierProvider<SelectedInquiryNotifier, int?>(SelectedInquiryNotifier.new);

final adminInquiryDetailProvider =
    FutureProvider.autoDispose.family<AdminInquiry, int>((ref, iSeq) async {
  final data = await apiGet('/inquiry/detail/$iSeq');
  if (data is Map && data['result'] == 'Error') {
    throw ApiException('문의를 찾을 수 없어요.');
  }
  return AdminInquiry.fromJson(data);
}, retry: noRetry);

// ------------------------------------------------------------
// 답변 등록
// ------------------------------------------------------------

// 서버가 영어 메시지로 주는 오류를 화면용 문구로 변환
const Map<String, String> _answerErrors = {
  'inquiry not found': '문의를 찾을 수 없어요.',
  'already answered': '이미 답변이 등록된 문의예요.',
  'headquarter not found': '답변 작성자(본사 직원) 정보를 찾을 수 없어요.',
};

class InquiryAnswerController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {} // 동기 반환 : 처음부터 "대기" 상태로 시작 (async면 첫 프레임이 로딩으로 보임)

  // 답변 등록 : 로그인한 본사 관리자의 아이디를 답변 작성자(h_id)로 저장. 성공하면 true
  Future<bool> answer(int iSeq, String content) async {
    final session = ref.read(adminSessionProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (session == null) throw ApiException('로그인 정보가 없어요. 다시 로그인해주세요.');
      final data = await apiPostForm('/inquiry/answer', {
        'i_seq': '$iSeq',
        'h_id': session.id,
        'inquiry_detail': content.trim(),
      });
      if (data is Map && data['result'] != 'OK') {
        final message = '${data['message'] ?? ''}';
        throw ApiException(_answerErrors[message] ?? '답변 등록에 실패했어요.');
      }
    });
    if (state.hasError) return false;
    // 등록 후 목록과 상세를 최신으로
    ref.invalidate(adminInquiryDetailProvider(iSeq));
    ref.invalidate(adminInquiryDetailProvider);
    await ref.read(adminInquiryListProvider.notifier).refresh();
    return true;
  }
}

final inquiryAnswerControllerProvider =
    AsyncNotifierProvider<InquiryAnswerController, void>(InquiryAnswerController.new, retry: noRetry);
