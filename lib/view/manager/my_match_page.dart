// [이 파일의 역할]
// 매치 매니저 "내 매치" 화면 : 담당 구장에 들어온 예약을 경기(구장+날짜+시간)별로 묶어서 보여줌
//   - 각 예약 회원마다 "출석 / 결석" 체크 → 출석한 회원은 "결과 등록"으로 경기 결과 입력
//   - 결과 등록 입력 : 종목, 팀, 스탯 4개(예: 골/어시/태클/선방 → 서버에는 "1-1-1-1"로 전송), 전체 스코어
// 이미 체크한 출석을 조회하는 API가 없어서, 이 화면에서 처리한 결과는 앱 안에서만 기억함 (새로고침하면 사라짐)
// 상태관리 : matchListProvider(예약 목록), matchProgressProvider(출석·등록 진행 상태)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/manager_match_model.dart';
import '../../vm/admin_auth_notifier.dart';
import '../../vm/manager_match_notifier.dart';
import '../common/admin_widgets.dart';
import '../common/app_theme.dart';
import '../common/common_widgets.dart';
import '../common/format_utils.dart';

class MyMatchPage extends ConsumerWidget {
  const MyMatchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(matchListProvider);
    final session = ref.watch(adminSessionProvider);

    return Column(
      children: [
        PageHeader(
          title: '내 매치',
          trailing: Text(
            listAsync.value == null
                ? ''
                : '${listAsync.value!.m_name.isEmpty ? (session?.id ?? '') : listAsync.value!.m_name} 매니저님 · 예약 ${listAsync.value!.reservations.length}건',
            style: const TextStyle(color: AppColors.textSub),
          ),
        ),
        Expanded(
          child: listAsync.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              error: error,
              onRetry: () => ref.read(matchListProvider.notifier).refresh(),
            ),
            data: (data) {
              if (data.reservations.isEmpty) {
                return const EmptyView(
                  icon: Icons.event_busy_outlined,
                  message: '담당 구장에 들어온 예약이 없어요.',
                );
              }
              // 같은 경기(구장+날짜+시간)끼리 묶음. LinkedHashMap이라 서버가 준 순서(날짜·시간순)가 유지됨
              final groups = <String, List<MatchReservation>>{};
              for (final r in data.reservations) {
                groups.putIfAbsent(r.matchKey, () => []).add(r);
              }
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => ref.read(matchListProvider.notifier).refresh(),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (final group in groups.values) ...[
                      _MatchGroupCard(reservations: group),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// 한 경기(구장+날짜+시간)와 그 경기의 예약 회원 목록
class _MatchGroupCard extends StatelessWidget {
  final List<MatchReservation> reservations;
  const _MatchGroupCard({required this.reservations});

  @override
  Widget build(BuildContext context) {
    final first = reservations.first;
    return SectionCard(
      title: first.g_name,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 정원 마감(매치 성사) 여부 + 예약 인원
          if (first.r_check) ...[
            const StatusBadge('매치 성사', tone: StatusTone.green),
            const SizedBox(width: 8),
          ],
          Text('예약 ${reservations.length}/${first.g_num}명',
              style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${formatKoreanDate(first.r_date)}  ${first.rs_time} ~ ${first.re_time}',
              style: const TextStyle(fontSize: 14, color: AppColors.textSub)),
          const SizedBox(height: 10),
          for (final r in reservations) _PlayerRow(reservation: r),
        ],
      ),
    );
  }
}

// 예약 회원 1명 : 정보 + 출석/결석 + 결과 등록
class _PlayerRow extends ConsumerWidget {
  final MatchReservation reservation;
  const _PlayerRow({required this.reservation});

  // 출석/결석 체크 : 서버 오류(이미 처리된 예약 등)는 안내 문구로 표시
  Future<void> _check(BuildContext context, WidgetRef ref, bool attended) async {
    try {
      await ref.read(matchProgressProvider.notifier).checkAttendance(reservation.r_seq, attended);
      if (context.mounted) {
        showAppSnack(context, '${reservation.c_name}님을 ${attended ? '출석' : '결석'} 처리했어요.');
      }
    } catch (e) {
      if (context.mounted) showAppSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(matchProgressProvider);
    final attendance = progress.attendance[reservation.r_seq]; // true 출석 / false 결석 / null 미처리
    final recorded = progress.recorded.contains(reservation.r_seq);
    final busy = progress.busy.contains(reservation.r_seq);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primarySoft,
            child: Text(reservation.c_name.isEmpty ? '?' : reservation.c_name.substring(0, 1),
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
          ),
          const SizedBox(width: 12),
          // 이름 + 아이디 / 실력 점수 · 포지션
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reservation.c_name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '@${reservation.c_id_seq} · 실력 ${reservation.c_rating ?? '-'} · ${reservation.c_position ?? '-'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
            )
          else ...[
            // 출석 / 결석 버튼 : 처리한 쪽은 색이 채워짐
            _CheckButton(
              label: '출석',
              selected: attendance == true,
              color: AppColors.primary,
              // 이미 처리했으면 다시 누를 수 없음 (서버가 중복 등록을 거절함)
              onTap: attendance == null ? () => _check(context, ref, true) : null,
            ),
            const SizedBox(width: 6),
            _CheckButton(
              label: '결석',
              selected: attendance == false,
              color: AppColors.danger,
              onTap: attendance == null ? () => _check(context, ref, false) : null,
            ),
            const SizedBox(width: 12),
            // 결과 등록 : 출석 처리된 회원만, 등록 후에는 "등록 완료" 표시
            SizedBox(
              width: 110,
              child: recorded
                  ? const Center(child: StatusBadge('등록 완료', tone: StatusTone.green))
                  : OutlinedButton(
                      onPressed: attendance == true
                          ? () => showDialog(
                                context: context,
                                builder: (_) => _ScoreDialog(reservation: reservation),
                              )
                          : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(38),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('결과 등록'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

// 출석/결석 토글 버튼
class _CheckButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  const _CheckButton({required this.label, required this.selected, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : AppColors.line),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              // 아직 처리 전이고 누를 수 있으면 보통 색, 처리가 끝나 비활성이면 흐리게
              color: selected ? Colors.white : (onTap == null ? AppColors.textHint : AppColors.textMain),
            )),
      ),
    );
  }
}

// ------------------------------------------------------------
// 경기 결과 등록 대화상자
// ------------------------------------------------------------

class _ScoreDialog extends ConsumerStatefulWidget {
  final MatchReservation reservation;
  const _ScoreDialog({required this.reservation});

  @override
  ConsumerState<_ScoreDialog> createState() => _ScoreDialogState();
}

class _ScoreDialogState extends ConsumerState<_ScoreDialog> {
  final _teamController = TextEditingController();
  final _scoreController = TextEditingController();
  late MatchSportOption _sport; // 선택한 종목
  final List<int> _stats = [0, 0, 0, 0]; // 스탯 4개 값
  String? _error; // 등록 실패 문구
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // 회원 아이디 끝 번호로 종목을 미리 선택해 둠 (필요하면 바꿀 수 있음)
    _sport = kMatchSports.firstWhere(
      (s) => s.e_code == widget.reservation.sportCode,
      orElse: () => kMatchSports.first,
    );
  }

  @override
  void dispose() {
    _teamController.dispose();
    _scoreController.dispose();
    super.dispose();
  }

  // 팀과 스코어를 입력했을 때만 등록 가능
  bool get _canSubmit => _teamController.text.trim().isNotEmpty && _scoreController.text.trim().isNotEmpty;

  // 등록 : 스탯 4개는 "-"로 이어서 서버에 전송 (예: 1-1-1-1). 성공하면 대화상자를 닫음
  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(matchProgressProvider.notifier).recordScore(
            rSeq: widget.reservation.r_seq,
            team: _teamController.text,
            eCode: _sport.e_code,
            stats: _stats,
            score: _scoreController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnack(context, '${widget.reservation.c_name}님의 경기 결과를 등록했어요.');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.reservation.c_name}님 경기 결과 등록'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('종목', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              // 종목 선택 : 바꾸면 아래 스탯 항목 이름도 함께 바뀜
              DropdownButtonFormField<MatchSportOption>(
                initialValue: _sport,
                items: [
                  for (final s in kMatchSports) DropdownMenuItem(value: s, child: Text('${s.name} (${s.e_code})')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _sport = v);
                },
              ),
              const SizedBox(height: 14),
              LabeledField(
                label: '팀',
                hintText: '예) A팀',
                controller: _teamController,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              const Text('개인 스탯', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              // 스탯 4개 : 항목마다 - / + 버튼으로 숫자 조절
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(width: 90, child: Text(_sport.statLabels[i])),
                      IconButton(
                        onPressed: _stats[i] > 0 ? () => setState(() => _stats[i]--) : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text('${_stats[i]}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        onPressed: _stats[i] < 99 ? () => setState(() => _stats[i]++) : null,
                        icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              // 서버에 전송될 스탯 코드 미리보기
              Text('저장 값  ${_stats.join('-')}  (${_sport.statLabels.join(' / ')})',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
              const SizedBox(height: 14),
              LabeledField(
                label: '전체 스코어',
                hintText: '예) 3:2',
                controller: _scoreController,
                maxLength: 20,
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.danger)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        SizedBox(
          width: 120,
          child: FilledButton(
            onPressed: _canSubmit && !_submitting ? _submit : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : const Text('등록'),
          ),
        ),
      ],
    );
  }
}
