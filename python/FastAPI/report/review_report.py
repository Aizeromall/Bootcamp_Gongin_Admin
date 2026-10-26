# 작업자 : 김병재
# 최초 작업 일 : 2026-10-26

# 관리자 신고 심의 시작 API (main.py의 prefix="/report"와 report.py의 prefix="/review"가 붙어 실제 주소는 /report/review/{r_seq})
#   POST /report/review/{r_seq}    [심의 시작] 버튼: report.h_id에 심의를 시작한 본사 직원 ID를 저장 → 상태가 접수에서 심의중으로 바뀜
# 저장 테이블: report (h_id 컬럼만 변경, 컬럼 추가/삭제 없음)
# 신고자 알림 발송은 아직 만들지 않음 (추후 기능 추가 때 작업)
import logging

import pymysql
from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, field_validator

from database import connect  # 공용 DB 연결 함수 (python/database.py)

from .report_common import STATE_RECEIVED, STATE_REVIEWING, STATE_TEXT, fetch_report

router = APIRouter()
logger = logging.getLogger(__name__)


class StartReviewRequest(BaseModel):
    """심의 시작 요청입니다. 심의를 시작하는 본사 직원 아이디를 보냅니다."""

    # Swagger Try it out 화면에 보이는 기본 예시 값
    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={"example": {"h_id": "admin2"}},
    )

    h_id: str = Field(min_length=1, max_length=50, description="심의를 시작하는 본사 직원 아이디(headquarter PK)")

    @field_validator("h_id", mode="before")
    @classmethod
    def strip_text(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value


# 심의 시작: 신고 확인 → 본사 직원 확인 → 접수 상태일 때만 h_id 저장
@router.post(
    "/{r_seq}",
    responses={
        status.HTTP_404_NOT_FOUND: {"description": "존재하지 않는 신고 번호 또는 본사 직원 아이디"},
        status.HTTP_409_CONFLICT: {"description": "이미 심의가 시작되었거나 처리가 끝난 신고"},
        status.HTTP_422_UNPROCESSABLE_CONTENT: {"description": "요청 값 검증 실패"},
        status.HTTP_500_INTERNAL_SERVER_ERROR: {"description": "심의 시작 실패"},
    },
)
def start_review(r_seq: int, payload: StartReviewRequest) -> dict:
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            # 신고 존재 여부 확인
            report = fetch_report(cursor, r_seq)
            if report is None:
                raise HTTPException(status_code=404, detail="존재하지 않는 신고입니다.")

            # 본사 직원 존재 여부 확인 (h_id가 headquarter PK). 퇴사한 직원은 심의를 시작할 수 없음
            cursor.execute(
                "SELECT h_name, h_resignationdate FROM headquarter WHERE h_id = %s",
                (payload.h_id,),
            )
            staff = cursor.fetchone()
            if staff is None or staff["h_resignationdate"] is not None:
                raise HTTPException(status_code=404, detail="존재하지 않거나 퇴사한 본사 직원입니다.")

            # 이미 심의 중이거나 처리완료면 다시 시작할 수 없음 (현재 상태를 안내)
            if report["state"] != STATE_RECEIVED:
                raise HTTPException(
                    status_code=409,
                    detail=f"이미 {report['state_text']} 상태인 신고입니다.",
                )

            # 다른 직원이 동시에 시작한 경우를 막기 위해 h_id가 비어 있을 때만 UPDATE
            cursor.execute(
                "UPDATE report SET h_id = %s WHERE r_seq = %s AND h_id IS NULL",
                (payload.h_id, r_seq),
            )
            if cursor.rowcount == 0:
                raise HTTPException(status_code=409, detail="이미 심의가 시작된 신고입니다.")

        connection.commit()
        return {
            "result": "OK",
            "r_seq": r_seq,
            "h_id": payload.h_id,
            "h_name": staff["h_name"],
            "state": STATE_REVIEWING,
            "state_text": STATE_TEXT[STATE_REVIEWING],
        }
    except HTTPException:
        if connection is not None:
            connection.rollback()
        raise  # 위에서 만든 404/409는 500으로 바뀌지 않게 그대로 전달
    except Exception:
        if connection is not None:
            connection.rollback()
        logger.exception("심의 시작 실패")
        raise HTTPException(status_code=500, detail="심의 시작에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료

# 최종 수정 일 : 2026-10-26
