# 작업자 : 김병재
# 최초 작업 일 : 2026-11-03

# 관리자 신고 제재 등록 API (main.py의 prefix="/report"와 report.py의 prefix="/sanction"이 붙어 실제 주소는 /report/sanction/{r_seq})
#   POST /report/sanction/{r_seq}    [제재 등록] 버튼: 심의중인 신고의 피신고자에게 c_sanction(제재)을 등록 → 상태가 심의중에서 처리완료로 바뀜
# 저장 테이블: c_sanction (INSERT만 함, 컬럼 추가/삭제 없음). report는 변경하지 않음
#   처리완료 판단은 report_common.py 규칙대로 "신고일 이후 피신고자에게 제재가 있음"이라 제재만 넣으면 자동으로 처리완료가 됨
# cs_detail 형식: 사용자 앱 제재 내역과 같은 "[제재종류] 제재 내용" (예: "[경고] 폭언·욕설")
# 기각은 저장할 컬럼이 없어서 아직 지원하지 않음. 신고자/피신고자 알림 발송은 추후 기능 추가 때 작업
import logging
from typing import Literal

import pymysql
from fastapi import APIRouter, Body, HTTPException, Path, status
from pydantic import BaseModel, ConfigDict, Field, field_validator

from database import connect  # 공용 DB 연결 함수 (python/database.py)

from .report_common import STATE_DONE, STATE_RECEIVED, STATE_TEXT, fetch_report

router = APIRouter()
logger = logging.getLogger(__name__)


class SanctionRequest(BaseModel):
    """제재 등록 요청입니다. 심의 담당 직원 아이디, 제재 종류, 제재 내용을 보냅니다."""

    # Swagger Try it out 화면에 보이는 기본 예시 값
    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={"example": {"h_id": "admin2", "sanction_type": "경고", "content": "폭언·욕설 (10/26 고척)"}},
    )

    h_id: str = Field(min_length=1, max_length=50, description="제재를 등록하는 본사 직원 아이디(심의를 시작한 직원)")
    sanction_type: Literal["경고", "이용정지", "기타"] = Field(description="제재 종류: 경고 / 이용정지 / 기타")
    content: str = Field(min_length=1, max_length=200, description="제재 내용(사유)")

    @field_validator("h_id", "content", mode="before")
    @classmethod
    def strip_text(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @field_validator("content")
    @classmethod
    def no_bracket_start(cls, value: str) -> str:
        # cs_detail은 앞의 [제재종류]로 종류를 구분하므로 내용이 대괄호로 시작하면 종류 분리가 깨짐
        if value.startswith("["):
            raise ValueError("제재 내용은 '['로 시작할 수 없습니다.")
        return value


# 제재 등록: 신고 확인(행 잠금) → 심의중 + 담당 직원 확인 → 피신고자 확인 → c_sanction INSERT
@router.post(
    "/{r_seq}",
    summary="신고 제재 등록",
    description="심의 중인 신고의 피신고자에게 제재를 등록합니다. 심의를 시작한 본사 직원만 등록할 수 있고, 등록하면 신고가 처리완료 상태가 됩니다.",
    responses={
        status.HTTP_403_FORBIDDEN: {"description": "심의를 시작한 직원이 아님"},
        status.HTTP_404_NOT_FOUND: {"description": "존재하지 않는 신고 번호 또는 피신고자"},
        status.HTTP_409_CONFLICT: {"description": "심의 중인 신고가 아님(접수 상태 또는 이미 처리완료)"},
        status.HTTP_422_UNPROCESSABLE_CONTENT: {"description": "요청 값 검증 실패"},
        status.HTTP_500_INTERNAL_SERVER_ERROR: {"description": "제재 등록 실패"},
    },
)
def create_sanction(r_seq: int = Path(..., description="신고 번호"), payload: SanctionRequest = Body(...)) -> dict:
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            # 같은 신고에 제재가 중복 등록되지 않도록 신고 행을 잠근 뒤 상태를 확인 (커밋/롤백 때 잠금 해제)
            cursor.execute("SELECT r_seq FROM report WHERE r_seq = %s FOR UPDATE", (r_seq,))
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="존재하지 않는 신고입니다.")

            report = fetch_report(cursor, r_seq)
            if report is None:
                raise HTTPException(status_code=404, detail="존재하지 않는 신고입니다.")

            # 심의중일 때만 등록 가능 (접수 = 심의 시작 전, 처리완료 = 이미 제재됨)
            if report["state"] == STATE_RECEIVED:
                raise HTTPException(status_code=409, detail="심의를 시작하지 않은 신고입니다. 먼저 심의를 시작해 주세요.")
            if report["state"] == STATE_DONE:
                raise HTTPException(status_code=409, detail=f"이미 {report['state_text']} 상태인 신고입니다.")

            # 심의를 시작한 직원만 제재 등록 가능
            if report["h_id"] != payload.h_id:
                raise HTTPException(status_code=403, detail="심의를 시작한 본사 직원만 제재를 등록할 수 있습니다.")

            # 피신고자 확인 (신고 대상이 비어 있거나 회원이 없으면 제재할 수 없음)
            if not report["r_person"]:
                raise HTTPException(status_code=404, detail="신고 대상 회원이 없습니다.")
            cursor.execute("SELECT c_id_seq FROM customer WHERE c_id_seq = %s", (report["r_person"],))
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="존재하지 않는 신고 대상 회원입니다.")

            cs_detail = f"[{payload.sanction_type}] {payload.content}"
            cursor.execute(
                "INSERT INTO c_sanction (c_id_seq, h_id, cs_date, cs_detail) VALUES (%s, %s, NOW(), %s)",
                (report["r_person"], payload.h_id, cs_detail),
            )
            cs_seq = cursor.lastrowid

        connection.commit()
        return {
            "result": "OK",
            "r_seq": r_seq,
            "cs_seq": cs_seq,
            "c_id_seq": report["r_person"],
            "sanction_type": payload.sanction_type,
            "cs_detail": payload.content,
            "h_id": payload.h_id,
            "state": STATE_DONE,
            "state_text": STATE_TEXT[STATE_DONE],
        }
    except HTTPException:
        if connection is not None:
            connection.rollback()
        raise  # 위에서 만든 403/404/409는 500으로 바뀌지 않게 그대로 전달
    except Exception:
        if connection is not None:
            connection.rollback()
        logger.exception("제재 등록 실패")
        raise HTTPException(status_code=500, detail="제재 등록에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료

# 최종 수정 일 : 2026-11-03
