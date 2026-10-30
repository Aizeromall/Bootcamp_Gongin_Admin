# 수정 일 : 2026-10-27 / 작업자 : 양태건
# 등록된 교육과 미이수 필수 과정 수, 개설 시 배정 가능한 매니저를 조회합니다.
import logging
import pymysql
from fastapi import APIRouter, Depends, HTTPException
from database import connect
from .education_access import require_headquarters
from .education_store import load_courses

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/courses")
def list_courses(staff_id: str = Depends(require_headquarters)):
    conn = connect()
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            courses = load_courses(cursor)
        return dict(
            results=courses,
            total=len(courses),
            required_pending=sum(
                c.get("category") == "필수" and c["completed_count"] < c["total"]
                for c in courses
            ),
        )
    except Exception:
        logger.exception("교육 목록 조회 실패")
        raise HTTPException(500, "교육 목록을 불러오지 못했습니다.")
    finally:
        conn.close()


@router.get("/managers")
def education_managers(staff_id: str = Depends(require_headquarters)):
    conn = connect()
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute(
                "SELECT m_id,m_name,m_workplace FROM match_manager WHERE TRIM(m_department)=%s AND m_resignationdate IS NULL ORDER BY m_name,m_id",
                ("매니저",),
            )
            rows = cursor.fetchall()
        return {"results": rows}
    except Exception:
        logger.exception("교육 대상 조회 실패")
        raise HTTPException(500, "교육 대상 매니저를 불러오지 못했습니다.")
    finally:
        conn.close()


# 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
