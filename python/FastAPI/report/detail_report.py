# 작업자 : 김병재
# 최초 작업 일 : 2026-10-26

# 관리자 신고 상세 API (main.py의 prefix="/report"와 report.py의 prefix="/detail"이 붙어 실제 주소는 /report/detail/{r_seq})
#   GET /report/detail/{r_seq}    신고 1건 상세 + 피신고자 이력(누적 경고 / 받은 신고 / 계정 상태)
# 조회 테이블: report, customer, headquarter, c_sanction, c_result_record, match_manager, ground
import logging
from datetime import datetime, timedelta

import pymysql
from fastapi import APIRouter, HTTPException, status

from database import connect  # 공용 DB 연결 함수 (python/database.py)

from .report_common import STATE_RECEIVED, fetch_report

router = APIRouter()
logger = logging.getLogger(__name__)

# 경고 누적 기준: 경고 3회가 쌓이면 14일 동안 이용 정지가 자동 적용됨 (화면 안내 문구 기준)
WARNING_LIMIT = 3
SUSPEND_DAYS = 14


# 피신고자 이력 조회: 누적 경고(c_sanction 건수), 받은 신고(report 건수), 계정 상태
# 계정 상태: 탈퇴(c_deletdate 있음) > 이용정지(경고 3회 이상이고 마지막 제재가 14일 이내) > 정상
def fetch_target_history(cursor, r_person: str) -> dict:
    cursor.execute(
        "SELECT COUNT(*) AS cnt, MAX(cs_date) AS last_date FROM c_sanction WHERE c_id_seq = %s",
        (r_person,),
    )
    sanction = cursor.fetchone()

    cursor.execute("SELECT COUNT(*) AS cnt FROM report WHERE r_person = %s", (r_person,))
    received = cursor.fetchone()["cnt"]

    cursor.execute("SELECT c_deletdate FROM customer WHERE c_id_seq = %s", (r_person,))
    customer = cursor.fetchone()

    warning_count = sanction["cnt"]
    if customer is not None and customer["c_deletdate"] is not None:
        account_state = "탈퇴"
    elif (
        warning_count >= WARNING_LIMIT
        and sanction["last_date"] is not None
        and sanction["last_date"] >= datetime.now() - timedelta(days=SUSPEND_DAYS)
    ):
        account_state = "이용정지"
    else:
        account_state = "정상"

    return {
        "warning_count": warning_count,        # 누적 경고 (제재 건수)
        "received_report_count": received,     # 받은 신고 건수 (이번 신고 포함)
        "account_state": account_state,        # 계정 상태
    }


# 신고 상세 조회: r_seq로 신고 1건과 피신고자 이력을 함께 조회
@router.get(
    "/{r_seq}",
    responses={
        status.HTTP_404_NOT_FOUND: {"description": "존재하지 않는 신고 번호"},
        status.HTTP_500_INTERNAL_SERVER_ERROR: {"description": "신고 상세 조회 실패"},
    },
)
def detail_report(r_seq: int) -> dict:
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            report = fetch_report(cursor, r_seq)
            if report is None:
                raise HTTPException(status_code=404, detail="존재하지 않는 신고입니다.")
            history = fetch_target_history(cursor, report["r_person"]) if report["r_person"] else None

        # can_start_review: 접수 상태일 때만 [심의 시작] 버튼을 보여 주기 위한 값
        return {
            **report,
            "can_start_review": report["state"] == STATE_RECEIVED,
            "target_history": history,
        }
    except HTTPException:
        raise  # 위에서 만든 404는 500으로 바뀌지 않게 그대로 전달
    except Exception:
        logger.exception("신고 상세 조회 실패")
        raise HTTPException(status_code=500, detail="신고 상세 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료

# 최종 수정 일 : 2026-10-26
