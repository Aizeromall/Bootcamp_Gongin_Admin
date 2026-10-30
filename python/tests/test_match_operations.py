# 작업자 : 양태건
# 수정일 : 2026-10-26
# [추가 시작] DB 변경 없이 상태 전환과 기록·검증 규칙을 검사합니다.
import copy
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from FastAPI.match.match_operations import (
    Command,
    initial_state,
    mutate,
    schedule_matches,
    totals,
)
from fastapi import HTTPException
from FastAPI.match import match_operations as operations


class MatchRulesTest(unittest.TestCase):
    def setUp(self):
        self.players = [
            dict(
                r_seq=i,
                c_id_seq=f"test{i}_01",
                c_name=f"선수{i}",
                c_position="수비",
                c_rating=1500,
                c_prefer_stock="1",
            )
            for i in (1, 2)
        ]
        self.state = initial_state(self.players)
        self.record = dict(
            match_code="test", m_id="test", g_code=1, status="attendance", version=0
        )
        self.cursor = MagicMock()
        self.cursor.fetchall.return_value = []

    def call(self, action, **kwargs):
        mutate(
            self.cursor,
            self.record,
            self.state,
            Command(version=0, action=action, **kwargs),
        )

    def live(self):
        for p in self.players:
            self.call("attendance", r_seq=p["r_seq"], attendance=True)
        self.call("teams", assignments={"1": "A", "2": "B"})
        self.call("start")

    def test_schedule_checks_ground_day_and_time(self):
        row = dict(g_code=1, r_date="2026-10-26", rs_time="19:00:00")
        self.assertTrue(
            schedule_matches(
                row, [dict(g_code=1, a_day="월,수,금", a_time="18:00~22:00")]
            )
        )
        for a in [
            dict(g_code=2, a_day="월", a_time="18:00~22:00"),
            dict(g_code=1, a_day="화", a_time="18:00~22:00"),
            dict(g_code=1, a_day="월", a_time="09:00~10:00"),
        ]:
            self.assertFalse(schedule_matches(row, [a]))

    def test_goal_and_undo_restore_player_and_team(self):
        self.live()
        self.call("event", r_seq=1, kind="goal")
        stats, score = totals(self.state)
        # 작업자 : 신현진 / 수정일 : 2026-10-29 스탯은 스탯코드 키(G = 골) 기준
        self.assertEqual(stats["1"]["G"], 1)
        self.assertEqual(score, {"A": 1, "B": 0})
        self.call("undo")
        self.assertEqual(totals(self.state)[1], {"A": 0, "B": 0})

    def test_attendance_can_be_corrected_before_start(self):
        self.call("attendance", r_seq=1, attendance=True)
        self.call("attendance", r_seq=1, attendance=False)
        self.assertFalse(self.state["attendance"]["1"])

    # 수정 일 : 2026-10-30 / 작업자 : 양태건
    def test_attendance_threshold_boundary_and_direct_start(self):
        for total, present, allowed in [(10, 7, True), (10, 6, False),
                                        (12, 8, False), (12, 9, True), (0, 0, False)]:
            with self.subTest(total=total, present=present):
                state = initial_state([dict(self.players[0], r_seq=i, c_id_seq=f'm{i}')
                                       for i in range(total)])
                state['attendance'] = {str(i): i < present for i in range(total)}
                if allowed:
                    operations.require_start_attendance(state)
                else:
                    with self.assertRaises(HTTPException) as caught:
                        operations.require_start_attendance(state)
                    self.assertEqual(caught.exception.status_code, 409)
        self.state['attendance'] = {'1': True, '2': False}
        with self.assertRaises(HTTPException):
            self.call('teams')
        self.assertEqual(self.record['status'], 'attendance')

    def test_start_requires_all_attendees_assigned(self):
        self.state["attendance"] = {"1": True, "2": True}
        self.call("teams", assignments={"1": "A"})
        with self.assertRaises(HTTPException):
            self.call("start")

    def test_absent_player_cannot_be_assigned(self):
        self.state["attendance"] = {"1": True, "2": False}
        self.record["status"] = "teams"
        self.state["assignments"] = {"1": "A", "2": "B"}
        with self.assertRaises(HTTPException):
            self.call("start")

    # 작업자 : 신현진 / 수정일 : 2026-10-29
    # 4종목을 지원하므로 "축구만 시작 가능" 대신 "종목이 섞인 경기는 시작 불가"를 확인
    def test_mixed_sports_cannot_start(self):
        self.state["players"][0]["c_prefer_stock"] = "3"
        with self.assertRaises(HTTPException):
            self.call("teams")

    def test_red_card_blocks_more_events_but_can_be_undone(self):
        self.live()
        self.call("event", r_seq=1, kind="red")
        with self.assertRaises(HTTPException):
            self.call("event", r_seq=1, kind="goal")
        self.call("undo")
        self.call("event", r_seq=1, kind="goal")

    def test_injury_is_validated_and_saved_separately(self):
        self.live()
        with self.assertRaises(HTTPException):
            self.call("injury", r_seq=1)
        self.call(
            "injury",
            r_seq=1,
            body_parts=["발목·발"],
            severity="mild",
            measures=["경기 일시 중단"],
            description="발목 부상",
            occurred_seconds=0,
        )
        self.assertEqual(len(self.state["injuries"]), 1)
        self.assertIsNone(self.state["running_since"])
        self.assertEqual(totals(self.state)[1], {"A": 0, "B": 0})

    # 작업자 : 신현진 / 수정일 : 2026-10-29
    # 결과 등록 시 등급 점수 반영 함수가 DB 회원 점수를 읽으므로 가짜 함수로 바꿔서 확인
    @patch.object(operations, "apply_member_ratings", return_value=[])
    def test_final_publish_is_idempotent_and_locks_result(self, _ratings):
        self.live()
        self.call("event", r_seq=1, kind="goal")
        self.call("end")
        self.call("publish")
        calls = self.cursor.execute.call_count
        self.call("publish")
        self.assertEqual(self.cursor.execute.call_count, calls)
        with self.assertRaises(HTTPException):
            self.call("event", r_seq=1, kind="goal")

    def test_stale_command_cannot_duplicate_event(self):
        self.live()
        self.record["version"] = 2
        before = copy.deepcopy(self.state["events"])
        with self.assertRaises(HTTPException):
            self.call("event", r_seq=1, kind="goal")
        self.assertEqual(self.state["events"], before)

    def test_review_edit_keeps_clock_paused(self):
        self.live()
        self.call("end")
        self.call("edit")
        self.assertEqual(self.record["status"], "live")
        self.assertIsNone(self.state["running_since"])

    # 작업자 : 신현진
    # 수정일 : 2026-10-29
    # [추가 시작] 종목별 기록 버튼·팀 점수 규칙과 결과 등록 시 등급 점수 반영을 확인합니다.
    def use_sport(self, number):
        for p in self.state["players"]:
            p["c_prefer_stock"] = number

    def test_basketball_points_and_three_pointer(self):
        self.use_sport("2")
        self.live()
        self.call("event", r_seq=1, kind="three_point")
        self.call("event", r_seq=1, kind="two_point")
        self.call("event", r_seq=2, kind="free_throw")
        stats, score = totals(self.state)
        self.assertEqual((stats["1"]["P"], stats["1"]["T"]), (5, 1))
        self.assertEqual(score, {"A": 5, "B": 1})

    def test_volleyball_error_gives_opponent_point(self):
        self.use_sport("4")
        self.live()
        self.call("event", r_seq=1, kind="ace")
        self.call("event", r_seq=1, kind="error")
        stats, score = totals(self.state)
        self.assertEqual((stats["1"]["SA"], stats["1"]["E"]), (1, 1))
        self.assertEqual(score, {"A": 1, "B": 1})

    def baseball_live(self, extra_a=()):
        # 야구 : A팀 타자 1 + 주자 3·4 (+ extra_a), B팀 2·5·6 (팀 인원 차이 1명 이하)
        for i in (3, 4, 5, 6, *extra_a):
            self.players.append(dict(r_seq=i, c_id_seq=f"test{i}_03", c_name=f"선수{i}",
                                     c_position="주자", c_rating=1500, c_prefer_stock="3"))
        self.state = initial_state(self.players)
        self.use_sport("3")
        for p in self.players:
            self.call("attendance", r_seq=p["r_seq"], attendance=True)
        assignments = {"1": "A", "3": "A", "4": "A", "5": "B", "2": "B", "6": "B"}
        assignments.update({str(i): "A" for i in extra_a})
        self.call("teams", assignments=assignments)
        self.call("start")

    def test_baseball_homerun_scores_by_runners(self):
        # 1점 / 2점 / 3점 홈런 : 홈런 버튼 1번 + 홈인 주자 선택
        self.baseball_live()
        for runners, expected in (([], 1), ([3], 2), ([3, 4], 3)):
            before = totals(self.state)[1]["A"]
            self.call("event", r_seq=1, kind="homerun", runners=runners)
            self.assertEqual(totals(self.state)[1]["A"] - before, expected)
        stats, score = totals(self.state)
        # 타자 : 홈런 3, 안타 3, 본인 득점 3, 타점 1 + 2 + 3 = 6
        self.assertEqual((stats["1"]["HR"], stats["1"]["H"], stats["1"]["RS"], stats["1"]["RBI"]), (3, 3, 3, 6))
        # 주자 3 : 득점 2 (2점·3점 홈런) / 주자 4 : 득점 1 (3점 홈런), 주자는 타점 없음
        self.assertEqual((stats["3"]["RS"], stats["3"]["RBI"], stats["4"]["RS"]), (2, 0, 1))
        self.assertEqual(score, {"A": 6, "B": 0})

    def test_baseball_grand_slam_and_undo(self):
        # 만루 홈런 : 주자 3명 → 팀 +4, 타자 4타점 / 마지막 기록 취소는 홈런 전체를 되돌림
        self.baseball_live(extra_a=(7,))
        self.call("event", r_seq=1, kind="homerun", runners=[3, 4, 7])
        stats, score = totals(self.state)
        self.assertEqual((score["A"], stats["1"]["RBI"]), (4, 4))
        self.assertEqual([stats[str(r)]["RS"] for r in (3, 4, 7)], [1, 1, 1])
        self.call("undo")
        stats, score = totals(self.state)
        self.assertEqual((score["A"], stats["1"]["RBI"], stats["3"]["RS"]), (0, 0, 0))

    def test_baseball_runners_are_validated(self):
        self.baseball_live()
        for kind, runners in (
            ("homerun", [5]),        # 상대 팀 선수
            ("homerun", [1]),        # 타자 본인
            ("homerun", [3, 3]),     # 같은 주자 중복
            ("hit", [3]),            # 홈런이 아닌 기록
        ):
            with self.assertRaises(HTTPException):
                self.call("event", r_seq=1, kind=kind, runners=runners)
        with self.assertRaises(Exception):
            Command(version=0, action="event", r_seq=1, kind="homerun", runners=[3, 4, 5, 6])  # 4명 초과
        self.assertEqual(totals(self.state)[1], {"A": 0, "B": 0})

    def test_event_of_other_sport_is_rejected(self):
        self.use_sport("2")
        self.live()
        with self.assertRaises(HTTPException):
            self.call("event", r_seq=1, kind="goal")

    @patch.object(operations, "apply_member_ratings", return_value=[])
    def test_publish_saves_sport_statcode_and_applies_ratings(self, ratings):
        self.use_sport("2")
        self.live()
        self.call("event", r_seq=1, kind="three_point")
        self.call("end")
        self.call("publish")
        updates = [c.args[1] for c in self.cursor.execute.call_args_list
                   if c.args[0].startswith("UPDATE c_result_record SET c_r_r_team")]
        self.assertEqual(updates[0][1:4], ("BASKETBALL", "P:3,T:1,A:0,RB:0,F:0,TO:0", "3:0"))
        args = ratings.call_args.args
        self.assertEqual(args[1], "BASKETBALL")
        self.assertEqual([p["c_id_seq"] for p in args[2]], ["test1_01"])
        self.assertEqual(args[4:], (3, 0))
        # 회원 결과 기록에 반영 전 / 후 점수를 저장하도록 경기코드를 같이 넘김
        self.assertEqual(ratings.call_args.kwargs["match_code"], self.record["match_code"])

    # [추가 끝]


