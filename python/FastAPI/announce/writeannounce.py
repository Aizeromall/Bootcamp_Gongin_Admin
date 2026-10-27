# 작업자 : 최현준
# 작업 일 : 2026-10-27
"""본사 직원 ID로 공지를 작성합니다. 분류는 단일 선택, 대상은 복수 선택입니다."""
from datetime import datetime
from zoneinfo import ZoneInfo

import pymysql
from fastapi import APIRouter, Body, HTTPException
from .announce_common import Classification, Target, TARGETS, connect, database_error

router = APIRouter(prefix="/announce", tags=["공지 작성"])


@router.post("/write", status_code=201)
def write_announcement(
    h_id: str = Body(..., min_length=1, max_length=50),
    a_classify: Classification = Body(...),
    a_title: str = Body(..., min_length=1, max_length=200),
    a_detail: str = Body(..., min_length=1, max_length=16000),
    a_target: list[Target] = Body(..., min_length=1, max_length=3),
):
    # 문자열 공백만 입력한 요청은 거부하고, 중복 대상은 한 번만 저장합니다.
    h_id, a_title, a_detail = h_id.strip(), a_title.strip(), a_detail.strip()
    if not all((h_id, a_title, a_detail)):
        raise HTTPException(400, detail={"code": "ANNOUNCE_INVALID_INPUT", "message": "작성자, 제목, 내용을 입력해 주세요."})
    targets = [target for target in TARGETS if target in a_target]
    # 클라이언트가 작성일을 정하지 않도록 서버의 한국 시간을 사용합니다.
    created_at = datetime.now(ZoneInfo("Asia/Seoul")).replace(tzinfo=None, microsecond=0)
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            # FK 오류에 앞서 직원 존재 여부를 확인합니다. h_id 자체는 인증 토큰이 아닙니다.
            cursor.execute("SELECT h_name FROM headquarter WHERE h_id = %s", (h_id,))
            staff = cursor.fetchone()
            if staff is None:
                raise HTTPException(404, detail={"code": "ANNOUNCE_STAFF_NOT_FOUND", "message": "작성 직원을 찾을 수 없습니다."})
            cursor.execute(
                "INSERT INTO announcement (h_id, a_classify, a_title, a_detail, a_date, a_target) "
                "VALUES (%s, %s, %s, %s, %s, %s)",
                (h_id, a_classify, a_title, a_detail, created_at, ",".join(targets)),
            )
            sequence = cursor.lastrowid
        connection.commit()
        return {"result": "OK", "a_seq": sequence, "h_id": h_id, "h_name": staff["h_name"],
                "a_classify": a_classify, "a_title": a_title, "a_detail": a_detail,
                "a_date": created_at, "a_target": targets}
    except pymysql.MySQLError as error:
        if connection is not None:
            connection.rollback()
        raise database_error(error) from error
    except Exception:
        if connection is not None:
            connection.rollback()
        raise
    finally:
        if connection is not None:
            connection.close()

# 최종 수정일 : 2026-10-27
