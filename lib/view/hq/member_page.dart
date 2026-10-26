// [이 파일의 역할]
// 본사 관리자 "회원 관리" 화면 (왼쪽 목록 + 오른쪽 상세의 2단 구성)
//   - 위쪽 탭 : 회원 / 매니저 전환 + 전체 인원 표시
//   - 왼쪽    : 검색창(이름·아이디·전화번호) + 목록. 항목을 누르면 오른쪽에 상세 표시
//   - 오른쪽  : 회원 → 기본 정보, 제재 이력, 받은 신고 / 매니저 → 기본 정보, 배정 구장, 평가, 제재 이력, 채용
// 조회 전용 화면 (수정·삭제 기능 없음)
// 상태관리 : mgmtTabProvider, memberListProvider/managerListProvider, selected*IdProvider, *DetailProvider

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/management_model.dart';
import '../../vm/management_notifier.dart';
import '../common/admin_widgets.dart';
import '../common/app_theme.dart';
import '../common/common_widgets.dart';

class MemberPage extends ConsumerWidget {
  const MemberPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(mgmtTabProvider);
    final isMember = tab == MgmtTab.member;

    // 현재 탭의 전체 인원 (목록을 불러오기 전에는 표시하지 않음)
    final total = isMember
        ? ref.watch(memberListProvider).value?.total
        : ref.watch(managerListProvider).value?.total;

