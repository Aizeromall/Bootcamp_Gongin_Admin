# 수정 일 : 2026-10-30 / 작업자 : 양태건
# 실제 DB 쓰기 없이 팀 경기 취소의 코드 연결·권한·시작 제한·노쇼 기준을 검증합니다.
import unittest
from datetime import datetime
from unittest.mock import MagicMock, patch
from fastapi import HTTPException
from FastAPI.match import match_manage_cancel as target
from FastAPI.match import match_operations as ops


class TeamCancellationTest(unittest.TestCase):
    def setup_cursor(self, no_show=0, status='attendance'):
        conn = MagicMock()
        cur = conn.cursor.return_value.__enter__.return_value
        cur.rowcount = 12
        now = datetime.now().replace(hour=18, minute=0, second=0, microsecond=0)
        cur.fetchone.side_effect = [
            {'m_id': 'manager', 'm_name': '담당자'}, {'assign_seq': 1},
            {'g_code': 1, 'g_name': '구장', 'g_num': 12}, {'team_code': 9},
            {'rental_g_code': 1, 'team_start': now}, None,
            {'refund_count': 1, 'refund_amount': 10000},
        ]
        cur.fetchall.return_value = [
            {'r_seq': i, 'c_id_seq': f'u{i}', 'r_check': 1,
             'c_r_r_attendance': 0 if i < no_show else 1} for i in range(12)]
        body = target.MatchCancel(team_code=9, g_code='1', r_date=now.date(), rs_time='18:00', r_c_category=2)
        return conn, cur, body

    def test_weather_cancel_uses_numeric_team_record_code_and_clears_cache(self):
        conn, cursor, body = self.setup_cursor()
        with patch.object(target, 'connect', return_value=conn), \
             patch.object(target, 'require_manager', return_value='manager'), \
             patch.dict(ops._MATCHES, {'9': ({'status': 'attendance'}, {})}, clear=True):
            result = target.cancel_match('manager', body, 'Bearer mock')
            self.assertNotIn('9', ops._MATCHES)
        conn.commit.assert_called_once()
        self.assertEqual(result['result'], 'OK')
        query = next(c for c in cursor.execute.call_args_list if 'SELECT DISTINCT r.r_seq' in c.args[0])
        self.assertIn('cr.c_r_r_code = %s', query.args[0])
        self.assertIn('r.reservation_category=2', query.args[0])
        self.assertEqual(query.args[1][0], '9')

    def test_no_show_cancellation_uses_team_attendance_and_threshold(self):
        for missing, allowed in [(6, True), (0, False), (3, False)]:
            with self.subTest(missing=missing):
                conn, cursor, body = self.setup_cursor(no_show=missing)
                body.r_c_category = 3
                reservations = cursor.fetchall.return_value
                cursor.fetchall.side_effect = [reservations,
                    [{'c_id_seq': f'u{i}', 'c_rating': 1500} for i in range(missing)]]
                with patch.object(target, 'connect', return_value=conn), \
                     patch.object(target, 'require_manager', return_value='manager'), \
                     patch.dict(ops._MATCHES, {}, clear=True):
                    if allowed:
                        result = target.cancel_match('manager', body, 'Bearer mock')
                        self.assertEqual(result['noshow_count'], missing)
                        self.assertEqual([r['rating_change'] for r in result['rating_changes']], [-30] * missing)
                        conn.commit.assert_called_once()
                    else:
                        with self.assertRaises(HTTPException) as caught:
                            target.cancel_match('manager', body, 'Bearer mock')
                        self.assertEqual(caught.exception.status_code, 409)
                        conn.commit.assert_not_called()
                        conn.rollback.assert_called_once()

    def test_facility_and_weather_cancel_without_penalties_even_when_full(self):
        for reason in (1, 2):
            conn, cursor, body = self.setup_cursor(no_show=6)
            body.r_c_category = reason
            with patch.object(target, 'connect', return_value=conn), \
                 patch.object(target, 'require_manager', return_value='manager'), \
                 patch.dict(ops._MATCHES, {}, clear=True):
                result = target.cancel_match('manager', body, 'Bearer mock')
            self.assertEqual(result['rating_changes'], [])
            self.assertFalse(any('UPDATE customer' in call.args[0] for call in cursor.execute.call_args_list))
            conn.commit.assert_called_once()
        self.assertEqual(target.CANCEL_CATEGORY_NAMES['1'], '시설 문제')

    def test_penalty_failure_rolls_back_cancellation_and_refund(self):
        conn, cursor, body = self.setup_cursor(no_show=6)
        body.r_c_category = 3
        with patch.object(target, 'connect', return_value=conn), \
             patch.object(target, 'require_manager', return_value='manager'), \
             patch('FastAPI.match.match_result_insert.apply_absence_penalties', side_effect=HTTPException(409, '충돌')), \
             patch.dict(ops._MATCHES, {}, clear=True):
            with self.assertRaises(HTTPException):
                target.cancel_match('manager', body, 'Bearer mock')
        conn.rollback.assert_called_once()
        conn.commit.assert_not_called()
        self.assertFalse(any('DELETE FROM pay' in call.args[0] for call in cursor.execute.call_args_list))

    def test_pickup_no_show_cancellation_also_applies_penalty(self):
        conn, cursor, body = self.setup_cursor(no_show=6)
        body.team_code = None
        body.r_c_category = 3
        cursor.fetchone.side_effect = [
            {'m_id': 'manager', 'm_name': '담당자'}, {'assign_seq': 1},
            {'g_code': 1, 'g_name': '구장', 'g_num': 12},
            {'refund_count': 1, 'refund_amount': 10000},
        ]
        reservations = cursor.fetchall.return_value
        cursor.fetchall.side_effect = [reservations, [{'c_id_seq': 'u0', 'c_rating': 1500}]]
        with patch.object(target, 'connect', return_value=conn), \
             patch.dict(ops._MATCHES, {}, clear=True):
            result = target.cancel_match('manager', body)
        self.assertEqual(result['rating_changes'][0]['rating_change'], -30)
        query = next(call for call in cursor.execute.call_args_list
                     if 'FROM c_result_record cr INNER JOIN customer' in call.args[0])
        self.assertIn('r.reservation_category=1', query.args[0])
        self.assertTrue(query.args[1][0].endswith('_180000'))
        conn.commit.assert_called_once()

    def test_started_game_cannot_be_canceled(self):
        conn, _, body = self.setup_cursor()
        with patch.object(target, 'connect', return_value=conn), \
             patch.object(target, 'require_manager', return_value='manager'), \
             patch.dict(ops._MATCHES, {'9': ({'status': 'live'}, {})}, clear=True):
            with self.assertRaises(HTTPException) as caught:
                target.cancel_match('manager', body, 'Bearer mock')
        self.assertEqual(caught.exception.status_code, 409)
        conn.commit.assert_not_called()

    def test_other_login_cannot_cancel(self):
        _, _, body = self.setup_cursor()
        with patch.object(target, 'require_manager', return_value='another'), \
             patch.object(target, 'connect') as connect:
            with self.assertRaises(HTTPException) as caught:
                target.cancel_match('manager', body, 'Bearer mock')
        self.assertEqual(caught.exception.status_code, 403)
        connect.assert_not_called()


if __name__ == '__main__':
    unittest.main()
# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
