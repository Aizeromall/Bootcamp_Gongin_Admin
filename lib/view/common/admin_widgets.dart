// [이 파일의 역할]
// 관리자 앱(iPad 가로 화면)의 여러 화면에서 같이 쓰는 위젯 모음
//   PageHeader    : 화면 상단 제목 줄 (제목 + 오른쪽 보조 문구/버튼)
//   SectionCard   : 제목이 붙은 흰색 카드 (상세 화면의 섹션)
//   InfoTile      : "라벨 + 값" 정보 칸
//   InfoGrid      : InfoTile을 화면 너비에 맞춰 여러 줄로 배치
//   SearchField   : 검색창 (키보드 검색 버튼 또는 돋보기 버튼으로 실행)
//   SelectableTile: 목록의 한 줄 (선택되면 연한 초록 배경)
//   FormattedDate : 날짜를 2026.10.23 형식으로 표시하는 함수 (값이 없으면 "-")

import 'package:flutter/material.dart';

import 'app_theme.dart';

// 날짜를 2026.10.23 형식으로 변환 (값이 없으면 "-")
String shortDate(DateTime? d) {
  if (d == null) return '-';
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}.$mm.$dd';
}

// 화면 상단 제목 줄 : 왼쪽에 제목, 오른쪽에 보조 문구(예: 전체 10명)나 버튼
class PageHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const PageHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// 제목이 붙은 흰색 카드 (상세 화면의 제재 이력, 받은 신고 같은 섹션)
class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing; // 제목 오른쪽 보조 문구

  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// "라벨 + 값" 정보 칸 (연한 회색 배경)
class InfoTile {
  final String label;
  final String value;
  final Color? valueColor; // 값 글자색 (경고 등 강조할 때)

  const InfoTile(this.label, this.value, {this.valueColor});
}

// InfoTile 여러 개를 사용 가능한 너비에 맞춰 한 줄에 최대 [columns]개씩 배치
class InfoGrid extends StatelessWidget {
  final List<InfoTile> tiles;
  final int columns;

  const InfoGrid({super.key, required this.tiles, this.columns = 4});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        // 너비가 좁으면 칸 수를 줄여서 글자가 잘리지 않게 함 (한 칸 최소 150)
        final usable = constraints.maxWidth;
        final cols = (usable / 150).floor().clamp(1, columns);
        final tileWidth = (usable - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles)
              Container(
                width: tileWidth,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tile.label, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                    const SizedBox(height: 4),
                    Text(tile.value,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: tile.valueColor ?? AppColors.textMain,
                        )),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// 검색창 : 입력 후 키보드의 검색 버튼 또는 오른쪽 화살표 버튼으로 onSearch 실행
class SearchField extends StatefulWidget {
  final String hintText;
  final ValueChanged<String> onSearch;

  const SearchField({super.key, required this.hintText, required this.onSearch});

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus(); // 키보드 닫기
    widget.onSearch(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        hintText: widget.hintText,
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textSub),
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_forward, size: 20, color: AppColors.primary),
          onPressed: _submit,
        ),
      ),
    );
  }
}

// 목록의 한 줄 : 선택된 항목은 연한 초록 배경 + 왼쪽 초록 막대
class SelectableTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const SelectableTile({super.key, required this.selected, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          border: Border(
            left: BorderSide(color: selected ? AppColors.primary : Colors.transparent, width: 3),
            bottom: const BorderSide(color: AppColors.line),
          ),
        ),
        child: child,
      ),
    );
  }
}
