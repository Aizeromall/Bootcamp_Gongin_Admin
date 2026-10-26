// [이 파일의 역할]
// 관리자 앱(공In중개사 관리자 대시보드)의 시작점
//   ProviderScope : 앱 전체에서 Riverpod Provider를 쓸 수 있게 감싸는 최상위 위젯 (없으면 ref 사용 시 오류)
//   MaterialApp   : 앱 이름·테마(초록 계열, IBM Plex Sans KR)를 지정하고 첫 화면(로그인)을 연결

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'view/auth/admin_login_page.dart';
import 'view/common/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: AdminApp()));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '공In중개사 관리자',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AdminLoginPage(),
    );
  }
// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runApp(const ProviderScope(child: GonginApp()));
}
// 최종 수정일 : 2026-10-24
