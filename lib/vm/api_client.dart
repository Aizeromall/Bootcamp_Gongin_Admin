// [이 파일의 역할]
// 모든 ViewModel(Notifier)이 공통으로 쓰는 서버(FastAPI) 호출 함수 모음
//   apiGet / apiPost / apiPostForm : 요청을 보내고 응답을 Dart 객체(Map/List)로 돌려줌
//     (apiPostForm은 문의 답변 API처럼 JSON이 아닌 Form 형식을 받는 서버용)
//   ApiException                 : 서버가 준 오류 메시지를 화면에 그대로 보여주기 위한 예외
//   noRetry                      : Riverpod 3의 자동 재시도를 끄는 함수 (실패 시 로딩이 계속 도는 것 방지)
//
// 서버 주소(baseUrl)는 기존 구장 상태관리 파일(match_notifier.dart)에 있는 값을 그대로 사용
// (관리자 서버 CORS가 localhost:5000/8081만 허용하므로 웹 테스트는 --web-port 5000으로 실행)

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'match_notifier.dart' show baseUrl;

// 서버가 돌려준 오류(4xx/5xx) 또는 연결 실패를 화면에 보여줄 메시지로 담는 예외
class ApiException implements Exception {
  final String message; // 사용자에게 보여줄 문구
  final int? statusCode; // HTTP 상태 코드 (연결 실패면 null)

  ApiException(this.message, [this.statusCode]);

  // 화면에서 error.toString()으로 바로 문구를 쓸 수 있게 message만 반환
  @override
  String toString() => message;
}

// Riverpod 3는 Provider가 실패하면 자동으로 다시 시도하는데, 오류 화면이 안 뜨고 로딩만 계속될 수 있어서
// 재시도를 끄는 함수 (retry: noRetry 로 Provider에 넘김). null을 반환하면 재시도하지 않음
Duration? noRetry(int retryCount, Object error) => null;

// 오류 응답 본문에서 사용자에게 보여줄 문구를 꺼냄
// FastAPI 오류 형식 : {"detail": "문구"}  또는  검증 실패(422) {"detail": [ {...}, ... ]}
String _errorMessage(http.Response response) {
  try {
    final body = json.decode(utf8.decode(response.bodyBytes));
    final detail = body is Map ? body['detail'] : null;
    if (detail is String && detail.isNotEmpty) return detail;
    // 로그인 API는 {"code": ..., "message": "문구"} 형태로 오류를 줌
    if (detail is Map && detail['message'] is String) return detail['message'] as String;
    if (response.statusCode == 422) return '입력한 내용을 다시 확인해주세요.';
  } catch (_) {
    // 본문이 JSON이 아니면 아래 기본 문구 사용
  }
  return '요청을 처리하지 못했어요. (${response.statusCode})';
}

// 응답 처리 공통부 : 200번대면 JSON으로 변환해 반환, 아니면 ApiException 발생
dynamic _handle(http.Response response) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    // utf8.decode(bodyBytes) : response.body를 그대로 쓰면 한글이 깨질 수 있어서 바이트를 직접 UTF-8로 변환
    return json.decode(utf8.decode(response.bodyBytes));
  }
  throw ApiException(_errorMessage(response), response.statusCode);
}

// 서버에 연결하지 못한 경우(서버 꺼짐, 주소 오류 등)를 안내 문구로 바꿔서 던짐
Future<T> _guard<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on ApiException {
    rethrow; // 서버가 준 오류는 그대로 전달
  } catch (_) {
    throw ApiException('서버에 연결하지 못했어요. 네트워크와 서버 주소를 확인해주세요.');
  }
}

// 요청 공통 헤더 (JSON 본문 전송용)
const Map<String, String> _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};

// GET 요청 : query가 있으면 ?key=value 형태로 붙임 (한글도 자동 인코딩)
Future<dynamic> apiGet(String path, {Map<String, String>? query}) {
  return _guard(() async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    return _handle(await http.get(uri));
  });
}

// POST 요청 : body(Map)를 JSON으로 변환해 전송
Future<dynamic> apiPost(String path, Map<String, dynamic> body) {
  return _guard(() async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _jsonHeaders,
      body: json.encode(body),
    );
    return _handle(response);
  });
}

// POST 요청 (Form 형식) : 서버가 Form(...)으로 받는 API용. Map이 자동으로 key=value&... 형태로 전송됨
Future<dynamic> apiPostForm(String path, Map<String, String> body) {
  return _guard(() async {
    return _handle(await http.post(Uri.parse('$baseUrl$path'), body: body));
  });
}

// DELETE 요청 : 삭제 대상은 주소(path)와 query로 전달
Future<dynamic> apiDelete(String path, {Map<String, String>? query}) {
  return _guard(() async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    return _handle(await http.delete(uri));
  });
}
