// ###  2026.10.23 매치 매니저 경기 관리 Riverpod 상태관리 구성
//
// [이 파일의 역할]
// 매치 매니저 앱 "내 매치" 화면의 담당 구장 예약 조회, 출석 체크, 경기 결과 등록을 관리하는 ViewModel
//   View  : lib/view/manager/my_match_page.dart
//   VM    : 이 파일
//
// [연결된 서버 API] (python/FastAPI/match)
//   GET  /match/list/{m_id}                   담당 구장의 예약 목록 (예약 회원 정보 포함)
//   POST /match/attendance/{m_id}/{r_seq}     출석 체크 {c_r_r_attendance: true/false}
//   POST /match/score/{m_id}/{r_seq}          경기 결과 등록 {c_r_r_team, e_code, c_r_r_statcode, c_r_r_score}
//
// 참고 : 이미 체크한 출석을 조회하는 API가 없어서, 이 화면에서 체크한 결과는 앱 안에서만 기억함 (새로고침하면 사라짐)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/manager_match_model.dart';
import 'admin_auth_notifier.dart';
import 'api_client.dart';

// ------------------------------------------------------------
// 담당 구장 예약 목록
// ------------------------------------------------------------

class MatchListNotifier extends AsyncNotifier<MatchListData> {
  // 로그인한 매니저의 아이디로 조회 (로그인·로그아웃으로 세션이 바뀌면 자동으로 다시 조회)
  @override
  Future<MatchListData> build() async {
    final session = ref.watch(adminSessionProvider);
    if (session == null || session.role != AdminRole.manager) {
      return MatchListData(m_name: '', reservations: []);
    }
    return _fetch(session.id);
  }

  Future<MatchListData> _fetch(String mId) async {
    final data = await apiGet('/match/list/$mId');
    return MatchListData.fromJson(data);
  }

  // 새로고침 (아래로 당겨서 새로고침 / 등록 후)
  Future<void> refresh() async {
    final session = ref.read(adminSessionProvider);
    if (session == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(session.id));
  }
}

final matchListProvider =
    AsyncNotifierProvider<MatchListNotifier, MatchListData>(MatchListNotifier.new, retry: noRetry);

// ------------------------------------------------------------
// 출석·결과 처리 진행 상태 (이 화면에서 처리한 예약번호 기억)
// ------------------------------------------------------------

class MatchProgress {
  final Map<int, bool> attendance; // 예약번호 → 출석(true)/결석(false)
  final Set<int> recorded; // 경기 결과를 등록한 예약번호
  final Set<int> busy; // 지금 서버에 요청 중인 예약번호

  const MatchProgress({
    this.attendance = const {},
    this.recorded = const {},
    this.busy = const {},
  });

  MatchProgress copyWith({Map<int, bool>? attendance, Set<int>? recorded, Set<int>? busy}) {
    return MatchProgress(
      attendance: attendance ?? this.attendance,
      recorded: recorded ?? this.recorded,
      busy: busy ?? this.busy,
    );
  }
}

class MatchProgressNotifier extends Notifier<MatchProgress> {
  @override
  MatchProgress build() => const MatchProgress();

  // 로그인한 매니저 아이디 (없으면 오류)
  String _managerId() {
    final session = ref.read(adminSessionProvider);
    if (session == null) throw ApiException('로그인 정보가 없어요. 다시 로그인해주세요.');
    return session.id;
  }

  // 요청 중 표시를 켜고 끄는 공통 함수
  void _setBusy(int rSeq, bool on) {
    final next = {...state.busy};
    on ? next.add(rSeq) : next.remove(rSeq);
    state = state.copyWith(busy: next);
  }

  // 출석 체크 : attended가 true면 출석, false면 결석. 실패하면 서버 오류 문구를 담은 예외를 던짐
  // (이미 체크된 예약은 서버가 409 "이미 출석 체크가 등록된 예약입니다."를 줌)
  Future<void> checkAttendance(int rSeq, bool attended) async {
    final mId = _managerId();
    _setBusy(rSeq, true);
    try {
      await apiPost('/match/attendance/$mId/$rSeq', {'c_r_r_attendance': attended});
      state = state.copyWith(attendance: {...state.attendance, rSeq: attended});
    } finally {
      _setBusy(rSeq, false);
    }
  }

  // 경기 결과 등록 : 스탯 4개는 "-"로 이어서 statcode로 전송 (예: [1,1,1,1] → "1-1-1-1")
  // 출석을 먼저 체크하지 않은 예약은 서버가 409 "회원의 출석 처리를 먼저 완료해 주세요."를 줌
  Future<void> recordScore({
    required int rSeq,
    required String team,
    required String eCode,
    required List<int> stats,
    required String score,
  }) async {
    final mId = _managerId();
    _setBusy(rSeq, true);
    try {
      await apiPost('/match/score/$mId/$rSeq', {
        'c_r_r_team': team.trim(),
        'e_code': eCode,
        'c_r_r_statcode': stats.join('-'),
        'c_r_r_score': score.trim(),
      });
      state = state.copyWith(recorded: {...state.recorded, rSeq});
    } finally {
      _setBusy(rSeq, false);
    }
  }
}

final matchProgressProvider =
    NotifierProvider<MatchProgressNotifier, MatchProgress>(MatchProgressNotifier.new);
