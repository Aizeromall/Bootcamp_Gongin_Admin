// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 본사 API는 기존 통신 계층을 공유하며 URL·JSON 계약을 유지합니다.
import '../model/headquarters_model.dart';
import 'operations_api.dart';

class HeadquartersService {
  HeadquartersService(this.api);
  final OperationsApi api;
  // 수정 일 : 2026-10-28 / 작업자 : 양태건
  // 문의 답변은 기존 Form 계약을 유지합니다.
  Future<void> answer(int sequence, String staffId, String text) async {
    final result = await api.request(
      '/inquiry/answer',
      form: {'i_seq': '$sequence', 'h_id': staffId, 'inquiry_detail': text},
    );
    if (result['result'] != 'OK') {
      throw const OperationsApiException(502, '답변 저장 결과를 확인할 수 없습니다.');
    }
  }

  Future<AdminPayload> save(String path, AdminRow body) async {
    final result = AdminPayload(await api.request(path, json: body));
    if ((path == '/announce/write' &&
            (result.data['result'] != 'OK' ||
                result.number('a_seq') == null)) ||
        (path.startsWith('/approval/requests') &&
            result.number('m_code') == null) ||
        (path.startsWith('/appeal/review/') && result.data['result'] != 'OK')) {
      throw const OperationsApiException(
        502,
        '저장 결과를 확인할 수 없습니다. 내역을 다시 조회해 주세요.',
      );
    }
    return result;
  }

  Future<String> upload(String staffId, String name, List<int> bytes) async {
    final result = await api.uploadPhoto(staffId, name, bytes);
    if (result['s_image'] is! String) {
      throw const FormatException('Invalid photo response');
    }
    return result['s_image'] as String;
  }
}

String adminPath(String path, Map<String, String?> params) => Uri(
  path: path,
  queryParameters: {
    for (final entry in params.entries)
      if (entry.value != null && entry.value!.isNotEmpty)
        entry.key: entry.value!,
  },
).toString();
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
