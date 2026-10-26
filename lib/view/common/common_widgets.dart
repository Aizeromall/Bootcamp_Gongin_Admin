// [이 파일의 역할]
// 여러 화면에서 같이 쓰는 작은 위젯 모음
//   LabeledField  : 라벨 + 입력창 + 안내/오류 문구가 묶인 입력 위젯
//   StatusBadge   : 상태 표시 알약 (결제완료, 답변대기 등)
//   SectionTitle  : 섹션 제목
//   EmptyView     : 데이터가 없을 때 안내
//   ErrorView     : 조회 실패 안내 + 다시 시도 버튼
//   LoadingView   : 로딩 표시
//   showAppSnack  : 하단 알림(스낵바) 표시 함수

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

// 라벨 + 입력창 + 안내 문구(hint)/오류 문구(error)를 한 번에 그리는 입력 위젯
// error가 있으면 빨간 테두리와 문구, ok가 true면 초록 문구로 표시
class LabeledField extends StatelessWidget {
  final String label;
  final String? hintText;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final String? helper; // 입력창 아래 기본 안내 문구
  final String? error; // 입력 오류 문구 (있으면 빨간색)
  final String? okMessage; // 입력이 올바를 때 보여줄 문구 (초록색)
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final TextInputAction? textInputAction;

  const LabeledField({
    super.key,
    required this.label,
    this.hintText,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.helper,
    this.error,
    this.okMessage,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    // 입력창 아래에 보여줄 문구와 색 결정 : 오류 > 성공 > 기본 안내 순서
    String? message;
    Color messageColor = AppColors.textSub;
    if (error != null) {
      message = error;
      messageColor = AppColors.danger;
    } else if (okMessage != null) {
      message = okMessage;
      messageColor = AppColors.primaryDark;
    } else if (helper != null) {
      message = helper;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          minLines: minLines,
          maxLines: obscureText ? 1 : maxLines,
          maxLength: maxLength,
          textInputAction: textInputAction,
          // maxLength를 쓸 때 입력창 아래 기본 글자수 표시를 숨김
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
          decoration: InputDecoration(
            hintText: hintText,
            // 오류일 때 테두리를 빨갛게 (문구는 아래 Text로 따로 표시)
            enabledBorder: error != null
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.danger),
                  )
                : null,
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 2),
            child: Text(message, style: TextStyle(fontSize: 12, color: messageColor)),
          ),
      ],
    );
  }
}

// 상태 표시 알약 (예: 결제완료 / 답변대기). 색 종류는 StatusTone으로 선택
enum StatusTone { green, red, gray, orange }

class StatusBadge extends StatelessWidget {
  final String text;
  final StatusTone tone;

  const StatusBadge(this.text, {super.key, this.tone = StatusTone.gray});

  @override
  Widget build(BuildContext context) {
    // 톤에 따라 배경색/글자색을 정함
    final (Color bg, Color fg) = switch (tone) {
      StatusTone.green => (AppColors.primarySoft, AppColors.primaryDark),
      StatusTone.red => (AppColors.dangerSoft, AppColors.danger),
      StatusTone.orange => (AppColors.warnSoft, AppColors.warn),
      StatusTone.gray => (const Color(0xFFECEFED), AppColors.textSub),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

// 섹션 제목 (카드 위/안쪽의 굵은 제목)
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700));
  }
}

// 목록이 비었을 때 가운데에 보여주는 안내
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyView({super.key, required this.message, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSub, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// 조회 실패 안내 + 다시 시도 버튼
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44, color: AppColors.textHint),
            const SizedBox(height: 12),
            // 예외 메시지에서 "Exception: " 접두어를 제거해 사용자가 읽기 쉽게 표시
            Text(error.toString().replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSub, height: 1.5)),
            const SizedBox(height: 16),
            SizedBox(
              width: 140,
              child: OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
            ),
          ],
        ),
      ),
    );
  }
}

// 로딩 중 표시 (가운데 초록 원형 진행 표시)
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(color: AppColors.primary));
  }
}

// 하단 알림(스낵바) 표시 : 이전 알림이 남아 있으면 먼저 지우고 새로 표시
void showAppSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textMain,
    ));
}