    return Column(
      children: [
        PageHeader(
          title: '회원 관리',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 회원 / 매니저 전환
              SegmentedButton<MgmtTab>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: MgmtTab.member, label: Text('회원')),
                  ButtonSegment(value: MgmtTab.manager, label: Text('매니저')),
                ],
                selected: {tab},
                onSelectionChanged: (s) => ref.read(mgmtTabProvider.notifier).select(s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.primarySoft,
                  selectedForegroundColor: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 16),
              Text(total == null ? '' : '전체 $total명',
                  style: const TextStyle(color: AppColors.textSub)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              // ---------- 왼쪽 목록 ----------
              Container(
                width: 380,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(right: BorderSide(color: AppColors.line)),
                ),
                child: isMember ? const _MemberListPane() : const _ManagerListPane(),
              ),
              // ---------- 오른쪽 상세 ----------
              Expanded(
                child: isMember ? const _MemberDetailPane() : const _ManagerDetailPane(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------
// 회원 목록
// ------------------------------------------------------------

class _MemberListPane extends ConsumerWidget {
  const _MemberListPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(memberListProvider);
    final selected = ref.watch(selectedMemberIdProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: SearchField(
            hintText: '이름 · 아이디 · 전화번호 검색',
            onSearch: (keyword) => ref.read(memberListProvider.notifier).search(keyword),
          ),
        ),
        const Divider(),
        Expanded(
          child: listAsync.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              error: error,
              onRetry: () => ref.read(memberListProvider.notifier).refresh(),
            ),
            data: (data) {
              if (data.results.isEmpty) {
                return const EmptyView(icon: Icons.person_search, message: '조건에 맞는 회원이 없어요.');
              }
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => ref.read(memberListProvider.notifier).refresh(),
                child: ListView.builder(
                  itemCount: data.results.length,
                  itemBuilder: (context, i) {
                    final m = data.results[i];
                    return SelectableTile(
                      selected: m.c_id_seq == selected,
                      onTap: () => ref.read(selectedMemberIdProvider.notifier).select(m.c_id_seq),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1줄 : @아이디 · 선호 종목 + 계정 상태 배지
                          Row(
                            children: [
                              Expanded(
                                child: Text('@${m.c_id_seq} · ${preferStockName(m.c_prefer_stock)}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                              ),
                              _memberStatusBadge(m),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(m.c_name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('${m.match_count}경기 · 가입 ${shortDate(m.c_signupdate)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
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

// 회원 상태 배지 : 탈퇴 > 경고 N > 정상 순서로 표시
Widget _memberStatusBadge(MemberSummary m) {
  if (m.isWithdrawn) return const StatusBadge('탈퇴', tone: StatusTone.gray);
  if (m.warning_count > 0) return StatusBadge('경고 ${m.warning_count}', tone: StatusTone.red);
  return const StatusBadge('정상', tone: StatusTone.green);
}

// ------------------------------------------------------------
// 회원 상세
// ------------------------------------------------------------

class _MemberDetailPane extends ConsumerWidget {
  const _MemberDetailPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedMemberIdProvider);
    if (selected == null) {
      return const EmptyView(icon: Icons.touch_app_outlined, message: '왼쪽 목록에서 회원을 선택해주세요.');
    }

    final detailAsync = ref.watch(memberDetailProvider(selected));
    return detailAsync.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(memberDetailProvider(selected)),
      ),
      data: (d) {
        final m = d.summary;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 프로필 + 기본 정보
            SectionCard(
              title: '기본 정보',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileHeader(
                    name: m.c_name,
                    sub: '@${m.c_id_seq}',
                    badge: m.isWithdrawn
                        ? const StatusBadge('탈퇴', tone: StatusTone.gray)
                        : const StatusBadge('이용 가능', tone: StatusTone.green),
                  ),
                  const SizedBox(height: 16),
                  InfoGrid(tiles: [
                    InfoTile('계정 상태', m.isWithdrawn ? '탈퇴' : (m.warning_count > 0 ? '경고' : '정상'),
                        valueColor: m.warning_count > 0 ? AppColors.danger : null),
                    InfoTile('유효 경고', '${m.warning_count}회',
                        valueColor: m.warning_count > 0 ? AppColors.danger : null),
                    InfoTile('참여 경기', '${m.match_count}경기'),
                    InfoTile('가입일', shortDate(m.c_signupdate)),
                    InfoTile('선호 종목', preferStockName(m.c_prefer_stock)),
                    InfoTile('전화번호', d.c_phone ?? '-'),
                    InfoTile('받은 신고', '${d.received_report_count}건'),
                    InfoTile('한 신고', '${d.sent_report_count}건'),
                    InfoTile('소속팀', d.c_team ?? '-'),
                    InfoTile('선호 포지션', d.c_position ?? '-'),
                    InfoTile('성별', d.c_gender ?? '-'),
                    if (m.isWithdrawn) InfoTile('탈퇴일', shortDate(m.c_deletdate)),
                  ]),
                  if ((d.c_address ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('주소  ${d.c_address}',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: '제재 이력',
              child: d.sanctions.isEmpty
                  ? const _EmptyLine('제재 이력이 없어요.')
                  : _SanctionTable(items: d.sanctions),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: '받은 신고',
              child: d.received_reports.isEmpty
                  ? const _EmptyLine('받은 신고가 없어요.')
                  : Column(
                      children: [
                        for (final r in d.received_reports)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.line),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text('#${r.r_seq} · ${shortDate(r.r_date)}',
                                          style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                                    ),
                                    StatusBadge(r.state,
                                        tone: r.state == '처리완료' ? StatusTone.green : StatusTone.orange),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(r.r_reason ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------
// 매니저 목록
// ------------------------------------------------------------

class _ManagerListPane extends ConsumerWidget {
  const _ManagerListPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(managerListProvider);
    final selected = ref.watch(selectedManagerIdProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: SearchField(
            hintText: '이름 · 아이디 · 전화번호 검색',
            onSearch: (keyword) => ref.read(managerListProvider.notifier).search(keyword),
          ),
        ),
        const Divider(),
        Expanded(
          child: listAsync.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              error: error,
              onRetry: () => ref.read(managerListProvider.notifier).refresh(),
            ),
            data: (data) {
              if (data.results.isEmpty) {
                return const EmptyView(icon: Icons.person_search, message: '조건에 맞는 매니저가 없어요.');
              }
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => ref.read(managerListProvider.notifier).refresh(),
                child: ListView.builder(
                  itemCount: data.results.length,
                  itemBuilder: (context, i) {
                    final m = data.results[i];
                    return SelectableTile(
                      selected: m.m_id == selected,
                      onTap: () => ref.read(selectedManagerIdProvider.notifier).select(m.m_id),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('@${m.m_id} · ${m.m_workplace ?? '-'}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                              ),
                              // 제재가 있으면 빨간 배지, 없으면 정상
                              m.sanction_count > 0
                                  ? StatusBadge('제재 ${m.sanction_count}', tone: StatusTone.red)
                                  : const StatusBadge('정상', tone: StatusTone.green),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(m.m_name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(m.m_phone ?? '-',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
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
// 매니저 상세
// ------------------------------------------------------------

class _ManagerDetailPane extends ConsumerWidget {
  const _ManagerDetailPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedManagerIdProvider);
    if (selected == null) {
      return const EmptyView(icon: Icons.touch_app_outlined, message: '왼쪽 목록에서 매니저를 선택해주세요.');
    }

    final detailAsync = ref.watch(managerDetailProvider(selected));
    return detailAsync.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(managerDetailProvider(selected)),
      ),
      data: (d) {
        final m = d.summary;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SectionCard(
              title: '기본 정보',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileHeader(
                    name: m.m_name,
                    sub: '@${m.m_id}',
                    badge: m.sanction_count > 0
                        ? StatusBadge('제재 ${m.sanction_count}건', tone: StatusTone.red)
                        : const StatusBadge('정상', tone: StatusTone.green),
                  ),
                  const SizedBox(height: 16),
                  InfoGrid(tiles: [
                    InfoTile('전화번호', m.m_phone ?? '-'),
                    InfoTile('성별', m.m_gender ?? '-'),
                    InfoTile('근무지', m.m_workplace ?? '-'),
                    InfoTile('채용일', d.hires.isEmpty ? '-' : shortDate(d.hires.first)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: '배정 구장',
              child: d.assigns.isEmpty
                  ? const _EmptyLine('배정된 구장이 없어요.')
                  : Column(
                      children: [
                        for (final a in d.assigns)
                          _LineItem(
                            title: a.g_name,
                            trailing: '${a.a_day ?? '-'} · ${a.a_time ?? '-'}',
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: '평가',
              child: d.evaluates.isEmpty
                  ? const _EmptyLine('평가 내역이 없어요.')
                  : Column(
                      children: [
                        for (final e in d.evaluates)
                          _LineItem(title: e.e_detail ?? '-', trailing: shortDate(e.e_date)),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: '제재 이력',
              child: d.sanctions.isEmpty
                  ? const _EmptyLine('제재 이력이 없어요.')
                  : _SanctionTable(items: d.sanctions),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------
// 공통 조각
// ------------------------------------------------------------

// 상세 상단 프로필 : 원형 아바타 + 이름 + 아이디 + 오른쪽 상태 배지
class _ProfileHeader extends StatelessWidget {
  final String name;
  final String sub;
  final Widget badge;
  const _ProfileHeader({required this.name, required this.sub, required this.badge});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.sidebar,
          child: Text(name.isEmpty ? '?' : name.substring(0, 1),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        const SizedBox(width: 14),
        Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
        const Spacer(),
        badge,
      ],
    );
  }
}

// 제재 이력 표 : 부과일 / 제재 / 사유 / 상태
class _SanctionTable extends StatelessWidget {
  final List<SanctionItem> items;
  const _SanctionTable({required this.items});

  @override
  Widget build(BuildContext context) {
    const headStyle = TextStyle(fontSize: 12, color: AppColors.textSub);
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(96),
        1: FixedColumnWidth(86),
        2: FlexColumnWidth(),
        3: FixedColumnWidth(64),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        const TableRow(
          children: [
            Padding(padding: EdgeInsets.only(bottom: 8), child: Text('부과일', style: headStyle)),
            Padding(padding: EdgeInsets.only(bottom: 8), child: Text('제재', style: headStyle)),
            Padding(padding: EdgeInsets.only(bottom: 8), child: Text('사유', style: headStyle)),
            Padding(padding: EdgeInsets.only(bottom: 8), child: Text('상태', style: headStyle)),
          ],
        ),
        for (final s in items)
          TableRow(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(shortDate(s.date))),
              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('경고 1회')),
              Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(s.detail ?? '-')),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(s.status,
                      tone: s.status == '유효' ? StatusTone.red : StatusTone.gray),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// "내용 ........ 오른쪽 문구" 한 줄 (배정 구장·평가 목록용)
class _LineItem extends StatelessWidget {
  final String title;
  final String trailing;
  const _LineItem({required this.title, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(trailing, style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
        ],
      ),
    );
  }
}

// 섹션 안에 데이터가 없을 때 보여주는 한 줄 안내
class _EmptyLine extends StatelessWidget {
  final String message;
  const _EmptyLine(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(message, style: const TextStyle(color: AppColors.textSub)),
    );
  }
}
