# 작업자 : 신현진
# 수정일 : 2026-10-29
# DB 변경 없이(MagicMock 커서) 경기별 회원 점수 기록 저장 규칙을 검사합니다.
#   출석 회원 : 반영 전 / 후 점수 저장
#   결석 회원 : 점수 미반영 → 전 = 후 = 그 회원의 현재 c_rating (DB 기본값 1500을 쓰지 않음)
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from FastAPI.match.match_result_insert import RATING_START, apply_member_ratings


class MemberRatingRecordTest(unittest.TestCase):
    def setUp(self):
        self.cursor = MagicMock()
        # 출석 회원 현재 점수 (A팀 1명, B팀 1명)
        self.cursor.fetchall.return_value = [
            dict(c_id_seq="a_01", c_rating=1700),
            dict(c_id_seq="b_01", c_rating=1500),
        ]
        self.team_a = [dict(c_id_seq="a_01", stats={})]
        self.team_b = [dict(c_id_seq="b_01", stats={})]

    # 실행한 SQL 중 결석 회원 점수를 채우는 UPDATE
    def absent_fill_calls(self):
        return [call for call in self.cursor.execute.call_args_list
                if "INNER JOIN customer" in call.args[0] and "IS NULL" in call.args[0]]

    def test_absent_members_get_current_rating_as_before_and_after(self):
        changes = apply_member_ratings(self.cursor, "SOCCER", self.team_a, self.team_b, 2, 1,
                                       match_code="1_20261029_200000")
        self.assertEqual(len(changes), 2)
        fills = self.absent_fill_calls()
        self.assertEqual(len(fills), 1)
        sql, params = fills[0].args
        # 결석 회원 = 같은 경기코드에서 전 / 후 점수가 아직 비어 있는 줄 → 현재 c_rating(없으면 1500)으로 채움
        self.assertIn("SET r.c_r_r_rating_before = COALESCE(c.c_rating, %s)", sql)
        self.assertIn("r.c_r_r_rating_after = COALESCE(c.c_rating, %s)", sql)
        self.assertEqual(params, (RATING_START, RATING_START, "1_20261029_200000"))
        # 출석 회원 점수를 모두 저장한 뒤 마지막에 결석 회원을 채움
        self.assertIs(self.cursor.execute.call_args_list[-1], fills[0])

    def test_attended_members_save_before_and_after(self):
        apply_member_ratings(self.cursor, "SOCCER", self.team_a, self.team_b, 2, 1, match_code="m1")
        saved = [call.args[1] for call in self.cursor.execute.call_args_list
                 if call.args[0].strip().startswith("UPDATE c_result_record SET c_r_r_rating_before")]
        self.assertEqual([(p[0], p[2], p[3]) for p in saved], [(1700, "m1", "a_01"), (1500, "m1", "b_01")])

    def test_without_match_code_no_record_update(self):
        apply_member_ratings(self.cursor, "SOCCER", self.team_a, self.team_b, 1, 1)
        self.assertEqual(self.absent_fill_calls(), [])
        self.assertFalse(any("c_result_record" in call.args[0] for call in self.cursor.execute.call_args_list))


if __name__ == "__main__":
    unittest.main()
