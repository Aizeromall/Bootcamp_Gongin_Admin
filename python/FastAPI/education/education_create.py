# 수정 일 : 2026-10-27 / 작업자 : 양태건
# 요청 클래스와 교육 개설 라우터를 함께 두고 대상별 training 행을 원자적으로 저장합니다.
import json
import logging
import uuid
from datetime import datetime
from typing import Literal
from zoneinfo import ZoneInfo
import pymysql
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from database import connect
from .education_access import require_headquarters

router = APIRouter()
logger = logging.getLogger(__name__)


class CreateEducationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str = Field(min_length=1, max_length=200)
    category: Literal["필수", "정기", "재교육"]
    format: Literal["온라인", "오프라인"]
    scheduled_at: datetime
    duration_minutes: int = Field(ge=15, le=1440)
    location: str = Field(min_length=1, max_length=200)
    instructor: str = Field(default="", max_length=100)
    description: str = Field(default="", max_length=8000)
    manager_ids: list[str] = Field(min_length=1, max_length=200)

    @field_validator("title", "location", "instructor", "description", mode="before")
    @classmethod
    def strip_fields(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator("manager_ids")
    @classmethod
    def valid_managers(cls, value):
        if any(not x.strip() or len(x) > 50 for x in value) or len(set(value)) != len(
            value
        ):
            raise ValueError("대상 매니저 ID를 확인해 주세요.")
        return value


@router.post("/courses", status_code=201)
def create_course(
    payload: CreateEducationRequest, staff_id: str = Depends(require_headquarters)
):
    local_date = payload.scheduled_at
    if local_date.tzinfo is not None:
        local_date = local_date.astimezone(ZoneInfo("Asia/Seoul")).replace(tzinfo=None)
    metadata = payload.model_dump(exclude={"manager_ids", "scheduled_at"})
    metadata.update(
        _education=1,
        course_id="edu_" + uuid.uuid4().hex,
        scheduled_at=local_date.isoformat(timespec="minutes"),
    )
    detail = json.dumps(metadata, ensure_ascii=False, separators=(",", ":"))
    if len(detail.encode("utf-8")) > 65535:
        raise HTTPException(422, "교육 내용이 저장 가능한 길이를 초과했습니다.")
    conn = connect()
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            placeholders = ",".join(["%s"] * len(payload.manager_ids))
            cursor.execute(
                f"SELECT m_id FROM match_manager WHERE m_id IN ({placeholders}) AND TRIM(m_department)=%s AND m_resignationdate IS NULL FOR UPDATE",
                (*payload.manager_ids, "매니저"),
            )
            if {r["m_id"] for r in cursor.fetchall()} != set(payload.manager_ids):
                raise HTTPException(
                    422,
                    "선택한 대상 중 배정할 수 없는 매니저가 있습니다. 대상 목록을 다시 확인해 주세요.",
                )
            for manager_id in payload.manager_ids:
                cursor.execute(
                    "INSERT INTO training (h_id,m_id,t_detail,t_state,t_date) VALUES (%s,%s,%s,%s,%s)",
                    (staff_id, manager_id, detail, False, local_date.date()),
                )
        conn.commit()
        return dict(result="OK", course_id=metadata["course_id"])
    except HTTPException:
        conn.rollback()
        raise
    except Exception:
        conn.rollback()
        logger.exception("교육 개설 실패")
        raise HTTPException(500, "교육을 개설하지 못했습니다.")
    finally:
        conn.close()


# 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
