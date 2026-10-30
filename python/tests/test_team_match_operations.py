# 수정 일 : 2026-10-30 / 작업자 : 양태건
# 실제 DB 쓰기 없이 예약 기반 명단·고정 팀·권한·트랜잭션 실패를 검증합니다.
import unittest
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from FastAPI.match import team_match_operations as target
from FastAPI.match import match_operations as ops


def match():
    now = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    return dict(team_start=now, team_end=now+timedelta(hours=2), rental_r_seq=1,
                rental_g_code=1, rental_g_name='구장', home_category='개설일', away_category='개설일', home_sport='1', away_sport='1',
                home_t_name='홈팀', away_t_name='원정팀')


def rows():
    return [dict(r_seq=i, c_id_seq=f'user{i}_01', c_name=f'선수{i}', c_position='FW',
                 c_rating=1500, c_prefer_stock='1', c_team='홈팀' if i == 1 else '원정팀')
            for i in (1, 2)]


class TeamOperationsTest(unittest.TestCase):
    def setUp(self):
        self.cursor = MagicMock()
        self.cursor.fetchone.side_effect = [match(), None]
        self.cursor.fetchall.side_effect = [rows(), [], []]

    def load(self):
        with patch.dict(ops._MATCHES, {}, clear=True):
            return target.load_team(self.cursor, 9, 'manager')

    def test_roster_is_only_matching_reservations_and_fixed_teams(self):
        record, state = self.load()
        self.assertEqual([p['r_seq'] for p in state['players']], [1, 2])
        self.assertEqual(state['fixed_sides'], {'1': 'A', '2': 'B'})
        self.assertEqual(state['attendance'], {})
        self.assertEqual(record['kind'], 'team')
        sql, params = self.cursor.execute.call_args_list[2].args
        for part in ('r.g_code=%s', 'r.r_date=DATE(%s)', 'r.rs_time=TIME(%s)',
                     'r.re_time=TIME(%s)', 'r.reservation_category=2', 'r.r_c_category',
                     'c.c_team IN', 'c.c_deletdate IS NULL'):
            self.assertIn(part, sql)
        self.assertEqual(params[0], 1)
        self.assertTrue(all(call.args[0].lstrip().startswith('SELECT')
                            for call in self.cursor.execute.call_args_list))

    def test_other_manager_cannot_get_roster(self):
        self.cursor.fetchone.side_effect = [None]
        with self.assertRaises(HTTPException) as caught:
            self.load()
        self.assertEqual(caught.exception.status_code, 404)
        self.assertIn('rm.m_id=%s', self.cursor.execute.call_args.args[0])
        self.assertEqual(self.cursor.execute.call_args.args[1], (9, 'manager'))

    def test_incomplete_and_one_sided_attendance_cannot_start(self):
        record, state = self.load()
        for attendance in ({'1': True}, {'1': True, '2': False}):
            state['attendance'] = attendance
            with self.assertRaises(HTTPException):
                target.mutate_team(self.cursor, record, state, ops.Command(version=0, action='start'))
            self.assertEqual(record['status'], 'attendance')

    def test_attendance_direct_start_events_and_publish(self):
        record, state = self.load()
        self.cursor.fetchall.side_effect = None
        self.cursor.fetchall.return_value = []
        for i in (1, 2):
            target.mutate_team(self.cursor, record, state,
                ops.Command(version=0, action='attendance', r_seq=i, attendance=True))
        target.mutate_team(self.cursor, record, state, ops.Command(version=0, action='start'))
        self.assertEqual(record['status'], 'live')
        self.assertEqual(state['assignments'], {'1': 'A', '2': 'B'})
        target.mutate_team(self.cursor, record, state, ops.Command(version=0, action='event', r_seq=1, kind='goal'))
        self.assertEqual(ops.totals(state)[1], {'A': 1, 'B': 0})
        target.mutate_team(self.cursor, record, state, ops.Command(version=0, action='end'))
        with patch.object(target, 'persist_team_match_result', return_value={'members': []}) as save:
            command = ops.Command(version=0, action='publish')
            target.mutate_team(self.cursor, record, state, command)
            target.mutate_team(self.cursor, record, state, command)
        save.assert_called_once()
        body = save.call_args.args[3]
        self.assertEqual(body.home_players[0].c_id_seq, 'user1_01')
        self.assertEqual(body.home_score, 1)
        self.assertEqual(record['status'], 'completed')

    def test_fixed_team_and_version_cannot_be_overridden(self):
        record, state = self.load()
        for action, version in [('teams', 0), ('back', 0), ('attendance', 99)]:
            with self.assertRaises(HTTPException):
                target.mutate_team(self.cursor, record, state, ops.Command(action=action, version=version))

    def test_empty_or_duplicate_reservations_do_not_create_full_team_roster(self):
        for raw, expected in [([], 0), ([rows()[0], rows()[0]], 1)]:
            cursor = MagicMock()
            cursor.fetchone.side_effect = [match(), None]
            cursor.fetchall.side_effect = [raw, [], []]
            with patch.dict(ops._MATCHES, {}, clear=True):
                _, state = target.load_team(cursor, 9, 'manager')
            self.assertEqual(len(state['players']), expected)

    def test_failure_rolls_back_and_does_not_cache_mutated_state(self):
        record, state = self.load()
        conn = MagicMock()
        with patch.object(target, 'connect', return_value=conn), \
             patch.object(target, 'load_team', return_value=(record, state)), \
             patch.object(target, 'mutate_team', side_effect=HTTPException(409, '거절')), \
             patch.object(ops, 'remember') as remember:
            with self.assertRaises(HTTPException):
                target.handle(9, 'manager', ops.Command(version=0, action='start'))
        conn.rollback.assert_called_once()
        conn.commit.assert_not_called()
        remember.assert_not_called()

    def test_shared_result_writer_updates_attendance_rows_without_losing_injuries(self):
        from FastAPI.match.match_result_insert import persist_team_match_result, TeamMatchResult, PlayerRecord
        cursor = MagicMock()
        info = dict(match(), rental_m_id='manager', home_t_id=1, away_t_id=2)
        cursor.fetchone.side_effect = [dict(m_id='manager'), dict(team_code=9), info, None]
        cursor.fetchall.side_effect = [
            [dict(t_id=1, c_prefer_stock='1'), dict(t_id=2, c_prefer_stock='1')],
            [dict(c_id_seq='user1_01')], [dict(c_id_seq='user2_01')],
            [dict(t_id=1, t_rating=1500), dict(t_id=2, t_rating=1500)],
            [dict(c_r_r_seq=1)], [dict(c_r_r_seq=2)],
            [dict(c_id_seq='user1_01', c_rating=1500), dict(c_id_seq='user2_01', c_rating=1500)],
        ]
        body = TeamMatchResult(home_score=1, away_score=0,
               home_players=[PlayerRecord(c_id_seq='user1_01', stats={'G': 1})],
               away_players=[PlayerRecord(c_id_seq='user2_01', stats={})])
        result = persist_team_match_result(cursor, 'manager', 9, body)
        sqls = [call.args[0] for call in cursor.execute.call_args_list]
        self.assertFalse(any('INSERT INTO c_result_record' in sql for sql in sqls))
        updates = [sql for sql in sqls if sql.startswith('UPDATE c_result_record SET m_id')]
        self.assertEqual(len(updates), 2)
        self.assertTrue(all('c_r_r_injury' not in sql for sql in updates))
        self.assertEqual(result['result'], 'OK')
        self.assertEqual(len(result['members']), 2)

    def test_authentication_required(self):
        app = FastAPI()
        app.include_router(target.router)
        response = TestClient(app).get('/match/team_operations/9')
        self.assertEqual(response.status_code, 401)


if __name__ == '__main__':
    unittest.main()
# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
