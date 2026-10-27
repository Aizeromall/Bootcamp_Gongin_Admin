# 작업자 : 김병재
# 최초 작업 일 : 2026-10-27

# 관리자 이의신청 목록 API (main.py의 prefix="/appeal"과 appeal.py의 prefix="/list"가 붙어 실제 주소는 /appeal/list)
#   GET /appeal/list                                  전체 이의신청 목록 (최신순)
#   GET /appeal/list?state=접수                        상태 필터 (접수 / 재심의 중 / 인용 / 기각)
#   GET /appeal/list?sport=SOCCER                     종목 필터 (SOCCER / VOLLEYBALL / BASKETBALL / BASEBALL / ETC)
# 응답에는 목록과 함께 좌측 탭 건수(이의신청 / 제재 목록), 종목 칩 건수, 우측 상단 "이의신청 대기 N건"의 N이 들어 있음
# 조회 테이블: appeal, c_sanction, customer, headquarter
import logging
from datetime import datetime
from typing import Optional

import pymysql
from fastapi import APIRouter, HTTPException, Query, status

from database import connect  # 공용 DB 연결 함수 (python/database.py)

from .appeal_common import (
    SPORT_ETC,
    SPORT_NAME,
    STATE_RECEIVED,
    STATE_REVIEWING,
    STATE_TEXT,
    fetch_appeals,
    fetch_sanctions,
    make_sport_counts,
)

router = APIRouter()
logger = logging.getLogger(__name__)

# state 파라미터로 받을 수 있는 값
STATE_FILTERS = list(STATE_TEXT.values())


# 이의신청 목록 조회
# 상태/종목은 SQL이 아닌 a_reason 태그와 회원 선호 종목에서 계산되므로, 전체를 읽어 서버에서 거르고 센다 (건수가 많지 않음)
# 칩 건수는 "다른 필터를 적용한 상태"의 건수: 상태 건수는 종목 필터를, 종목 건수는 상태 필터를 반영
@router.get(
    "",
    responses={
        status.HTTP_422_UNPROCESSABLE_CONTENT: {"description": "state 또는 sport 값이 올바르지 않음"},
        status.HTTP_500_INTERNAL_SERVER_ERROR: {"description": "이의신청 목록 조회 실패"},
    },
)
def list_appeal(
    state: Optional[str] = Query(default=None, description="상태: 접수 / 재심의 중 / 인용 / 기각"),
    sport: Optional[str] = Query(default=None, description="종목 코드: SOCCER / VOLLEYBALL / BASKETBALL / BASEBALL / ETC"),
) -> dict:
    # 허용하지 않는 필터 값은 DB 조회 전에 거절
    if state is not None and state not in STATE_FILTERS:
        raise HTTPException(status_code=422, detail="state는 접수, 재심의 중, 인용, 기각 중 하나여야 합니다.")
    if sport is not None and sport != SPORT_ETC and sport not in SPORT_NAME:
        raise HTTPException(status_code=422, detail="sport는 SOCCER, VOLLEYBALL, BASKETBALL, BASEBALL, ETC 중 하나여야 합니다.")

    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            now = datetime.now()
            sanctions = fetch_sanctions(cursor, now)
            appeals = fetch_appeals(cursor, now, sanctions)  # 전체 이의신청 (최신순)

        # 상태 건수: 종목 필터만 적용한 이의신청 기준
        by_sport = [a for a in appeals if sport is None or a["sport"] == sport]
        status_counts = {"전체": len(by_sport)}
        for code, name in STATE_TEXT.items():
            status_counts[name] = sum(1 for a in by_sport if a["state"] == code)

        # 종목 칩 건수: 상태 필터만 적용한 이의신청 기준
        by_state = [a for a in appeals if state is None or a["state_text"] == state]
        sport_counts = make_sport_counts(by_state)

        # 두 필터를 모두 적용한 최종 목록
        results = [a for a in by_state if sport is None or a["sport"] == sport]

        return {
            # 우측 상단 "이의신청 대기 N건": 필터와 상관없이 결과가 나지 않은(접수 + 재심의 중) 전체 이의신청 수
            "pending_count": sum(1 for a in appeals if a["state"] in (STATE_RECEIVED, STATE_REVIEWING)),
            # 좌측 탭 "이의신청 N / 제재 목록 N"
            "tab_counts": {"appeal": len(appeals), "sanction": len(sanctions)},
            "status_counts": status_counts,
            "sport_counts": sport_counts,
            "total": len(results),
            "results": results,
        }
    except HTTPException:
        raise
    except Exception:
        logger.exception("이의신청 목록 조회 실패")
        raise HTTPException(status_code=500, detail="이의신청 목록 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료

# 최종 수정 일 : 2026-10-27