# 작업자 : 양태건
# 수정일 : 2026-10-26
# [추가 시작] 기존 결과는 상세 조회만 허용하고 새 진행 상태를 생성하지 않습니다.
# 수정 일 : 2026-10-30 / 작업자 : 양태건
class ConfirmedPickupTest(unittest.TestCase):
    def rows(self):
        return [dict(r_seq=i, c_id_seq=f'member{i}', g_num=2, r_date='2026-10-30',
                     reservation_category=1, r_category='1', r_c_category='', r_check=1)
                for i in (1, 2)]

    def test_only_full_confirmed_valid_today_or_future_match_is_eligible(self):
        from datetime import date
        today = date(2026, 10, 30)
        rows = self.rows()
        self.assertTrue(operations.confirmed_pickup(rows, today))
        self.assertFalse(operations.confirmed_pickup(rows[:1], today))
        self.assertFalse(operations.confirmed_pickup([rows[0], rows[0]], today))
        for field, value in [('r_check', 0), ('r_c_category', '회원 취소'),
                             ('r_category', '2'), ('reservation_category', 2),
                             ('r_date', '2026-10-29'), ('g_num', 0)]:
            with self.subTest(field=field):
                changed = self.rows()
                for row in changed:
                    row[field] = value
                self.assertFalse(operations.confirmed_pickup(changed, today))

    def test_list_excludes_unconfirmed_and_underfilled_matches(self):
        for confirmed, capacity, expected in [(1, 2, 1), (0, 2, 0), (1, 3, 0)]:
            with self.subTest(confirmed=confirmed, capacity=capacity):
                rows = [dict(row, r_date='2099-01-01', match_code='1_20990101_160000',
                             g_code=1, g_name='구장', rs_time='16:00:00',
                             c_prefer_stock='1', r_check=confirmed, g_num=capacity)
                        for row in self.rows()]
                conn = MagicMock()
                cursor = conn.cursor.return_value.__enter__.return_value
                cursor.fetchall.return_value = rows
                with patch.object(operations, 'connect', return_value=conn), \
                     patch.object(operations, 'assignments_for', return_value=[]), \
                     patch.object(operations, 'schedule_matches', return_value=True), \
                     patch.object(operations, 'legacy_results', return_value=[]), \
                     patch.dict(operations._MATCHES, {}, clear=True):
                    result = operations.match_list('manager')
                self.assertEqual(len(result['results']), expected)
                conn.commit.assert_not_called()

    def test_direct_detail_rejects_unconfirmed_match_before_loading_state(self):
        row = dict(self.rows()[0], match_code='1_20261030_160000', g_code=1,
                   g_name='구장', rs_time='16:00:00', r_check=0)
        cursor = MagicMock()
        cursor.fetchone.return_value = row
        cursor.fetchall.side_effect = [[row], []]
        with patch.object(operations, 'assignments_for', return_value=[]), \
             patch.object(operations, 'schedule_matches', return_value=True):
            with self.assertRaises(HTTPException) as caught:
                operations.load_match(cursor, 1, 'manager')
        self.assertEqual(caught.exception.status_code, 409)
        self.assertFalse(any(call.args[0].lstrip().startswith(('INSERT', 'UPDATE'))
                             for call in cursor.execute.call_args_list))


