# 수정 일 : 2026-10-27 / 작업자 : 양태건
# 확인된 출석부·퀴즈 결과에 따라 본사 직원이 이수 처리를 확정합니다.
import logging
from typing import Annotated, Literal
import pymysql
from fastapi import APIRouter, Depends, HTTPException, Path
from pydantic import BaseModel, ConfigDict
from database import connect
from .education_access import require_headquarters

router = APIRouter()
logger = logging.getLogger(__name__)


class CompleteEducationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    completed: Literal[True]


@router.post(
    "/completion/{training_seq}", summary="교육 이수 처리",
    description="본사 직원이 매니저의 교육 대상 기록을 이수 완료로 처리합니다. 이미 이수된 기록은 그대로 성공으로 응답합니다.",
    responses={
        401: {"description": "본사 로그인 토큰 없음 또는 만료"},
        403: {"description": "재직 중인 본사 직원이 아님"},
        404: {"description": "교육 대상 기록 없음"},
        500: {"description": "이수 처리 실패"},
    },
)
def complete_education(
    training_seq: Annotated[int, Path(description="교육 대상 기록 번호")],
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
