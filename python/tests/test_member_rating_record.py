# 작업자 : 신현진
# 수정일 : 2026-10-29
# DB 변경 없이(MagicMock 커서) 경기별 회원 점수 기록 저장 규칙을 검사합니다.
#   출석 회원 : 반영 전 / 후 점수 저장
#   결석 회원 : 유효 실력매칭 예약에 최종 등록 시 최대 -30점, 하한 1000점 적용 (2026-10-30 양태건)
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

    # 수정 일 : 2026-10-30 / 작업자 : 양태건
    def test_absent_penalty_saves_before_after_and_excludes_canceled(self):
        self.cursor.fetchall.side_effect = [
            [dict(c_id_seq="a_01", c_rating=1700), dict(c_id_seq="b_01", c_rating=1500)],
            [dict(c_id_seq="absent_01", c_rating=1500), dict(c_id_seq="absent_01", c_rating=1500)],
        ]
        changes = apply_member_ratings(self.cursor, "SOCCER", self.team_a, self.team_b, 2, 1,
                                       match_code="1_20261029_200000")
        self.assertEqual(changes[-1]['rating_change'], -30)
        self.assertEqual(changes[-1]['rating_after'], 1470)
        updates = [call.args[1] for call in self.cursor.execute.call_args_list
                   if call.args[0].startswith("UPDATE customer SET c_rating=%s")]
        self.assertEqual(updates, [(1470, "absent_01")])
        query = next(call.args[0] for call in self.cursor.execute.call_args_list
                     if 'FROM c_result_record cr INNER JOIN customer' in call.args[0])
        self.assertIn('cr.c_r_r_attendance=0', query)
        self.assertIn('cr.c_r_r_rating_before IS NULL', query)
        self.assertIn('r.reservation_category=1', query)
        self.assertIn('r.r_c_category', query)
        self.assertIn('FOR UPDATE', query)

    def test_floor_and_repeat_exclusion(self):
        from FastAPI.match.match_result_insert import apply_absence_penalties
        self.cursor.fetchall.side_effect = [[dict(c_id_seq="absent", c_rating=1010)], []]
        first = apply_absence_penalties(self.cursor, '1_20261029_200000')
        self.assertEqual(first[0]['rating_after'], 1000)
        self.assertEqual(first[0]['rating_change'], -10)
        self.assertEqual(apply_absence_penalties(self.cursor, '1_20261029_200000'), [])
        self.assertEqual(apply_absence_penalties(self.cursor, '9'), [])

    def test_cancellation_penalty_is_limited_to_locked_reservations_and_unprocessed_absences(self):
        from FastAPI.match.match_result_insert import apply_absence_penalties
        for code, category in [('1_20261030_180000', 1), ('9', 2)]:
            with self.subTest(code=code):
                cursor = MagicMock()
                cursor.fetchall.side_effect = [[{'c_id_seq': 'absent', 'c_rating': 1500}], []]
                first = apply_absence_penalties(cursor, code, reservation_ids=[10, 11])
                self.assertEqual(first[0]['rating_change'], -30)
                sql, params = cursor.execute.call_args_list[0].args
                self.assertIn('cr.c_r_r_attendance=0', sql)
                self.assertIn('cr.c_r_r_rating_before IS NULL', sql)
                self.assertIn(f'r.reservation_category={category}', sql)
                self.assertIn('r.r_seq IN (%s,%s)', sql)
                self.assertEqual(params, (code, 10, 11))
                self.assertEqual(apply_absence_penalties(cursor, code, reservation_ids=[10, 11]), [])

    def test_attended_members_save_before_and_after(self):
        apply_member_ratings(self.cursor, "SOCCER", self.team_a, self.team_b, 2, 1, match_code="m1")
        saved = [call.args[1] for call in self.cursor.execute.call_args_list
                 if call.args[0].strip().startswith("UPDATE c_result_record SET c_r_r_rating_before")]
        self.assertEqual([(p[0], p[2], p[3]) for p in saved], [(1700, "m1", "a_01"), (1500, "m1", "b_01")])

    def test_without_match_code_no_record_update(self):
        apply_member_ratings(self.cursor, "SOCCER", self.team_a, self.team_b, 1, 1)

        self.assertFalse(any("c_result_record" in call.args[0] for call in self.cursor.execute.call_args_list))


if __name__ == "__main__":
    unittest.main()

# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
