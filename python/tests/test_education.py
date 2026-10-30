# 수정 일 : 2026-10-27 / 작업자 : 양태건
# 실제 DB 연결·쓰기 없이 교육 저장 계약과 본사 인증을 검증합니다.
import json
import sys
import unittest
from datetime import date
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi import HTTPException
from pydantic import ValidationError
from FastAPI.education.education_store import group_courses
from FastAPI.education import (
    education_create as create,
    education_complete as complete,
    education_access as access,
)
from FastAPI.match.manager_session import (
    issue_manager_session,
    issue_headquarters_session,
    verify_headquarters_token,
)


def payload(**overrides):
    values = dict(
        title="안전 · 응급처치",
        category="필수",
        format="오프라인",
        scheduled_at="2026-11-05T14:00:00+09:00",
        duration_minutes=180,
        location="본사 교육장",
        manager_ids=["manager1", "manager2"],
    )
    values.update(overrides)
    return create.CreateEducationRequest(**values)


class EducationTest(unittest.TestCase):
    def test_rows_of_same_course_are_grouped_without_new_table(self):
        info = json.dumps(
            dict(
                _education=1,
                course_id="edu_test",
                title="응급처치",
                category="필수",
                format="오프라인",
                scheduled_at="2026-11-05T14:00",
            )
        )
        rows = [
            dict(
                training_seq=i,
                h_id="hq",
                m_id=f"m{i}",
                m_name=f"매니저{i}",
                m_workplace="구장",
                t_detail=info,
                t_state=i - 1,
                t_date=date(2026, 11, 5),
            )
            for i in (1, 2)
        ]
        courses = group_courses(rows)
        self.assertEqual(len(courses), 1)
        self.assertEqual(courses[0]["total"], 2)
        self.assertEqual(courses[0]["completed_count"], 1)

    def test_existing_plain_training_text_is_preserved(self):
        result = group_courses(
            [
                dict(
                    training_seq=1,
                    m_id="m1",
                    t_detail="기존 교육 설명",
                    t_state=None,
                    t_date=None,
                )
            ]
        )
        self.assertEqual(result[0]["description"], "기존 교육 설명")
        self.assertIsNone(result[0]["category"])
        self.assertIsNone(result[0]["managers"][0]["completed"])

    def test_create_writes_only_training_and_commits_all_assignments(self):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchall.return_value = [{"m_id": "manager1"}, {"m_id": "manager2"}]
        with patch.object(create, "connect", return_value=conn):
            result = create.create_course(payload(), "hq")
        writes = [
            c.args
            for c in cursor.execute.call_args_list
            if c.args[0].startswith("INSERT")
        ]
        self.assertEqual(len(writes), 2)
        self.assertTrue(all("INSERT INTO training" in w[0] for w in writes))
        self.assertEqual(writes[0][1][0], "hq")
        self.assertEqual(writes[0][1][4], date(2026, 11, 5))
        saved = json.loads(writes[0][1][2])
        self.assertEqual(saved["course_id"], result["course_id"])
        self.assertEqual(saved["title"], "안전 · 응급처치")
        conn.commit.assert_called_once()
        conn.close.assert_called_once()

    def test_invalid_manager_blocks_all_inserts(self):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchall.return_value = [{"m_id": "manager1"}]
        with patch.object(create, "connect", return_value=conn):
            with self.assertRaises(HTTPException) as caught:
                create.create_course(payload(), "hq")
        self.assertEqual(caught.exception.status_code, 422)
        conn.rollback.assert_called_once()
        conn.commit.assert_not_called()
        self.assertFalse(
            any("INSERT" in c.args[0] for c in cursor.execute.call_args_list)
        )

    def test_partial_write_error_rolls_back(self):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchall.return_value = [{"m_id": "manager1"}, {"m_id": "manager2"}]
        cursor.execute.side_effect = [None, None, RuntimeError("mock failure")]
        with patch.object(create, "connect", return_value=conn), patch.object(
            create.logger, "exception"
        ):
            with self.assertRaises(HTTPException):
                create.create_course(payload(), "hq")
        conn.rollback.assert_called_once()
        conn.commit.assert_not_called()

    def test_empty_title_or_duplicate_managers_rejected(self):
        for values in [
            dict(title="  "),
            dict(manager_ids=["manager1", "manager1"]),
            dict(duration_minutes=0),
        ]:
            with self.assertRaises(ValidationError):
                payload(**values)

    def test_completion_is_idempotent(self):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = {"training_seq": 1, "t_state": 1}
        with patch.object(complete, "connect", return_value=conn):
            result = complete.complete_education(
                1, complete.CompleteEducationRequest(completed=True), "hq"
            )
        self.assertTrue(result["completed"])
        self.assertFalse(
            any(c.args[0].startswith("UPDATE") for c in cursor.execute.call_args_list)
        )
        conn.commit.assert_called_once()

    def test_completion_updates_only_selected_training(self):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = {"training_seq": 2, "t_state": 0}
        with patch.object(complete, "connect", return_value=conn):
            complete.complete_education(
                2, complete.CompleteEducationRequest(completed=True), "hq"
            )
        self.assertEqual(
            cursor.execute.call_args.args,
            ("UPDATE training SET t_state=1 WHERE training_seq=%s", (2,)),
        )

    def test_manager_token_cannot_access_headquarters_education(self):
        with patch.object(
            access, "connect", side_effect=AssertionError("Unexpected DB")
        ):
            with self.assertRaises(HTTPException) as caught:
                access.require_headquarters("Bearer " + issue_manager_session("m"))
        self.assertEqual(caught.exception.status_code, 401)
        self.assertEqual(
            verify_headquarters_token(issue_headquarters_session("hq")), "hq"
        )

    def test_resigned_headquarters_account_is_denied(self):
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchone.return_value = None
        with patch.object(access, "connect", return_value=conn):
            with self.assertRaises(HTTPException) as caught:
                access.require_headquarters(
                    "Bearer " + issue_headquarters_session("hq")
                )
        self.assertEqual(caught.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
# 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
