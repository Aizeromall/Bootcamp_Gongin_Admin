# 수정 일 : 2026-10-30 / 작업자 : 양태건
# 메모리 SQLite와 Mock만 사용하며 실제 MySQL에는 연결하지 않습니다.
import asyncio
import sqlite3
import unittest
from unittest.mock import MagicMock, patch
from FastAPI.management import management as target


class ManagerMatchCountTest(unittest.TestCase):
    def test_counts_unique_completed_games_across_member_and_team_records(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.create_collation('utf8mb4_unicode_ci', lambda a, b: (a > b) - (a < b))
        db.executescript('''
            CREATE TABLE c_result_record (m_id TEXT, c_r_r_code TEXT, c_r_r_score TEXT);
            CREATE TABLE t_result_record (m_id TEXT, t_r_r_m_code TEXT, t_r_r_score TEXT);
        ''')
        db.executemany('INSERT INTO c_result_record VALUES (?,?,?)', [
            ('many', 'pickup1', '1:0'), ('many', 'pickup1', '0:1'),
            ('many', 'team1', '2:1'), ('many', 'pending', None),
            ('many', 'cancel-penalty', None), ('many', '', '0:0'),
            ('few', 'pickup2', '0:0'), ('few', 'empty', ''),
        ])
        db.executemany('INSERT INTO t_result_record VALUES (?,?,?)', [
            ('many', 'team1', '2:1'), ('many', 'team1', '1:2'),
            ('many', 'team2', '0:0'), ('many', 'pending2', None),
        ])
        self.assertEqual(dict(db.execute(target._MANAGER_MATCH_COUNTS).fetchall()), {'few': 1, 'many': 3})

    def test_list_exposes_zero_for_missing_history_and_sorts_before_return(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchall.return_value = [{'m_id': 'many', 'match_count': 3}, {'m_id': 'none', 'match_count': 0}]
        with patch.object(target, 'connect', return_value=connection):
            result = asyncio.run(target.list_managers('search'))
        sql, params = cursor.execute.call_args.args
        self.assertIn('COALESCE(games.match_count, 0) AS match_count', sql)
        self.assertIn('ORDER BY match_count DESC, m.m_id', sql)
        self.assertEqual(params, ['%search%'] * 3)
        self.assertEqual(result['results'][1]['match_count'], 0)
        connection.close.assert_called_once()


if __name__ == '__main__':
    unittest.main()
# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
