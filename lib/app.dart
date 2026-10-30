// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';

import 'view/login/login_page.dart';
import 'view/shared/admin_style.dart';

// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 관리자 전체 목업의 파란 동작·흰 카드·밝은 배경을 공통 테마로 사용합니다.
class GonginApp extends StatelessWidget {
  const GonginApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '공IN 중개사 · 운영',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AdminStyle.canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: AdminStyle.blue).copyWith(
        primary: AdminStyle.blue,
        surface: Colors.white,
        onSurface: AdminStyle.ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AdminStyle.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AdminStyle.line),
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      fontFamily: 'IBM Plex Sans KR',
      inputDecorationTheme: const InputDecorationTheme(
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AdminStyle.line),
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AdminStyle.blue, width: 1.5),
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      ),
    ),
    home: const LoginPage(),
  );
}
// 최종 수정일 : 2026-10-24

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
