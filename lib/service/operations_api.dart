import 'dart:async';
// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../vm/login_notifier.dart';

// 작업자 : 양태건
// 수정일 : 2026-10-26
// [수정 시작] 새 경기 API에 로그인 토큰을 전달합니다.
final operationsApiProvider = Provider((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return OperationsApi(
    client: client,
    accessToken: ref.watch(loginProvider).asData?.value?.accessToken,
  );
});
final operationsDataProvider = AsyncNotifierProvider.autoDispose
    .family<OperationsDataNotifier, Map<String, dynamic>, String>(
      OperationsDataNotifier.new,
      retry: (_, _) => null,
    );

class OperationsApi {
  OperationsApi({this.accessToken, this.client});
  final String? accessToken;
  // 주입한 client는 생성한 provider 또는 호출자가 정리합니다.
  final http.Client? client;
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> json,
  ) async {
    final uri = Uri.parse(
      '${LoginNotifier.baseUrl.replaceFirst(RegExp(r'/+$'), '')}$path',
    );
    final response = await (client?.patch ?? http.patch)(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(json),
    ).timeout(const Duration(seconds: 10));
    return _decode(response);
  }

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
                ? (client?.post ?? http.post)(
                    uri,
                    headers: {
                      'Content-Type': 'application/json',
                      if (accessToken != null)
                        'Authorization': 'Bearer $accessToken',
                    },
                    body: jsonEncode(json),
                  )
                : form != null
                ? (client?.post ?? http.post)(
                    uri,
                    body: form,
                    headers: {
                      if (accessToken != null)
                        'Authorization': 'Bearer $accessToken',
                    },
                  )
                : (client?.get ?? http.get)(
                    uri,
                    headers: {
                      if (accessToken != null)
                        'Authorization': 'Bearer $accessToken',
                    },
                  ))
            .timeout(const Duration(seconds: 10));
    return _decode(response);
  }

  // 수정 일 : 2026-10-27 / 작업자 : 양태건
  // 구장 품의 사진도 공통 주소·토큰·응답 오류 처리를 사용합니다.
  Future<Map<String, dynamic>> uploadPhoto(
    String staffId,
    String name,
    List<int> bytes,
  ) async {
    final uri = Uri.parse(
      '${LoginNotifier.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/approval/ground-photos/draft',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['h_id'] = staffId
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 30)),
    ).timeout(const Duration(seconds: 30));
    return _decode(response);
  }

  // 수정 일 : 2026-10-28 / 작업자 : 양태건
  // 배너는 품의 사진과 다른 multipart 경로이며 주입된 client를 공유합니다.
  Future<Map<String, dynamic>> uploadBanner(
    String staffId,
    String name,
    List<int> bytes,
  ) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse(
              '${LoginNotifier.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/images/banner',
            ),
          )
          ..fields['h_id'] = staffId
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: name),
          );
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    final response = await http.Response.fromStream(
      await (client != null ? client!.send(request) : request.send()).timeout(
        const Duration(seconds: 30),
      ),
    ).timeout(const Duration(seconds: 30));
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    // 수정 일 : 2026-10-27 / 작업자 : 양태건
    // 신고 심의 충돌을 구분하고 비JSON·구조화된 검증 오류도 안전하게 안내합니다.
    if (response.statusCode >= 500) {
      throw OperationsApiException(
        response.statusCode,
        '서버에서 요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.',
      );
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw OperationsApiException(
        response.statusCode,
        '서버 응답을 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.',
      );
    }
    final data = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode >= 400 || data['result'] == 'Error') {
      final detail = data['detail'];
      final message = detail is String
          ? detail
          : detail is List
          ? detail
                .whereType<Map>()
                .map((v) => '${v['msg'] ?? '입력 값을 확인해 주세요.'}')
                .join('\n')
          : detail is Map
          ? detail['message']?.toString()
          : data['message']?.toString();
      throw OperationsApiException(
        response.statusCode,
        message?.isNotEmpty == true ? message! : '요청을 처리하지 못했습니다. 다시 시도해 주세요.',
      );
    }
    if (decoded is! Map) {
      throw OperationsApiException(response.statusCode, '서버 응답을 확인할 수 없습니다.');
    }
    return data;
  }
}
// 최종 수정일 : 2026-10-24

// [수정 끝]

// 수정 일 : 2026-10-27 / 작업자 : 양태건
class OperationsApiException implements Exception {
  const OperationsApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 조회 상태를 AsyncNotifier가 소유하며 기존 조건별 캐시와 오류 처리를 유지합니다.
class OperationsDataNotifier extends AsyncNotifier<Map<String, dynamic>> {
  OperationsDataNotifier(this.path);
  final String path;
  @override
  FutureOr<Map<String, dynamic>> build() =>
      ref.watch(operationsApiProvider).request(path);
}

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
