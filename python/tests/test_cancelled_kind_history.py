# 수정 일 : 2026-10-30 / 작업자 : 양태건
# 실제 DB 쓰기 없이 예약 유형별 취소 집계·종목·예약 회원·인증을 검증합니다.
import unittest
from datetime import date, datetime
from unittest.mock import MagicMock, patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from FastAPI.match import match_manage_cancel as target


def row(seq, ground=1, sport='1'):
    return dict(r_seq=seq, g_code=ground, g_name=f'구장{ground}', g_num=12,
                r_date=date(2026, 10, 30), rs_time='18:00:00', re_time='20:00:00',
                r_c_category='2', r_cancel_date=datetime(2026, 10, 30, 17),
                c_name=f'회원{seq}', c_team='소속팀', c_prefer_stock=sport)


class CancelledKindHistoryTest(unittest.TestCase):
    def test_category_filter_and_grouping_uses_same_slot_reservations(self):
        for kind, category in [('pickup', '1'), ('team', '2')]:
            with self.subTest(kind=kind):
                cursor = MagicMock()
                cursor.fetchall.return_value = [row(1), row(2), row(2), row(3, ground=2)]
                result = target.canceled_by_kind(cursor, 'manager', kind)
                self.assertEqual([r['canceled_count'] for r in result], [2, 1])
                self.assertEqual(result[0]['members'][0]['current_team'], '소속팀')
                self.assertEqual(result[0]['e_code'], 'SOCCER')
                sql, params = cursor.execute.call_args.args
                self.assertEqual(params, [2, category, 'manager'])
                self.assertIn('r.r_c_category IN', sql)
                self.assertIn('r.reservation_category=%s', sql)
                self.assertIn('a.m_id=%s', sql)
                self.assertTrue(sql.lstrip().startswith('SELECT'))

    def test_sport_filter_does_not_show_partial_count_of_mixed_slot(self):
        cursor = MagicMock()
        cursor.fetchall.return_value = [row(1), row(2, sport='2'), row(3, ground=2, sport='2')]
        result = target.canceled_by_kind(cursor, 'manager', 'team', 'BASKETBALL')
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['g_code'], 2)
        self.assertEqual(result[0]['canceled_count'], 1)

    def test_penalty_uses_stored_snapshot_and_excludes_present_or_missing_history(self):
        cursor = MagicMock()
        base = dict(row(1), r_c_category='3', attendance=0, rating_before=1500, rating_after=1470)
        cursor.fetchall.return_value = [base,
            dict(base, r_seq=2, attendance=1),
            dict(base, r_seq=3, rating_before=None, rating_after=None),
            dict(base, r_seq=4, rating_before=1010, rating_after=1000),
            dict(base, r_seq=5, rating_before=1000, rating_after=1000)]
        result = target.canceled_by_kind(cursor, 'manager', 'team')
        members = result[0]['members']
        self.assertEqual([m['rating_change'] for m in members], [-30, None, None, -10, 0])
        self.assertEqual([m['penalty_applied'] for m in members], [True, False, False, True, False])
        sql = cursor.execute.call_args.args[0]
        self.assertIn('history.c_r_r_date<=r.r_cancel_date', sql)
        self.assertIn('MAX(history.c_r_r_seq)', sql)
        self.assertIn('history.g_code=r.g_code', sql)
        self.assertIn('CAST(tm.team_code AS CHAR CHARACTER SET utf8mb4)', sql)
        cursor.fetchall.return_value = [dict(base, r_c_category='1')]
        self.assertIsNone(target.canceled_by_kind(cursor, 'manager', 'pickup')[0]['members'][0]['rating_change'])

    def test_authenticated_route_returns_filtered_rows_and_validates_kind(self):
        app = FastAPI()
        app.include_router(target.router)
        client = TestClient(app)
        self.assertEqual(client.get('/match/manage/cancel/manager?kind=team').status_code, 401)
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = {'m_id': 'manager', 'm_name': '담당자'}
        cursor.fetchall.return_value = [row(1)]
        with patch.object(target, 'connect', return_value=conn), \
             patch.object(target, 'require_manager', return_value='manager'):
            result = client.get('/match/manage/cancel/manager?kind=pickup&e_code=SOCCER')
            self.assertEqual(result.status_code, 200)
            self.assertEqual(result.json()['results'][0]['kind'], 'pickup')
            self.assertEqual(result.json()['results'][0]['members'][0]['r_seq'], 1)
            self.assertEqual(client.get('/match/manage/cancel/manager?kind=wrong').status_code, 422)
        conn.commit.assert_not_called()
        with patch.object(target, 'require_manager', return_value='another'), \
             patch.object(target, 'connect') as connect:
            self.assertEqual(client.get('/match/manage/cancel/manager?kind=team').status_code, 403)
            connect.assert_not_called()


if __name__ == '__main__':
    unittest.main()
# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
