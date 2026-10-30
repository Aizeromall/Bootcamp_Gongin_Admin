# 수정 일 : 2026-10-30 / 작업자 : 양태건
# 실제 DB 쓰기 없이 VARCHAR 예약 구분·성사 플래그로 일정 조회 응답을 검증합니다.
import unittest
from datetime import date, datetime
from unittest.mock import MagicMock, patch
from FastAPI.match import match_schedule as target


class ScheduleContractTest(unittest.TestCase):
    def schedule(self, category, confirmed):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = {'m_id': 'manager', 'm_name': '담당자'}
        cursor.fetchall.side_effect = [
            [{'g_code': 1, 'g_name': '구장', 'g_num': 12}],
            [{'assign_seq': 1, 'g_code': 1, 'm_id': 'manager', 'a_time': '08:00~22:00'}],
            [{'r_seq': i, 'g_code': 1, 'rs_time': '18:00:00', 'c_id_seq': f'user{i}',
              'c_name': '예약자', 'r_check': confirmed, 'reservation_category': category}
             for i in range(1, 13)],
            [{'team_code': 9, 'home_t_id': 1, 'home_t_name': '홈팀', 'away_t_id': 2,
              'away_t_name': '원정팀', 'team_start': datetime(2026, 10, 30, 18)}],
            [{'t_id': 1, 'captain_id': 'user1'}],
        ]
        with patch.object(target, 'connect', return_value=conn):
            result = target.select_manager_schedule('manager', date(2026, 10, 30), None)
        return next(slot for slot in result['grounds'][0]['slots'] if slot['rs_time'] == '18:00')

    def test_string_and_integer_rental_categories_return_team_match(self):
        for category in ('2', 2):
            with self.subTest(category=category):
                slot = self.schedule(category, '1')
                self.assertEqual(slot['slot_type'], 'team_match')
                self.assertEqual(slot['team_match']['team_code'], 9)
                self.assertIsNone(slot['pickup'])

    def test_string_zero_is_not_a_matched_rental(self):
        slot = self.schedule('2', '0')
        self.assertIsNone(slot['team_match'])
        self.assertFalse(slot['rental']['is_matched'])

    def test_string_pickup_zero_is_not_full(self):
        slot = self.schedule('1', '0')
        self.assertEqual(slot['slot_type'], 'pickup')
        self.assertFalse(slot['pickup']['is_full'])
        self.assertEqual(slot['pickup']['reservation_count'], 12)


if __name__ == '__main__':
    unittest.main()
# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