class LegacyResultTest(unittest.TestCase):
    def setUp(self):
        self.cursor = MagicMock()
        self.row = dict(
            r_seq=1,
            match_code="1_20261026_160000",
            reservation_category=1, r_check=1, r_category="1", r_c_category="",
            g_code=1,
            g_name="테스트 구장",
            r_date="2026-10-26",
            rs_time="16:00:00",
            re_time="18:00:00",
            c_id_seq="test_01",
            c_name="기존 회원",
            c_position="수비",
            c_rating=1500,
            c_prefer_stock="1",
        )
        self.cursor.fetchone.return_value = self.row
        self.cursor.fetchall.side_effect = [
            [self.row],
            [
                dict(
                    m_id="manager",
                    c_id_seq="test_01",
                    c_name="기존 회원",
                    c_r_r_score="5",
                    c_r_r_statcode="100",
                    c_r_r_team="이전 팀",
                    e_code="SOCCER",
                )
            ],
        ]

    def test_existing_result_is_read_only_without_new_rows(self):
        record, state = operations.load_match(self.cursor, 1, "manager")
        data = operations.response_for(record, state)
        self.assertTrue(data["legacy"])
        self.assertEqual(data["status"], "completed")
        self.assertEqual(data["state"]["legacy_records"][0]["c_r_r_score"], "5")
        self.assertIsNone(data["scores"])
        self.assertFalse(
            any("INSERT" in c.args[0] for c in self.cursor.execute.call_args_list)
        )
        with self.assertRaises(HTTPException):
            operations.mutate(
                self.cursor, record, state, Command(version=0, action="publish")
            )

    def test_other_manager_cannot_read_old_results(self):
        with self.assertRaises(HTTPException) as caught:
            operations.load_match(self.cursor, 1, "another-manager")
        self.assertEqual(caught.exception.status_code, 403)


