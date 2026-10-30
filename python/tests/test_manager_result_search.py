# 수정 일 : 2026-10-29 / 작업자 : 양태건
# 실제 DB 연결 없이 결과 조회·담당자 범위·미보관 변동을 검증합니다.
import unittest
from datetime import datetime
from unittest.mock import MagicMock, patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from FastAPI.match import manager_result_search as target


def member(code='1_20261028_180000', name='A', cid='member_01', rating=1510):
    return dict(c_r_r_code=code, c_r_r_score='4:2', c_r_r_team=name,
                c_id_seq=cid, c_name='회원', c_position='FW', c_rating=rating,
                c_r_r_statcode='G:2,A:1', c_r_r_date=datetime(2026, 10, 28, 20),
                e_code='SOCCER', g_code=1, g_name='구장', m_name='담당자')


class ResultSearchTests(unittest.TestCase):
    def test_current_rating_does_not_become_historical_change(self):
        rows = target.group_results([member()], [], 'manager')
        self.assertEqual(rows[0]['date'], '2026-10-28')
        player = rows[0]['sides'][0]['members'][0]
        self.assertEqual(player['current_tier'], '비기너 1')
        self.assertEqual(player['stats']['G'], 2)
        self.assertIsNone(player['rating_change'])
        self.assertIsNone(player['rating_after'])

    # 수정 일 : 2026-10-30 / 작업자 : 양태건
    def test_first_match_only_uses_initial_rating_when_history_is_missing(self):
        for rating, count, expected in [(1524, 1, 24), (1480, 1, -20),
                                        (1500, 1, 0), (1524, 2, None),
                                        (None, 1, None)]:
            with self.subTest(rating=rating, count=count):
                row = member(rating=rating)
                row['completed_match_count'] = count
                self.assertEqual(target.member_document(row)['rating_change'], expected)
        row = member(rating=2000)
        row.update(completed_match_count=1, c_r_r_rating_before=1500, c_r_r_rating_after=1524)
        self.assertEqual(target.member_document(row)['rating_change'], 24)

    def test_first_team_match_fallback_and_later_match_guard(self):
        from FastAPI.match.team_match_search import team_rating_change
        record = dict(t_r_r_rating_after=None, prev_count=0, prev_rating_after=None,
                      completed_match_count=1, current_team_rating=1480)
        self.assertEqual(team_rating_change(record)['rating_change'], -20)
        record['completed_match_count'] = 2
        self.assertIsNone(team_rating_change(record)['rating_change'])
        record.update(t_r_r_rating_after=1524, current_team_rating=2000)
        self.assertEqual(team_rating_change(record)['rating_change'], 24)

    def test_registered_team_result_and_members_are_grouped(self):
        teams = [dict(t_r_r_m_code='9', t_r_r_seq=i, t_id=i, home_t_id=1,
                      t_name=f'T{i}', t_rating=1500, t_r_r_score=score,
                      t_r_r_statcode='G:4,A:2', e_code='SOCCER',
                      team_start=datetime(2026, 10, 27, 18), t_r_r_date=datetime(2026, 10, 27, 20))
                 for i, score in [(1, '4:2'), (2, '2:4')]]
        rows = target.group_results([member('9')], teams, 'manager')
        self.assertEqual(rows[0]['kind'], 'team')
        self.assertEqual(rows[0]['home_score'], 4)
        self.assertEqual(rows[0]['team_summary'][0]['result'], '승')
        self.assertIsNone(rows[0]['team_summary'][0]['rating_change'])

    # 수정 일 : 2026-10-30 / 작업자 : 양태건
    def test_published_absence_penalty_is_visible_without_affecting_score(self):
        absent = member(cid='absent')
        absent.update(c_r_r_score=None, c_r_r_attendance=0,
                      c_r_r_rating_before=1500, c_r_r_rating_after=1470)
        result = target.group_results([member(), absent], [], 'manager')[0]
        self.assertEqual(result['home_score'], 4)
        self.assertEqual(result['sides'][-1]['members'][0]['rating_change'], -30)
        self.assertEqual(target.group_results([absent], [], 'manager'), [])

    def test_attendance_without_score_is_not_a_result(self):
        row = member()
        row['c_r_r_score'] = None
        self.assertEqual(target.group_results([row], [], 'manager'), [])

    def test_missing_rating_and_invalid_score_are_not_zero(self):
        row = member(rating=None)
        row['c_r_r_score'] = 'old-format'
        result = target.group_results([row], [], 'manager')[0]
        self.assertIsNone(result['home_score'])
        self.assertIsNone(result['sides'][0]['members'][0]['current_tier'])

    def test_routes_are_authenticated_and_sql_is_select_only(self):
        app = FastAPI()
        app.include_router(target.router)
        client = TestClient(app)
        self.assertEqual(client.get('/match/manager/results?kind=pickup').status_code, 401)
        app.dependency_overrides[target.require_manager] = lambda: 'manager'
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchall.side_effect = [[member()], [], [member()], []]
        with patch.object(target, 'connect', return_value=conn):
            response = client.get('/match/manager/results?kind=pickup&e_code=SOCCER')
            self.assertEqual(response.status_code, 200)
            self.assertNotIn('sides', response.json()['results'][0])
            response = client.get('/match/manager/results/1_20261028_180000')
            self.assertEqual(response.status_code, 200)
        for call in cursor.execute.call_args_list:
            sql, params = call.args
            self.assertTrue(sql.strip().startswith('SELECT'))
            self.assertIn('rr.m_id=%s', sql)
            self.assertEqual(params[0], 'manager')
        conn.commit.assert_not_called()

    def test_detail_cannot_read_another_managers_result(self):
        app = FastAPI()
        app.include_router(target.router)
        app.dependency_overrides[target.require_manager] = lambda: 'manager'
        with patch.object(target, 'read_results', return_value=[]) as reader:
            response = TestClient(app).get('/match/manager/results/9')
        reader.assert_called_once_with('manager', '9')
        self.assertEqual(response.status_code, 404)

    def test_upcoming_excludes_past_completed_and_canceled_reservations(self):
        today = datetime.now(target.ZoneInfo("Asia/Seoul")).date().isoformat()
        operations = {"results": [
            dict(r_seq=1, status="attendance", r_date=today),
            dict(r_seq=2, status="teams", r_date=today),
            dict(r_seq=3, status="completed", r_date=today),
            dict(r_seq=4, status="attendance", r_date="2000-01-01"),
        ]}
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchall.side_effect = [[{"r_seq": 1}], []]
        with patch.object(target, "match_list", return_value=operations), patch.object(target, "connect", return_value=conn):
            response = target.upcoming("manager")
        self.assertEqual([r["r_seq"] for r in response["operations"]], [1])
        self.assertIn("r.reservation_category=1", cursor.execute.call_args_list[0].args[0])
        self.assertEqual(cursor.execute.call_args_list[1].args[1][0], "manager")
        conn.commit.assert_not_called()

    # 수정 일 : 2026-10-30 / 작업자 : 양태건
    def test_saved_rating_change_is_returned_in_detail_response(self):
        for before, after, expected in [(1500, 1524, 24), (1500, 1480, -20),
                                        (1700, 1700, 0), (None, 1524, None),
                                        (1500, None, None), (None, None, None)]:
            with self.subTest(before=before, after=after):
                row = member(rating=2000)
                row.update(c_r_r_rating_before=before, c_r_r_rating_after=after)
                grouped = target.group_results([row], [], 'manager')
                app = FastAPI()
                app.include_router(target.router)
                app.dependency_overrides[target.require_manager] = lambda: 'manager'
                with patch.object(target, 'read_results', return_value=grouped):
                    response = TestClient(app).get('/match/manager/results/1_20261028_180000')
                self.assertEqual(response.status_code, 200)
                player = response.json()['sides'][0]['members'][0]
                self.assertEqual(player['rating_before'], before)
                self.assertEqual(player['rating_after'], after)
                self.assertEqual(player['rating_change'], expected)
                self.assertEqual(player['current_rating'], 2000)


if __name__ == '__main__':
    unittest.main()
# 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
