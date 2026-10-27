# 작업자 : 김병재
# 최초 작업 일 : 2026-10-27

# 관리자 제재 목록 API ("제재 · 이의신청" 화면의 [제재 목록] 탭)
#   (main.py의 prefix="/appeal"과 appeal.py의 prefix="/sanction"이 붙어 실제 주소는 /appeal/sanction)
#   GET /appeal/sanction                      전체 제재 목록 (최신순)
#   GET /appeal/sanction?sport=SOCCER         종목 필터 (SOCCER / VOLLEYBALL / BASKETBALL / BASEBALL / ETC)
#   GET /appeal/sanction?tag=유효              태그 필터 (유효 / 소멸)
# 제재는 본사가 등록한 c_sanction을 그대로 보여 줌. 소멸 기준은 사용자 앱 제재 내역과 같음(경고는 제재일로부터 90일 후 소멸)
# 조회 테이블: c_sanction, appeal, customer, headquarter
import logging
from datetime import datetime
from typing import Optional

import pymysql
from fastapi import APIRouter, HTTPException, Query, status

from database import connect  # 공용 DB 연결 함수 (python/database.py)

from .appeal_common import (
    SPORT_ETC,
    SPORT_NAME,
    fetch_appeals,
    fetch_sanctions,
    make_sport_counts,
)

router = APIRouter()
logger = logging.getLogger(__name__)

# tag 파라미터로 받을 수 있는 값
TAG_FILTERS = ["유효", "소멸"]


# 제재 목록 조회
# 제재마다 이의신청 건수(appeal_count)와 가장 최근 이의신청 상태(appeal_state_text)를 함께 내려 [이의신청 있음] 표시에 쓸 수 있음
# 종목 칩 건수는 태그 필터를 반영, 태그 건수는 종목 필터를 반영
@router.get(
    "",
    responses={
        status.HTTP_422_UNPROCESSABLE_CONTENT: {"description": "sport 또는 tag 값이 올바르지 않음"},
        status.HTTP_500_INTERNAL_SERVER_ERROR: {"description": "제재 목록 조회 실패"},
    },
)
def list_sanction(
    sport: Optional[str] = Query(default=None, description="종목 코드: SOCCER / VOLLEYBALL / BASKETBALL / BASEBALL / ETC"),
    tag: Optional[str] = Query(default=None, description="태그: 유효 / 소멸"),
) -> dict:
    # 허용하지 않는 필터 값은 DB 조회 전에 거절
    if sport is not None and sport != SPORT_ETC and sport not in SPORT_NAME:
        raise HTTPException(status_code=422, detail="sport는 SOCCER, VOLLEYBALL, BASKETBALL, BASEBALL, ETC 중 하나여야 합니다.")
    if tag is not None and tag not in TAG_FILTERS:
        raise HTTPException(status_code=422, detail="tag는 유효, 소멸 중 하나여야 합니다.")

    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            now = datetime.now()
            sanctions = fetch_sanctions(cursor, now)
            appeals = fetch_appeals(cursor, now, sanctions)  # 최신순

        # 제재별 이의신청 건수와 가장 최근 이의신청 상태 붙이기 (appeals가 최신순이라 처음 만난 것이 가장 최근)
        latest = {}
        count = {}
        for a in appeals:
            if a["cs_seq"] is None:
                continue
            count[a["cs_seq"]] = count.get(a["cs_seq"], 0) + 1
            latest.setdefault(a["cs_seq"], a)
        for s in sanctions:
            s["appeal_count"] = count.get(s["cs_seq"], 0)
            s["appeal_state_text"] = latest[s["cs_seq"]]["state_text"] if s["cs_seq"] in latest else None

        sanctions.reverse()  # fetch_sanctions는 제재일 오름차순이라 화면용으로 최신순으로 뒤집음

        # 태그 건수: 종목 필터만 적용한 제재 기준
        by_sport = [s for s in sanctions if sport is None or s["sport"] == sport]
        tag_counts = {"전체": len(by_sport)}
        for name in TAG_FILTERS:
            tag_counts[name] = sum(1 for s in by_sport if s["tag"] == name)

        # 종목 칩 건수: 태그 필터만 적용한 제재 기준
        by_tag = [s for s in sanctions if tag is None or s["tag"] == tag]
        sport_counts = make_sport_counts(by_tag)

        # 두 필터를 모두 적용한 최종 목록
        results = [s for s in by_tag if sport is None or s["sport"] == sport]

        return {
            # 좌측 탭 "이의신청 N / 제재 목록 N"
            "tab_counts": {"appeal": len(appeals), "sanction": len(sanctions)},
            "tag_counts": tag_counts,
            "sport_counts": sport_counts,
            "total": len(results),
            "results": results,
        }
    except HTTPException:
        raise
    except Exception:
        logger.exception("제재 목록 조회 실패")
        raise HTTPException(status_code=500, detail="제재 목록 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료

# 최종 수정 일 : 2026-10-27
