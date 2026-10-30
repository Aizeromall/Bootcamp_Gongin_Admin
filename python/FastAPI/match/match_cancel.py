# 작업자 : 신현진
# 최초 작업 일 : 2026-10-26

# 본사 구장 취소 내역 조회 API (router prefix로 실제 주소 앞에 /match 가 붙음)
#   GET /match/cancel                                       매니저가 취소한 경기 목록 (취소 사유 포함)
#       ?r_c_category=1 시설 문제 / 2 우천·기상악화 / 3 노쇼 및 환불 (안 보내면 전체)
#       ?g_code=1 특정 구장만 조회 (안 보내면 전체 구장)
#   GET /match/cancel/{g_code}?r_date=날짜&rs_time=08:00    취소된 경기 1건의 예약 회원 목록
# 조회만 하고 받는 값(body)이 없어서 BaseModel class 없음
# 매칭 취소는 경기 매니저가 처리하고 (match_manage_cancel.py), 본사는 이 API로 조회만 함
#
# reservation.r_category : 예약 구분
#   1 = 예약 / 2 = 취소 (취소해도 행을 지우지 않고 r_category만 2로 바꿔서 취소 내역을 조회할 수 있게 함)
# 중간 수정 작성자 - 신현진
# 수정일 2026.10.28
# reservation.r_c_category : 예약 취소 사유 (VARCHAR, 회원 앱과 같은 컬럼을 함께 사용)
#   '1' = 시설 문제 / '2' = 우천·기상악화 / '3' = 노쇼 및 환불 → 매니저가 취소할 때 저장
#   그 외 (회원이 직접 쓴 글) = 회원 직접 취소 → 구장 취소가 아니므로 이 API에서는 제외
#     ('0' ~ '3'은 회원 앱에서 입력을 막아 둠, 사유 이름은 "회원 개인 사정"으로 표시하고 원문은 보내지 않음)
import logging
from datetime import date, timedelta

import pymysql
from fastapi import APIRouter, HTTPException, Query

from database import connect  # 공용 DB 연결 함수 (python/database.py)

# 이 파일의 API들을 담는 라우터 (main.py에서 include_router로 등록)
router = APIRouter(prefix="/match", tags=["구장 취소 조회"])
logger = logging.getLogger(__name__)

# 예약 구분 값 (DB의 r_category 숫자에 이름을 붙여서 코드에서 1, 2를 직접 쓰지 않게 함)
CATEGORY_CANCELED = 2   # 취소

# 중간 수정 작성자 - 신현진
# 수정일 2026.10.28
# 예약 취소 사유 이름 (DB의 r_c_category 값 → 앱에 표시할 이름)
# r_c_category가 VARCHAR라서 '1' 같은 글자 키로 찾음 (숫자 키로 찾으면 전부 "회원 개인 사정"으로 나옴)
CANCEL_CATEGORY_NAMES = {
    "1": "시설 문제",
    "2": "우천·기상악화",
    "3": "노쇼 및 환불",
}
# 1 ~ 3 코드가 아닌 사유(회원이 직접 쓴 글)의 표시 이름 (원문은 개인 정보가 있을 수 있어 보내지 않음)
MEMBER_CANCEL_NAME = "회원 개인 사정"
# 매니저 취소로 보는 사유 조건 (회원이 직접 쓴 글로 저장된 회원 취소는 제외)
# 서버에서 정한 고정 문자열이라 SQL에 바로 넣어도 SQL 인젝션 위험 없음
MANAGER_CANCEL_CONDITION = "r.r_c_category IN ('1', '2', '3')"

# 출석 체크 기록(c_result_record)의 경기 코드와 같은 형식 : 구장코드_YYYYMMDD_HHMMSS
# attendance_check.py에서 만드는 c_r_r_code와 똑같이 맞춰야 회원별 출석(노쇼) 기록을 찾을 수 있음
# %% : 값을 넘겨서 execute 할 때 pymysql이 % 를 자리표시로 읽지 않게 두 번 씀
RECORD_CODE = (
    "CONCAT(r.g_code, '_', DATE_FORMAT(r.r_date, '%%Y%%m%%d'), "
    "'_', TIME_FORMAT(r.rs_time, '%%H%%i%%s'))"
)


# 시간 값 → "08:00" 형식 문자열로 통일
# DB 컬럼이 TIME 타입이면 pymysql이 timedelta로 주기 때문에 그대로 보내면 초(숫자)로 바뀜
# 문자열(varchar)로 저장된 경우에는 앞 5글자(HH:MM)만 사용
def format_time(value) -> str:
    if isinstance(value, timedelta):
        total_minutes = int(value.total_seconds()) // 60
        return f"{total_minutes // 60:02d}:{total_minutes % 60:02d}"
    return str(value)[:5]


