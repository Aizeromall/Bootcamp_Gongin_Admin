// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';

import 'view/login/role_selection_page.dart';

class GonginApp extends StatelessWidget {
  const GonginApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '공IN 중개사 · 운영',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F8F4),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF34734F)),
      fontFamily: 'IBM Plex Sans KR',
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      ),
    ),
    home: const RoleSelectionPage(),
  );
}
// 최종 수정일 : 2026-10-24
