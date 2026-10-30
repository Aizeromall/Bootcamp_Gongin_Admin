import '../shared/async_screen_state.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../match/manager_schedule_panel.dart';
import '../match/manager_result_panel.dart';

// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';

import '../../model/login_role.dart';
import '../management/management_page.dart';
import '../inquiry/inquiry_page.dart';
import '../ground/ground_page.dart';
import '../report/report_page.dart';
import '../education/education_page.dart';
import '../shared/education_shell.dart';
import '../headquarters/home_panel.dart';
import '../headquarters/announcement_panel.dart';
import '../headquarters/appeal_panel.dart';
import '../headquarters/team_panel.dart';
import '../headquarters/approval_panel.dart';
import '../headquarters/match_updates_panel.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({
    super.key,
    required this.role,
    required this.userId,
    this.userName,
    this.department,
    required this.onLogout,
  });
  final LoginRole role;
  final String userId;
  final String? userName;
  final String? department;
  final VoidCallback onLogout;
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with AsyncScreenState<DashboardPage> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {
    'selected': widget.role == LoginRole.headquarters ? 6 : 0,
  };
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  int get selected => screenValue<int>('selected');
  set selected(int value) => setScreenValue('selected', value);
  // 수정 일 : 2026-10-27 / 작업자 : 양태건
  // 본사는 실제 API 현황을 모은 대시보드에서 시작합니다.

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.role != widget.role) {
      resetScreenScope();
    }
  }

  @override
  Widget build(BuildContext context) {
    watchScreen();
    final headquarters = widget.role == LoginRole.headquarters;
    final labels = headquarters
        ? [
            '회원 관리',
            '매니저 관리',
            '문의 내역',
            '구장 조회',
            '신고 내역',
            '매니저 교육',
            '대시보드',
            '공지사항',
            '제재 · 이의신청',
            '팀 관리',
            '품의서 작성',
            '품의 내역',
            '매치 관리',
          ]
        : ['내 매치', '실력매칭', '팀매칭', '공지사항'];
    final icons = headquarters
        ? [
            Icons.people_outline,
            Icons.badge_outlined,
            Icons.question_answer_outlined,
            Icons.stadium_outlined,
            Icons.flag_outlined,
            Icons.menu_book_outlined,
            Icons.dashboard_outlined,
            Icons.campaign_outlined,
            Icons.balance_outlined,
            Icons.shield_outlined,
            Icons.note_add_outlined,
            Icons.receipt_long_outlined,
            Icons.sports_soccer_outlined,
          ]
        : [
            Icons.sports_soccer,
            Icons.history,
            Icons.shield_outlined,
            Icons.campaign_outlined,
          ];
    final pages = headquarters
        ? <Widget>[
            const ManagementPage(key: ValueKey('members'), managers: false),
            const ManagementPage(key: ValueKey('managers'), managers: true),
            InquiryPage(staffId: widget.userId),
            const GroundPage(),
            // 수정 일 : 2026-10-27 / 작업자 : 양태건
            // 본사 직원에게만 신고 목록과 심의 시작 화면을 제공합니다.
            ReportPage(
              key: ValueKey('reports:${widget.userId}'),
              staffId: widget.userId,
            ),
            EducationPage(
              key: ValueKey('education:${widget.userId}'),
              staffId: widget.userId,
              onLogout: widget.onLogout,
            ),
            HeadquartersHome(
              staffId: widget.userId,
              onNavigate: (index) => updateScreen(() => selected = index),
            ),
            AnnouncementPanel(staffId: widget.userId),
            AppealPanel(staffId: widget.userId),
            TeamPanel(staffId: widget.userId),
            ApprovalPanel(
              key: ValueKey('approval-write:${widget.userId}'),
              staffId: widget.userId,
              write: true,
            ),
            ApprovalPanel(
              key: ValueKey('approval-history:${widget.userId}'),
              staffId: widget.userId,
            ),
            HeadquartersMatchWorkbench(
              key: ValueKey('staff-matches:${widget.userId}'),
              staffId: widget.userId,
            ),
          ]
        // 작업자 : 양태건
        // 수정일 : 2026-10-26
        // [수정 시작] 완료된 경기만 지난 매치로 분리합니다.
        : <Widget>[
            ManagerSchedulePanel(
              key: ValueKey('current:${widget.userId}'),
              managerId: widget.userId,
              onCompleted: () => updateScreen(() => selected = 1),
              onTeamCompleted: () => updateScreen(() => selected = 2),
            ),
            // 수정 일 : 2026-10-29 / 작업자 : 양태건
            // 실력매칭·팀매칭은 각각 등록된 결과만 표시합니다.
            ManagerResultsPanel(
              key: ValueKey('pickup-results:${widget.userId}'),
              managerId: widget.userId,
              kind: 'pickup',
            ),
            ManagerResultsPanel(
              key: ValueKey('team-results:${widget.userId}'),
              managerId: widget.userId,
              kind: 'team',
            ),
            // 수정 일 : 2026-10-30 / 작업자 : 양태건
            // 매니저 대상 공지를 읽기 전용 탭으로 연결합니다.
            AnnouncementPanel(
              key: ValueKey('manager-announcements:${widget.userId}'),
              staffId: widget.userId,
              manager: true,
            ),
          ];
    // 수정 일 : 2026-10-27 / 작업자 : 양태건
    // 첨부 관리자 목업의 사이드바를 본사 업무에 공통 적용합니다.
    // 수정 일 : 2026-10-29 / 작업자 : 양태건
    // 본사·매니저 평가 메뉴를 제거하고 역할은 명시적으로 전달합니다.
    return EducationShell(
      headquarters: headquarters,
      labels: labels,
      icons: icons,
      selected: selected,
      onSelected: (index) => updateScreen(() => selected = index),
      userId: widget.userId,
      userName: widget.userName,
      department: widget.department,
      onLogout: widget.onLogout,
      child: selected == 5
          ? pages[selected]
          : Column(
              children: [
                Container(
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE6E9F0)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          headquarters
                              ? labels[selected]
                              : '공IN · ${labels[selected]}',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF14203A),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '로그아웃',
                        onPressed: widget.onLogout,
                        icon: const Icon(Icons.logout, size: 18),
                      ),
                    ],
                  ),
                ),
                Expanded(child: pages[selected]),
              ],
            ),
    );
  }
}
// 최종 수정일 : 2026-10-24

// [수정 끝]

// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