# DB에서 받은 취소 경기 1줄(dict) → 앱으로 보낼 JSON(dict)으로 정리
# DictCursor를 쓰기 때문에 row["컬럼명"]으로 값을 꺼냄
def cancel_match_to_dict(row: dict) -> dict:
    return {
        "g_code": row["g_code"],                         # 구장코드
        "g_name": row["g_name"],                         # 구장명 (ground JOIN)
        "g_address": row["g_address"],                   # 구장 주소 (ground JOIN)
        "g_num": row["g_num"],                           # 구장 정원
        "r_date": row["r_date"],                         # 경기일 (취소해도 그대로 유지)
        "rs_time": format_time(row["rs_time"]),          # 경기 시작 시간
        "re_time": format_time(row["re_time"]),          # 경기 종료 시간
        "r_c_category": str(row["r_c_category"]),        # 취소 사유 ('1' / '2' / '3')
        # str() : 글자 키로 이름을 찾고, 1 ~ 3 코드가 아니면 "회원 개인 사정" (2026.10.28 신현진)
        "r_c_category_name": CANCEL_CATEGORY_NAMES.get(str(row["r_c_category"]), MEMBER_CANCEL_NAME),  # 취소 사유 이름 (앱에서 바로 표시)
        "canceled_count": row["canceled_count"],         # 취소된 예약 수 (경기에 예약했던 회원 수)
        "r_check": bool(row["r_check"]),                 # 취소 전 매치 성사 여부 (DB 0/1 → false/true)
        "r_cancel_date": row["r_cancel_date"],           # 취소일
    }


# 취소 경기 조회에서 공통으로 쓰는 SELECT
# r / g 는 테이블 별칭 (reservation / ground)
# 중간 수정 작성자 - 신현진
# 수정일 2026.10.28
# r_c_category IN ('1', '2', '3') : 매니저가 사유를 넣어 취소한 예약만 (회원이 직접 쓴 글로 저장된 회원 취소 제외)
# GROUP BY는 조건을 붙인 뒤 각 API에서 추가 (회원별 예약 여러 줄을 경기 1줄로 묶음)
CANCEL_MATCH_SELECT = f"""
    SELECT r.g_code, g.g_name, g.g_address, g.g_num,
        r.r_date, r.rs_time, r.re_time, r.r_c_category,
        COUNT(*) AS canceled_count,
        MAX(r.r_check) AS r_check,
        MAX(r.r_cancel_date) AS r_cancel_date
    FROM reservation AS r
    INNER JOIN ground AS g ON g.g_code = r.g_code
    WHERE r.r_category = %s
        AND {MANAGER_CANCEL_CONDITION}
"""
CANCEL_MATCH_GROUP_BY = """
    GROUP BY r.g_code, g.g_name, g.g_address, g.g_num,
        r.r_date, r.rs_time, r.re_time, r.r_c_category
"""


