# 작업자 : 김병재
# 최초 작업 일 : 2026-10-27

# 관리자 이의신청 상세 API (main.py의 prefix="/appeal"과 appeal.py의 prefix="/detail"이 붙어 실제 주소는 /appeal/detail/{a_seq})
#   GET /appeal/detail/{a_seq}    이의신청 1건 상세: 대상 제재 + 이의신청 내용(사유·상세·증빙 링크) + [재심의 시작] 노출 여부
# 조회 테이블: appeal, c_sanction, customer, headquarter
import logging
from datetime import datetime

import pymysql
from fastapi import APIRouter, HTTPException, status

from database import connect  # 공용 DB 연결 함수 (python/database.py)

from .appeal_common import STATE_RECEIVED, fetch_appeal

router = APIRouter()
logger = logging.getLogger(__name__)


# 이의신청 상세 조회: a_seq로 이의신청 1건과 대상 제재를 함께 조회
@router.get(
    "/{a_seq}",
    responses={
        status.HTTP_404_NOT_FOUND: {"description": "존재하지 않는 이의신청 번호"},
        status.HTTP_500_INTERNAL_SERVER_ERROR: {"description": "이의신청 상세 조회 실패"},
    },
)
def detail_appeal(a_seq: int) -> dict:
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            appeal = fetch_appeal(cursor, a_seq, datetime.now())
        if appeal is None:
            raise HTTPException(status_code=404, detail="존재하지 않는 이의신청입니다.")

        # can_start_review: 접수 상태일 때만 [재심의 시작] 버튼을 보여 주기 위한 값
        return {**appeal, "can_start_review": appeal["state"] == STATE_RECEIVED}
    except HTTPException:
        raise  # 위에서 만든 404는 500으로 바뀌지 않게 그대로 전달
    except Exception:
        logger.exception("이의신청 상세 조회 실패")
        raise HTTPException(status_code=500, detail="이의신청 상세 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료

# 최종 수정 일 : 2026-10-27