# [추가 끝]


# 작업자 : 양태건
# 수정일 : 2026-10-26
# [추가 시작] 저장된 부상 JSON과 이전 텍스트를 손실 없이 조회합니다.
class InjuryStorageTest(unittest.TestCase):
    def test_plain_text_is_preserved_without_guessing_severity(self):
        player = dict(c_id_seq="test_01", r_seq=1, c_name="선수")
        rows = [dict(c_id_seq="test_01", c_r_r_injury="이전 부상 내용")]
        injuries = operations.injuries_from_rows(rows, [player])
        self.assertEqual(injuries[0]["description"], "이전 부상 내용")
        self.assertIsNone(injuries[0]["severity"])
        self.assertIsNone(injuries[0]["elapsed_seconds"])

    def test_duplicate_database_rows_do_not_duplicate_injuries(self):
        import json

        entry = dict(
            id="injury1", description="발목", body_parts=["발목·발"], severity="mild"
        )
        row = dict(c_id_seq="test_01", c_r_r_injury=json.dumps([entry]))
        self.assertEqual(len(operations.injuries_from_rows([row, row], [])), 1)

    def test_save_updates_only_the_selected_player_and_match(self):
        cursor = MagicMock()
        cursor.fetchall.return_value = []
        record = dict(match_code="match1", m_id="manager", g_code=1)
        player = dict(c_id_seq="test_01", r_seq=1, c_name="선수")
        operations.save_injury(
            cursor, record, player, dict(id="new1", description="부상 내용")
        )
        sql, params = cursor.execute.call_args.args
        self.assertIn("SET c_r_r_injury=%s", sql)
        self.assertEqual(params[1:], ("match1", "test_01"))


# [추가 끝]


class TransactionTest(unittest.TestCase):
    def test_failed_publish_rolls_back_whole_transaction(self):
        conn = MagicMock()
        record = dict(status="review", version=0)
        with patch.object(operations, "connect", return_value=conn), patch.object(
            operations, "load_match", return_value=(record, {})
        ), patch.object(
            operations, "mutate", side_effect=HTTPException(409, "저장 충돌")
        ):
            with self.assertRaises(HTTPException):
                operations.match_command(
                    1, Command(version=0, action="publish"), "test"
                )
        conn.rollback.assert_called_once()
        conn.commit.assert_not_called()
        conn.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
# [추가 끝]

# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
