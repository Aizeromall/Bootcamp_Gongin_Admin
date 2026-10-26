// [이 파일의 역할]
// 관리자 앱 전체에서 쓰는 색상(AppColors)과 테마(buildAppTheme)를 한 곳에서 관리
// agent.md 디자인 규칙 : 활동적·스포츠·밝은 무드 / 연한 초록색 계열 중심 / 글꼴 IBM Plex Sans KR
//   - 화면 코드에서 색을 직접 쓰지 않고 AppColors를 쓰면, 색 변경이 필요할 때 이 파일만 고치면 됨

import 'package:flutter/material.dart';

// 앱 색상 모음 (정적 상수라 어디서든 AppColors.primary 형태로 사용)
class AppColors {
  AppColors._(); // 인스턴스를 만들 일이 없어서 생성자를 막음

  // 주 색상 (버튼·선택된 칩·강조) : 연한 초록 계열, 흰 글씨와 같이 써도 읽히도록 약간 진한 톤
  static const Color primary = Color(0xFF2A9D68);
  // 눌렀을 때·강조 텍스트용 진한 초록
  static const Color primaryDark = Color(0xFF1E7A4F);
  // 선택 배경·배지 배경에 쓰는 아주 연한 초록
  static const Color primarySoft = Color(0xFFE6F6EE);

  // 배경색 (화면 바탕 : 연한 초록빛이 도는 흰색 / 카드 : 흰색)
  static const Color bg = Color(0xFFF4FAF6);
  static const Color surface = Colors.white;

  // 관리자 앱 왼쪽 사이드바 : 진한 초록 배경 + 선택 항목 배경 + 보조 글자색
  static const Color sidebar = Color(0xFF17382A);
  static const Color sidebarSelected = Color(0xFF24503D);
  static const Color sidebarText = Color(0xFFB9D3C6);

  // 구분선·테두리
  static const Color line = Color(0xFFDDEBE3);

  // 글자색 (본문 / 보조 / 안내문구)
  static const Color textMain = Color(0xFF16261D);
  static const Color textSub = Color(0xFF5E7066);
  static const Color textHint = Color(0xFF8A9A91);

  // 오류·취소 (빨강) / 안내 (연한 주황)
  static const Color danger = Color(0xFFE5384B);
  static const Color dangerSoft = Color(0xFFFDE8EB);
  static const Color warn = Color(0xFF9A5B00);
  static const Color warnSoft = Color(0xFFFFF1DB);
}

// 앱 글꼴 이름 (pubspec.yaml의 fonts: family 와 같아야 함)
const String appFontFamily = 'IBMPlexSansKR';

// MaterialApp(theme: ...)에 넣는 앱 전체 테마
ThemeData buildAppTheme() {
  // 초록 계열 기본 색 구성표 (Material3). 주요 색은 아래에서 AppColors 값으로 덮어씀
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    error: AppColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: appFontFamily,
    scaffoldBackgroundColor: AppColors.bg,

    // 상단 앱바 : 흰 배경 + 아래 얇은 선, 제목은 굵게
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textMain,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: appFontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textMain,
      ),
    ),

    // 채워진 버튼(주요 동작) : 초록 배경 + 둥근 모서리, 비활성은 회색
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFC9D6CE),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: appFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    // 테두리 버튼(보조 동작)
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textMain,
        side: const BorderSide(color: AppColors.line),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: appFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // 입력창 : 흰 배경 + 연한 테두리, 포커스 시 초록 테두리
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.textHint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
      ),
    ),

    // 하단 탭바 : 흰 배경, 선택된 탭은 연한 초록 알약 표시
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: appFontFamily,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.primaryDark : AppColors.textSub,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.primaryDark : AppColors.textSub,
        );
      }),
    ),

    // 구분선·카드 기본값
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
  );
}
