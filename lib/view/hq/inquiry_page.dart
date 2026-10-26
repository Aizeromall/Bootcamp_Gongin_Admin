// [이 파일의 역할]
// 본사 관리자 "문의 내역" 화면 (왼쪽 목록 + 오른쪽 상세·답변의 2단 구성)
//   - 왼쪽   : 필터(전체/답변 대기/답변 완료) + 문의 목록. 서버가 미답변을 위(오래된 순), 답변 완료를 아래(최신순)로 정렬해서 줌
//   - 오른쪽 : 선택한 문의의 내용, 추가 문의, 답변. 답변이 없으면 입력창이 나오고 "답변 등록"으로 저장
// 답변은 로그인한 본사 관리자 아이디로 저장되며, 원글과 추가 문의 각각에 따로 등록
// 상태관리 : inquiryFilterProvider, adminInquiryListProvider, selectedInquiryProvider,
//           adminInquiryDetailProvider, inquiryAnswerControllerProvider

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vm/admin_inquiry_notifier.dart';
import '../common/admin_widgets.dart';
import '../common/app_theme.dart';
import '../common/common_widgets.dart';
import '../common/format_utils.dart';

class InquiryPage extends ConsumerWidget {
  const InquiryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(adminInquiryListProvider);
    // 답변 대기 건수 : 헤더 오른쪽에 표시
    final pending = listAsync.value?.where((e) => e.hasPending).length;

