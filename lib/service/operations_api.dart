// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../vm/login_notifier.dart';

final operationsApiProvider = Provider((ref) => OperationsApi());
final operationsDataProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, path) => ref.read(operationsApiProvider).request(path),
    );

class OperationsApi {
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
  }) async {
    final uri = Uri.parse(
      '${LoginNotifier.baseUrl.replaceFirst(RegExp(r'/+$'), '')}$path',
    );
    final response =
        await (json != null
                ? http.post(
                    uri,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(json),
                  )
                : form != null
                ? http.post(uri, body: form)
                : http.get(uri))
            .timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) {
      throw Exception('요청한 데이터 또는 API를 찾을 수 없습니다. 서버 연결을 확인해 주세요.');
    }
    if (response.statusCode >= 500) {
      throw Exception('서버에서 요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.');
    }
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 400 || data['result'] == 'Error') {
      final detail = data['detail'];
      throw Exception(
        detail is String ? detail : data['message'] ?? '요청 처리에 실패했습니다.',
      );
    }
    return data;
  }
}
// 최종 수정일 : 2026-10-24
