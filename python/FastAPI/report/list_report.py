# 작업자 : 김병재
# 최초 작업 일 : 2026-10-26

# 관리자 신고 내역 목록 API (main.py의 prefix="/report"와 report.py의 prefix="/list"가 붙어 실제 주소는 /report/list)
#   GET /report/list                                  전체 신고 목록 (최신순)
#   GET /report/list?state=접수                        처리 상태 탭 필터 (접수 / 심의중 / 처리완료 / 기각)
#   GET /report/list?sport=SOCCER                     종목 필터 (SOCCER / VOLLEYBALL / BASKETBALL / BASEBALL / ETC)
# 응답에는 목록과 함께 화면 상단 탭/칩에 표시할 건수, 우측 상단 "처리 대기 N건"의 N이 들어 있음
# 조회 테이블: report, customer, headquarter, c_sanction, c_result_record, match_manager, ground
import logging
from typing import Optional

import pymysql
from fastapi import APIRouter, HTTPException, Query, status

from database import connect  # 공용 DB 연결 함수 (python/database.py)

from .report_common import (
    SPORT_ETC,
    SPORT_NAME,
    STATE_DONE,
    STATE_RECEIVED,
    STATE_REVIEWING,
    STATE_TEXT,
    fetch_reports,
)

router = APIRouter()
logger = logging.getLogger(__name__)

# state 파라미터로 받을 수 있는 값. 기각은 저장 방식이 정해지기 전이라 항상 0건
STATE_FILTERS = ["접수", "심의중", "처리완료", "기각"]


# 신고 내역 목록 조회
# 탭 건수는 "다른 필터를 적용한 상태"의 건수: 상태 탭 건수는 종목 필터를, 종목 칩 건수는 상태 필터를 반영
# 신고가 많지 않아 전체를 읽어 서버에서 거르고 센다 (상태/종목은 SQL이 아닌 r_reason·c_result_record에서 계산되기 때문)
@router.get(
    "",
    responses={
        status.HTTP_422_UNPROCESSABLE_CONTENT: {"description": "state 또는 sport 값이 올바르지 않음"},
        status.HTTP_500_INTERNAL_SERVER_ERROR: {"description": "신고 내역 조회 실패"},
    },
)
def list_report(
    state: Optional[str] = Query(default=None, description="처리 상태: 접수 / 심의중 / 처리완료 / 기각"),
    sport: Optional[str] = Query(default=None, description="종목 코드: SOCCER / VOLLEYBALL / BASKETBALL / BASEBALL / ETC"),
) -> dict:
    # 허용하지 않는 필터 값은 DB 조회 전에 거절
    if state is not None and state not in STATE_FILTERS:
        raise HTTPException(status_code=422, detail="state는 접수, 심의중, 처리완료, 기각 중 하나여야 합니다.")
    if sport is not None and sport != SPORT_ETC and sport not in SPORT_NAME:
        raise HTTPException(status_code=422, detail="sport는 SOCCER, VOLLEYBALL, BASKETBALL, BASEBALL, ETC 중 하나여야 합니다.")

    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            reports = fetch_reports(cursor)  # 전체 신고 (최신순)

        # 상태 탭 건수: 종목 필터만 적용한 신고 기준
        by_sport = [r for r in reports if sport is None or r["sport"] == sport]
        status_counts = {"전체": len(by_sport)}
        for code, name in STATE_TEXT.items():
            status_counts[name] = sum(1 for r in by_sport if r["state"] == code)
        status_counts["기각"] = 0  # 기각은 아직 지원하지 않음

        # 종목 칩 건수: 상태 필터만 적용한 신고 기준 (기각 탭이면 항상 0건)
        by_state = [r for r in reports if state is None or r["state_text"] == state]
        sport_counts = [
            {"sport": code, "sport_name": name, "count": sum(1 for r in by_state if r["sport"] == code)}
            for code, name in SPORT_NAME.items()
        ]
        etc_count = sum(1 for r in by_state if r["sport"] == SPORT_ETC)
        if etc_count:  # 목록에 없는 종목은 있을 때만 '기타' 칩을 보여 줌
            sport_counts.append({"sport": SPORT_ETC, "sport_name": "기타", "count": etc_count})

        # 두 필터를 모두 적용한 최종 목록
        results = [r for r in by_state if sport is None or r["sport"] == sport]

        return {
            # 우측 상단 "처리 대기 N건": 필터와 상관없이 아직 처리가 끝나지 않은(접수+심의중) 전체 신고 수
            "pending_count": sum(1 for r in reports if r["state"] in (STATE_RECEIVED, STATE_REVIEWING)),
            "status_counts": status_counts,
            "sport_counts": sport_counts,
            "total": len(results),
            "results": results,
        }
    except HTTPException:
        raise
    except Exception:
        logger.exception("신고 내역 조회 실패")
        raise HTTPException(status_code=500, detail="신고 내역 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료

# 최종 수정 일 : 2026-10-26