    return Column(
      children: [
        PageHeader(
          title: '문의 내역',
          trailing: Text(
            listAsync.value == null ? '' : '전체 ${listAsync.value!.length}건 · 처리 필요 $pending건',
            style: const TextStyle(color: AppColors.textSub),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              // ---------- 왼쪽 목록 ----------
              Container(
                width: 400,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(right: BorderSide(color: AppColors.line)),
                ),
                child: const _InquiryListPane(),
              ),
              // ---------- 오른쪽 상세 ----------
              const Expanded(child: _InquiryDetailPane()),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------
// 목록
// ------------------------------------------------------------

class _InquiryListPane extends ConsumerWidget {
  const _InquiryListPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(inquiryFilterProvider);
    final listAsync = ref.watch(adminInquiryListProvider);
    final selected = ref.watch(selectedInquiryProvider);

    // 필터 칩 정의 : 값은 서버 i_state (null=전체, '0'=답변 대기, '1'=답변 완료)
    const filters = [(null, '전체'), ('0', '답변 대기'), ('1', '답변 완료')];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              for (final f in filters) ...[
                ChoiceChip(
                  label: Text(f.$2),
                  selected: filter == f.$1,
                  onSelected: (_) => ref.read(inquiryFilterProvider.notifier).select(f.$1),
                  selectedColor: AppColors.primarySoft,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: filter == f.$1 ? AppColors.primaryDark : AppColors.textMain,
                  ),
                  side: BorderSide(color: filter == f.$1 ? AppColors.primary : AppColors.line),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: listAsync.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              error: error,
              onRetry: () => ref.read(adminInquiryListProvider.notifier).refresh(),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyView(icon: Icons.inbox_outlined, message: '문의가 없어요.');
              }
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => ref.read(adminInquiryListProvider.notifier).refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final q = items[i];
                    return SelectableTile(
                      selected: q.i_seq == selected,
                      onTap: () => ref.read(selectedInquiryProvider.notifier).select(q.i_seq),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('@${q.c_id_seq} · ${q.c_name ?? '-'}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                              ),
                              // 원글 또는 추가 문의에 미답변이 있으면 "답변 대기"
                              q.hasPending
                                  ? const StatusBadge('답변 대기', tone: StatusTone.orange)
                                  : const StatusBadge('답변 완료', tone: StatusTone.green),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(q.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(q.post,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
                          const SizedBox(height: 4),
                          Text(q.i_date == null ? '' : formatDateTime(q.i_date!),
                              style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------
// 상세 + 답변
// ------------------------------------------------------------

class _InquiryDetailPane extends ConsumerWidget {
  const _InquiryDetailPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedInquiryProvider);
    if (selected == null) {
      return const EmptyView(icon: Icons.touch_app_outlined, message: '왼쪽 목록에서 문의를 선택해주세요.');
    }

    final detailAsync = ref.watch(adminInquiryDetailProvider(selected));
    return detailAsync.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(adminInquiryDetailProvider(selected)),
      ),
      data: (q) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 문의 본문
          SectionCard(
            title: q.title,
            trailing: q.answered
                ? const StatusBadge('답변 완료', tone: StatusTone.green)
                : const StatusBadge('답변 대기', tone: StatusTone.orange),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('문의자  ${q.c_name ?? '-'} (@${q.c_id_seq})  ·  ${q.i_date == null ? '-' : formatDateTime(q.i_date!)}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
                const SizedBox(height: 12),
                _Bubble(text: q.post),
                const SizedBox(height: 16),
                // 원글 답변
                _ReplyBlock(
                  iSeq: q.i_seq,
                  answered: q.answered,
                  detail: q.inquiry_detail,
                  answerDate: q.i_answer_date,
                  writer: q.h_name ?? q.h_id,
                ),
              ],
            ),
          ),
          // 추가 문의 (있을 때만) : 각각 따로 답변
          for (var i = 0; i < q.follow_ups.length; i++) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: '추가 문의 ${i + 1}',
              trailing: q.follow_ups[i].answered
                  ? const StatusBadge('답변 완료', tone: StatusTone.green)
                  : const StatusBadge('답변 대기', tone: StatusTone.orange),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.follow_ups[i].i_date == null ? '-' : formatDateTime(q.follow_ups[i].i_date!),
                      style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
                  const SizedBox(height: 12),
                  _Bubble(text: q.follow_ups[i].post),
                  const SizedBox(height: 16),
                  _ReplyBlock(
                    iSeq: q.follow_ups[i].i_seq,
                    answered: q.follow_ups[i].answered,
                    detail: q.follow_ups[i].inquiry_detail,
                    answerDate: q.follow_ups[i].i_answer_date,
                    writer: q.follow_ups[i].h_id,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// 회원이 쓴 글을 보여주는 회색 말풍선
class _Bubble extends StatelessWidget {
  final String text;
  const _Bubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: const TextStyle(height: 1.7)),
    );
  }
}

// 답변 영역 : 답변이 있으면 내용 표시, 없으면 입력창 + "답변 등록" 버튼
class _ReplyBlock extends ConsumerStatefulWidget {
  final int iSeq; // 답변을 저장할 문의 번호 (원글 또는 추가 문의)
  final bool answered;
  final String? detail;
  final DateTime? answerDate;
  final String? writer; // 답변 작성자(이름 또는 아이디)

  const _ReplyBlock({
    required this.iSeq,
    required this.answered,
    this.detail,
    this.answerDate,
    this.writer,
  });

  @override
  ConsumerState<_ReplyBlock> createState() => _ReplyBlockState();
}

class _ReplyBlockState extends ConsumerState<_ReplyBlock> {
  final _controller = TextEditingController();
  // 이 블록에서 마지막으로 요청했을 때의 오류 문구 (다른 블록의 오류와 섞이지 않게 로컬로 보관)
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 답변 등록 : 성공하면 목록·상세가 새로 조회되어 "답변 완료" 모습으로 바뀜
  Future<void> _submit() async {
    setState(() => _error = null);
    final ok = await ref
        .read(inquiryAnswerControllerProvider.notifier)
        .answer(widget.iSeq, _controller.text);
    if (!mounted) return;
    if (ok) {
      showAppSnack(context, '답변을 등록했어요.');
    } else {
      setState(() => _error = ref.read(inquiryAnswerControllerProvider).error?.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // 이미 답변된 경우 : 연한 초록 박스로 표시
    if (widget.answered && widget.detail != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '답변${widget.writer != null ? ' · ${widget.writer}' : ''}'
              '${widget.answerDate != null ? ' · ${formatDateTime(widget.answerDate!)}' : ''}',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 6),
            Text(widget.detail!, style: const TextStyle(height: 1.7)),
          ],
        ),
      );
    }

    // 답변 전 : 입력창 + 버튼. 내용이 있을 때만 버튼 활성화
    final isLoading = ref.watch(inquiryAnswerControllerProvider).isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          minLines: 4,
          maxLines: 8,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: '답변 내용을 입력해주세요.'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.danger)),
          ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 160,
            child: FilledButton(
              onPressed: _controller.text.trim().isEmpty || isLoading ? null : _submit,
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('답변 등록'),
            ),
          ),
        ),
      ],
    );
  }
}
