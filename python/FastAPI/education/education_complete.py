# 수정 일 : 2026-10-27 / 작업자 : 양태건
# 확인된 출석부·퀴즈 결과에 따라 본사 직원이 이수 처리를 확정합니다.
import logging
from typing import Literal
import pymysql
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict
from database import connect
from .education_access import require_headquarters

router = APIRouter()
logger = logging.getLogger(__name__)


class CompleteEducationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    completed: Literal[True]


@router.post("/completion/{training_seq}")
def complete_education(
    training_seq: int,
    payload: CompleteEducationRequest,
    staff_id: str = Depends(require_headquarters),
):
    conn = connect()
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute(
                "SELECT training_seq,t_state FROM training WHERE training_seq=%s FOR UPDATE",
                (training_seq,),
            )
            row = cursor.fetchone()
            if row is None:
                raise HTTPException(404, "교육 대상 기록을 찾을 수 없습니다.")
            if row["t_state"] != 1:
                cursor.execute(
                    "UPDATE training SET t_state=1 WHERE training_seq=%s",
                    (training_seq,),
                )
        conn.commit()
        return dict(result="OK", training_seq=training_seq, completed=True)
    except HTTPException:
        conn.rollback()
        raise
    except Exception:
        conn.rollback()
        logger.exception("교육 이수 처리 실패")
        raise HTTPException(500, "이수 처리를 완료하지 못했습니다.")
    finally:
        conn.close()


# 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
