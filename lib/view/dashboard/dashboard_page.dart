// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';

import '../../model/login_role.dart';
import '../management/management_page.dart';
import '../inquiry/inquiry_page.dart';
import '../match/match_page.dart';
import '../ground/ground_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.role,
    required this.userId,
    this.userName,
    required this.onLogout,
  });
  final LoginRole role;
  final String userId;
  final String? userName;
  final VoidCallback onLogout;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final headquarters = widget.role == LoginRole.headquarters;
    final labels = headquarters
        ? ['회원 관리', '매니저 관리', '문의 관리', '구장 조회']
        : ['담당 경기'];
    final icons = headquarters
        ? [
            Icons.people_outline,
            Icons.badge_outlined,
            Icons.question_answer_outlined,
            Icons.stadium_outlined,
          ]
        : [Icons.sports_soccer];
    final pages = headquarters
        ? <Widget>[
            const ManagementPage(key: ValueKey('members'), managers: false),
            const ManagementPage(key: ValueKey('managers'), managers: true),
            InquiryPage(staffId: widget.userId),
            const GroundPage(),
          ]
        : <Widget>[MatchPage(managerId: widget.userId)];
    return Scaffold(
      appBar: AppBar(
        title: Text('공IN · ${labels[selected]}'),
        actions: [
          Center(
            child: Text(
              '${widget.role.label} · ${widget.userName ?? widget.userId}',
            ),
          ),
          IconButton(
            tooltip: '로그아웃',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (constraints.maxWidth >= 760 && headquarters)
              NavigationRail(
                extended: constraints.maxWidth >= 1100,
                selectedIndex: selected,
                onDestinationSelected: (index) =>
                    setState(() => selected = index),
                destinations: [
                  for (var i = 0; i < labels.length; i++)
                    NavigationRailDestination(
                      icon: Icon(icons[i]),
                      label: Text(labels[i]),
                    ),
                ],
              ),
            Expanded(child: pages[selected]),
          ],
        ),
      ),
      bottomNavigationBar:
          MediaQuery.sizeOf(context).width < 760 && headquarters
          ? NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (index) =>
                  setState(() => selected = index),
              destinations: [
                for (var i = 0; i < labels.length; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
              ],
            )
          : null,
    );
  }
}
// 최종 수정일 : 2026-10-24
