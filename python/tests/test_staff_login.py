# 작업자 : 양태건
# 수정일 : 2026-10-26
# [추가 시작] 부서 필터와 DB 없는 서명 토큰을 검증합니다.
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi import HTTPException
from FastAPI.login import manager_login
from FastAPI.match import manager_session


class StaffLoginTest(unittest.TestCase):
    def test_manager_login_checks_department_and_returns_name(self):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = ("test", "테스트", "매니저")
        with patch.object(manager_login, "connect", return_value=conn):
            data = manager_login.login_manager("test", "password")
        sql, params = cursor.execute.call_args.args
        self.assertIn("TRIM(m_department)", sql)
        self.assertEqual(params, ("test", "password", "매니저"))
        self.assertEqual(data["role"], "manager")
        self.assertEqual(data["m_department"], "매니저")
        self.assertEqual(
            manager_session.verify_manager_token(data["access_token"]), "test"
        )

    def test_non_manager_login_is_rejected(self):
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchone.return_value = None
        with patch.object(manager_login, "connect", return_value=conn):
            with self.assertRaises(HTTPException) as caught:
                manager_login.login_manager("headquarters", "password")
        self.assertEqual(caught.exception.status_code, 401)

    def test_token_can_be_verified_without_session_table(self):
        with patch.object(
            manager_session, "connect", side_effect=AssertionError("DB access")
        ):
            token = manager_session.issue_manager_session("test")
            self.assertEqual(manager_session.verify_manager_token(token), "test")

    def test_tampered_or_expired_token_is_rejected(self):
        token = manager_session.issue_manager_session("test")
        for bad in ("invalid", token + "tampered"):
            with self.assertRaises(HTTPException):
                manager_session.verify_manager_token(bad)
        with patch.object(manager_session.time, "time", return_value=10**12):
            with self.assertRaises(HTTPException):
                manager_session.verify_manager_token(token)

    def test_department_change_denies_existing_token(self):
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchone.return_value = None
        token = manager_session.issue_manager_session("test")
        with patch.object(manager_session, "connect", return_value=conn):
            with self.assertRaises(HTTPException) as caught:
                manager_session.require_manager("Bearer " + token)
        self.assertEqual(caught.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
# [추가 끝]
