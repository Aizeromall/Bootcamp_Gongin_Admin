# 작업자 : 최현준
# 작업 일 : 2026-10-27
"""SQL 없이 공지 입력 선택값과 DB 오류 응답만 공유합니다."""
import logging
from typing import Literal

import pymysql
from fastapi import HTTPException
from FastAPI.login.admin_login import connect

Target = Literal["사용자", "매니저", "본사"]
Classification = Literal["이벤트", "운영", "정책", "점검", "공지"]
TARGETS = ("사용자", "매니저", "본사")
logger = logging.getLogger(__name__)


def database_error(error):
    # DB 내부 오류/접속 정보를 응답에 노출하지 않습니다.
    logger.error("공지 DB 처리 실패: %s", type(error).__name__)
    return HTTPException(
        503 if isinstance(error, pymysql.err.OperationalError) else 500,
        detail={"code": "ANNOUNCE_DB_ERROR", "message": "공지 데이터베이스 처리에 실패했습니다."},
    )

# 최종 수정일 : 2026-10-27