# 매니저가 취소한 경기 목록 조회
# 예: /match/cancel                     전체 구장 취소 내역
#     /match/cancel?r_c_category=3      노쇼 및 환불로 취소된 경기만
#     /match/cancel?g_code=1            1번 구장의 취소 내역만
@router.get("/cancel")
def select_canceled_matches(
    # ge=1, le=3 : 1~3 밖의 값이 오면 FastAPI가 자동으로 422 에러 처리
    r_c_category: int | None = Query(None, ge=1, le=3, description="1 시설 문제 / 2 우천·기상악화 / 3 노쇼 및 환불"),
    g_code: str | None = Query(None, description="구장코드 (안 보내면 전체 구장)"),
):
    connection = None
    try:
        connection = connect()  # DB 연결
        # DictCursor : 결과를 (값, 값) 튜플 대신 {"컬럼명": 값} dict로 받음
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            sql = CANCEL_MATCH_SELECT
            params = [CATEGORY_CANCELED]  # %s 자리에 순서대로 들어갈 값
            # 취소 사유를 보낸 경우에만 조건 추가
            if r_c_category is not None:
                sql += " AND r.r_c_category = %s"
                params.append(str(r_c_category))  # VARCHAR 컬럼과 같은 글자로 비교 (2026.10.28 신현진)
            # 구장코드를 보낸 경우에만 조건 추가
            if g_code:
                sql += " AND r.g_code = %s"
                params.append(g_code.strip())
            sql += CANCEL_MATCH_GROUP_BY + " ORDER BY r_cancel_date DESC"
            cursor.execute(sql, params)  # %s 자리에 값이 순서대로 들어감 (SQL 인젝션 방지)
            rows = cursor.fetchall()  # 결과 전체를 dict 목록으로 받음
        # 취소된 경기가 하나도 없으면 빈 리스트 [] 가 나감 (에러 아님)
        return {"results": [cancel_match_to_dict(row) for row in rows]}
    except pymysql.MySQLError:
        logger.exception("구장 취소 내역 DB 조회 실패")
        raise HTTPException(status_code=500, detail="구장 취소 내역 조회 중 DB 오류가 발생했습니다.")
    except Exception:
        logger.exception("구장 취소 내역 조회 실패")
        raise HTTPException(status_code=500, detail="구장 취소 내역 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료


# 취소된 경기 1건의 예약 회원 목록 조회 (환불·노쇼 확인용)
# 예: /match/cancel/1?r_date=2026-10-25&rs_time=08:00
@router.get("/cancel/{g_code}")
def select_canceled_match_detail(
    g_code: str,
    r_date: date,
    # pattern : "08:00" 형식이 아니면 FastAPI가 자동으로 422 에러 처리
    rs_time: str = Query(pattern=r"^\d{2}:\d{2}$", description="경기 시작 시간 (예: 08:00)"),
):
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            # 1) 매니저가 취소한 경기인지 + 경기 정보·취소 사유 조회
            sql = (
                CANCEL_MATCH_SELECT
                + " AND r.g_code = %s AND r.r_date = %s AND r.rs_time = %s"
                + CANCEL_MATCH_GROUP_BY
            )
            cursor.execute(sql, (CATEGORY_CANCELED, g_code, r_date, rs_time))
            match = cursor.fetchone()  # 1건만 받음 (없으면 None)
            if match is None:
                raise HTTPException(status_code=404, detail="매니저가 취소한 경기가 아닙니다.")

            # 2) 해당 경기에서 매니저 취소로 함께 취소된 회원 목록
            # INNER JOIN customer : 회원 이름·전화번호를 함께 가져옴
            # LEFT JOIN pay : 환불(결제 삭제)된 예약도 빠지지 않고 나옴 (결제 값은 None)
            # LEFT JOIN c_result_record : 출석 체크 전에 취소된 회원도 빠지지 않고 나옴 (출석 값은 None)
            # 중간 수정 작성자 - 신현진
            # 수정일 2026.10.28
            # r_c_category IN ('1', '2', '3') : 그 전에 회원이 직접 취소한 예약(회원이 쓴 글로 저장)은 제외
            sql = f"""
                SELECT r.r_seq, r.c_id_seq, c.c_name, c.c_phone,
                    r.r_cancel_date, p.p_seq, cr.c_r_r_attendance
                FROM reservation AS r
                INNER JOIN customer AS c ON c.c_id_seq = r.c_id_seq
                LEFT JOIN pay AS p ON p.r_seq = r.r_seq
                LEFT JOIN c_result_record AS cr
                    ON cr.c_id_seq = r.c_id_seq
                    AND cr.g_code = r.g_code
                    AND cr.c_r_r_code = {RECORD_CODE}
                WHERE r.g_code = %s AND r.r_date = %s AND r.rs_time = %s
                    AND r.r_category = %s
                    AND {MANAGER_CANCEL_CONDITION}
                ORDER BY r.r_seq
            """
            cursor.execute(sql, (g_code, r_date, rs_time, CATEGORY_CANCELED))
            rows = cursor.fetchall()

        members = []
        for row in rows:
            attendance = row["c_r_r_attendance"]
            members.append({
                "r_seq": row["r_seq"],                   # 예약번호
                "c_id_seq": row["c_id_seq"],             # 회원 (회원ID + 종목번호)
                "c_name": row["c_name"],                 # 회원 이름 (customer JOIN)
                "c_phone": row["c_phone"],               # 회원 전화번호 (환불 안내 연락용)
                "r_cancel_date": row["r_cancel_date"],   # 취소일
                # 출석 여부 (출석 체크 전에 취소됐으면 None)
                "attendance": None if attendance is None else bool(attendance),
                "is_noshow": attendance is not None and not bool(attendance),  # 노쇼 여부
                # 결제 내역이 남아 있으면 아직 환불되지 않은 것 (취소 시 pay에서 삭제됨)
                "is_refunded": row["p_seq"] is None,
            })

        result = cancel_match_to_dict(match)
        result["noshow_count"] = sum(1 for member in members if member["is_noshow"])  # 노쇼 회원 수
        result["members"] = members  # 경기 정보 + 예약 회원 목록을 한 번에 보냄
        return result
    except HTTPException:
        raise  # 위에서 만든 404는 500으로 바뀌지 않게 그대로 전달
    except pymysql.MySQLError:
        logger.exception("구장 취소 경기 상세 DB 조회 실패")
        raise HTTPException(status_code=500, detail="구장 취소 경기 조회 중 DB 오류가 발생했습니다.")
    except Exception:
        logger.exception("구장 취소 경기 상세 조회 실패")
        raise HTTPException(status_code=500, detail="구장 취소 경기 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()

# 최종 수정 일 : 2026-10-28

# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
