# 작업자 : 신현진
# 최초 작업 일 : 2026-10-26

# 경기 매니저 매칭 취소 API (router prefix로 실제 주소 앞에 /match 가 붙음)
#   PATCH /match/manage/cancel/{m_id}     매니저가 담당 구장의 경기(구장·날짜·시작시간) 1건 매칭 취소
#   GET   /match/manage/cancel/{m_id}     매니저 담당 구장에서 취소된 경기 목록
#       ?r_c_category=1 정원 미달 / 2 우천·기상악화 / 3 노쇼 및 환불 (안 보내면 전체)
#
# reservation.r_category : 예약 구분
#   1 = 예약 / 2 = 취소 (취소해도 행을 지우지 않고 r_category만 2로 바꿔서 취소 내역을 조회할 수 있게 함)
# reservation.r_c_category : 예약 취소 사유 (매니저가 취소할 때 저장, 회원이 직접 취소하면 NULL)
#   1 = 정원 미달       : 예약 인원이 구장 정원(g_num)보다 적은 경기
#                         (정원이 안 차도 참가 회원들이 진행을 원하면 취소하지 않고 그대로 진행)
#   2 = 우천·기상악화   : 불가피한 상황이라 성사 여부(r_check)와 상관없이 취소 가능
#   3 = 노쇼 및 환불    : 노쇼 회원이 있고, 빈자리 재예약까지 합쳐도 참여 인원이 정원의 70% 미만인 경기
# 성사 여부(r_check)가 0이든 1이든 위 사유 조건만 맞으면 매니저가 취소할 수 있음
#
# 취소하면 해당 경기에 예약된 회원 전체가 한 번에 취소되고, 결제 내역(pay)은 삭제 (환불 처리)
import logging
from datetime import date, timedelta

import pymysql
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from database import connect  # 공용 DB 연결 함수 (python/database.py)

# 이 파일의 API들을 담는 라우터 (main.py에서 include_router로 등록)
router = APIRouter(prefix="/match", tags=["매니저 매칭 취소"])
logger = logging.getLogger(__name__)

# 예약 구분 값 (DB의 r_category 숫자에 이름을 붙여서 코드에서 1, 2를 직접 쓰지 않게 함)
CATEGORY_RESERVED = 1   # 예약
CATEGORY_CANCELED = 2   # 취소

# 예약 취소 사유 값 (DB의 r_c_category)
CANCEL_UNDER_CAPACITY = 1   # 정원 미달
CANCEL_WEATHER = 2          # 우천·기상악화
CANCEL_NO_SHOW = 3          # 노쇼 및 환불
CANCEL_CATEGORY_NAMES = {
    CANCEL_UNDER_CAPACITY: "정원 미달",
    CANCEL_WEATHER: "우천·기상악화",
    CANCEL_NO_SHOW: "노쇼 및 환불",
}

# 노쇼 취소 기준 : 참여 인원이 정원의 몇 % 미만이면 취소할 수 있는지
NO_SHOW_MIN_RATE = 70

# 출석 체크 기록(c_result_record)의 경기 코드와 같은 형식 : 구장코드_YYYYMMDD_HHMMSS
# attendance_check.py에서 만드는 c_r_r_code와 똑같이 맞춰야 노쇼(결석) 기록을 찾을 수 있음
# %% : 값을 넘겨서 execute 할 때 pymysql이 % 를 자리표시로 읽지 않게 두 번 씀
RECORD_CODE = (
    "CONCAT(r.g_code, '_', DATE_FORMAT(r.r_date, '%%Y%%m%%d'), "
    "'_', TIME_FORMAT(r.rs_time, '%%H%%i%%s'))"
)


# 매칭 취소 요청 body
# 한 경기 = 구장코드 + 경기일 + 시작시간 (같은 시간대에 예약한 회원들이 한 경기에 참여)
class MatchCancel(BaseModel):
    g_code: str = Field(min_length=1, description="구장코드")
    r_date: date = Field(description="경기일 (예: 2026-10-25)")
    # pattern : "08:00" 형식이 아니면 FastAPI가 자동으로 422 에러 처리
    rs_time: str = Field(pattern=r"^\d{2}:\d{2}$", description="경기 시작 시간 (예: 08:00)")
    # ge=1, le=3 : 1~3 밖의 값이 오면 FastAPI가 자동으로 422 에러 처리
    r_c_category: int = Field(ge=1, le=3, description="1 정원 미달 / 2 우천·기상악화 / 3 노쇼 및 환불")


# 시간 값 → "08:00" 형식 문자열로 통일
# DB 컬럼이 TIME 타입이면 pymysql이 timedelta로 주기 때문에 그대로 보내면 초(숫자)로 바뀜
# 문자열(varchar)로 저장된 경우에는 앞 5글자(HH:MM)만 사용
def format_time(value) -> str:
    if isinstance(value, timedelta):
        total_minutes = int(value.total_seconds()) // 60
        return f"{total_minutes // 60:02d}:{total_minutes % 60:02d}"
    return str(value)[:5]


# 매니저 존재 여부 확인 (없으면 404)
# 다른 API에서도 같은 확인을 하므로 함수로 분리
def check_manager(cursor, m_id: str) -> dict:
    cursor.execute("SELECT m_id, m_name FROM match_manager WHERE m_id = %s", (m_id,))
    manager = cursor.fetchone()  # 1건만 받음 (없으면 None)
    if manager is None:
        raise HTTPException(status_code=404, detail="매니저 ID가 존재하지 않습니다.")
    return manager


# 경기 매칭 취소 (매니저)
# 예: PATCH /match/manage/cancel/manager01
#     body {"g_code": "G001", "r_date": "2026-10-25", "rs_time": "08:00", "r_c_category": 2}
@router.patch("/manage/cancel/{m_id}")
def cancel_match(m_id: str, cancel: MatchCancel):
    g_code = cancel.g_code.strip()  # 앞뒤 공백 제거
    connection = None
    try:
        connection = connect()  # DB 연결
        # DictCursor : 결과를 (값, 값) 튜플 대신 {"컬럼명": 값} dict로 받음
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            # 1) 매니저 확인
            manager = check_manager(cursor, m_id)

            # 2) 요청한 매니저에게 해당 구장이 배정되어 있는지 확인
            cursor.execute(
                "SELECT assign_seq FROM assign WHERE m_id = %s AND g_code = %s LIMIT 1",
                (m_id, g_code),
            )
            if cursor.fetchone() is None:
                raise HTTPException(status_code=403, detail="담당 구장의 경기만 취소할 수 있습니다.")

            # 3) 구장 정원(g_num) 확인
            cursor.execute("SELECT g_code, g_name, g_num FROM ground WHERE g_code = %s", (g_code,))
            ground = cursor.fetchone()
            if ground is None:
                raise HTTPException(status_code=404, detail="존재하지 않는 구장 코드입니다.")

            # 4) 지난 경기인지 확인 (노쇼 취소는 경기 당일에 하므로 오늘은 허용)
            if cancel.r_date < date.today():
                raise HTTPException(status_code=409, detail="이미 지난 경기는 취소할 수 없습니다.")

            # 5) 취소할 경기의 예약 목록 조회
            # r_category = 1 : 아직 예약 상태인 회원만 (이미 취소한 회원은 제외)
            # LEFT JOIN c_result_record : 출석 체크 전인 회원도 빠지지 않고 나옴 (출석 값은 None)
            # FOR UPDATE : 취소하는 동안 다른 요청(회원 취소, 재예약 등)이 이 예약들을 바꾸지 못하게 잠금
            sql = f"""
                SELECT r.r_seq, r.c_id_seq, r.r_check, cr.c_r_r_attendance
                FROM reservation AS r
                LEFT JOIN c_result_record AS cr
                    ON cr.c_id_seq = r.c_id_seq
                    AND cr.g_code = r.g_code
                    AND cr.c_r_r_code = {RECORD_CODE}
                WHERE r.g_code = %s AND r.r_date = %s AND r.rs_time = %s AND r.r_category = %s
                FOR UPDATE
            """
            cursor.execute(sql, (g_code, cancel.r_date, cancel.rs_time, CATEGORY_RESERVED))
            reservations = cursor.fetchall()  # 결과 전체를 dict 목록으로 받음
            if not reservations:
                raise HTTPException(status_code=404, detail="취소할 예약이 없는 경기입니다.")

            capacity = ground["g_num"]                 # 구장 정원
            reservation_count = len(reservations)      # 현재 예약 인원 (빈자리 재예약 포함)
            # 결석(0)으로 출석 체크된 회원 수 (출석 체크 전 None은 노쇼가 아님)
            noshow_count = sum(1 for row in reservations if row["c_r_r_attendance"] == 0)
            attend_count = reservation_count - noshow_count  # 실제 참여 가능한 인원

            # 6) 취소 사유별 조건 확인
            if cancel.r_c_category == CANCEL_UNDER_CAPACITY:
                # 정원이 다 찼으면 정원 미달이 아님
                if reservation_count >= capacity:
                    raise HTTPException(status_code=409, detail="정원이 다 찬 경기는 정원 미달로 취소할 수 없습니다.")
            elif cancel.r_c_category == CANCEL_NO_SHOW:
                # 노쇼 회원이 없으면 노쇼 취소가 아님
                if noshow_count == 0:
                    raise HTTPException(status_code=409, detail="노쇼(결석) 처리된 회원이 없습니다.")
                # 참여 인원이 정원의 70% 이상이면 경기 진행 가능
                # 소수점 계산 대신 양쪽에 100을 곱해서 정수로 비교 (예: 정원 10명 → 7명 이상이면 진행)
                if attend_count * 100 >= capacity * NO_SHOW_MIN_RATE:
                    raise HTTPException(
                        status_code=409,
                        detail=f"참여 인원이 정원의 {NO_SHOW_MIN_RATE}% 이상이라 경기를 진행할 수 있습니다.",
                    )
            # 우천·기상악화(2)는 조건 없이 취소 가능

            # 7) 결제 내역 삭제 (환불 처리)
            # IN (%s, %s, ...) : 예약번호 개수만큼 자리표시를 만들어서 한 번에 처리
            r_seqs = [row["r_seq"] for row in reservations]
            placeholders = ", ".join(["%s"] * len(r_seqs))
            # placeholders는 "%s" 문자열만 들어가므로 f-string을 써도 SQL 인젝션 위험 없음
            cursor.execute(
                f"SELECT COUNT(*) AS refund_count, COALESCE(SUM(p_amount), 0) AS refund_amount "
                f"FROM pay WHERE r_seq IN ({placeholders})",
                r_seqs,
            )
            refund = cursor.fetchone()  # 환불 건수·금액 안내용
            cursor.execute(f"DELETE FROM pay WHERE r_seq IN ({placeholders})", r_seqs)

            # 8) 경기 전체 예약을 취소 상태로 변경 (DELETE 대신 UPDATE)
            # r_category = 2 : 취소 카테고리로 이동 → 회원 앱의 취소 내역에 표시
            # r_c_category : 매니저가 선택한 취소 사유 저장
            # r_cancel_date = NOW() : 취소한 날짜·시간 저장 (r_date 경기일은 그대로 유지)
            sql = f"""
                UPDATE reservation
                SET r_category = %s, r_c_category = %s, r_cancel_date = NOW()
                WHERE r_seq IN ({placeholders}) AND r_category = %s
            """
            cursor.execute(sql, [CATEGORY_CANCELED, cancel.r_c_category, *r_seqs, CATEGORY_RESERVED])
            canceled_count = cursor.rowcount  # 실제로 취소된 예약 수

        connection.commit()  # 결제 삭제 + 예약 취소 상태 변경을 한 번에 확정
        return {
            "result": "OK",
            "m_id": manager["m_id"],                                         # 취소한 매니저
            "g_code": ground["g_code"],                                      # 구장코드
            "g_name": ground["g_name"],                                      # 구장명
            "r_date": cancel.r_date,                                         # 취소한 경기의 경기일
            "rs_time": cancel.rs_time,                                       # 경기 시작 시간
            "r_c_category": cancel.r_c_category,                             # 취소 사유 (1 / 2 / 3)
            "r_c_category_name": CANCEL_CATEGORY_NAMES[cancel.r_c_category], # 취소 사유 이름
            "g_num": capacity,                                               # 구장 정원
            "canceled_count": canceled_count,                                # 취소된 예약 수
            "noshow_count": noshow_count,                                    # 노쇼(결석) 회원 수
            "refund_count": refund["refund_count"],                          # 환불된 결제 건수
            "refund_amount": refund["refund_amount"],                        # 환불 금액 합계
        }
    except HTTPException:
        if connection is not None:
            connection.rollback()  # 위에서 만든 404/403/409는 되돌린 뒤 그대로 전달
        raise
    except pymysql.MySQLError:
        if connection is not None:
            connection.rollback()  # 에러 시 결제 삭제·취소 상태 변경을 모두 되돌림
        logger.exception("매칭 취소 DB 처리 실패")
        raise HTTPException(status_code=500, detail="매칭 취소 중 DB 오류가 발생했습니다.")
    except Exception:
        if connection is not None:
            connection.rollback()
        logger.exception("매칭 취소 처리 실패")
        raise HTTPException(status_code=500, detail="매칭 취소에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료


# 매니저 담당 구장에서 취소된 경기 목록 조회
# r_c_category IS NOT NULL : 매니저가 취소한 경기만 (회원이 직접 취소한 예약은 사유가 NULL이라 제외)
# GROUP BY : 회원별 예약 여러 줄을 경기(구장·날짜·시작시간·사유) 1줄로 묶음
# 예: /match/manage/cancel/manager01                  전체 취소 경기
#     /match/manage/cancel/manager01?r_c_category=3   노쇼 및 환불로 취소된 경기만
@router.get("/manage/cancel/{m_id}")
def select_canceled_matches(
    m_id: str,
    # ge=1, le=3 : 1~3 밖의 값이 오면 FastAPI가 자동으로 422 에러 처리
    r_c_category: int | None = Query(None, ge=1, le=3, description="1 정원 미달 / 2 우천·기상악화 / 3 노쇼 및 환불"),
):
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            manager = check_manager(cursor, m_id)

            # r / g 는 테이블 별칭 (reservation / ground)
            # EXISTS assign : 매니저에게 배정된 구장만 (배정 기록이 여러 개여도 경기 중복 방지)
            sql = """
                SELECT r.g_code, g.g_name, g.g_num,
                    r.r_date, r.rs_time, r.re_time, r.r_c_category,
                    COUNT(*) AS canceled_count,
                    MAX(r.r_cancel_date) AS r_cancel_date
                FROM reservation AS r
                INNER JOIN ground AS g ON g.g_code = r.g_code
                WHERE r.r_category = %s
                    AND r.r_c_category IS NOT NULL
                    AND EXISTS (
                        SELECT 1
                        FROM assign AS a
                        WHERE a.g_code = r.g_code
                            AND a.m_id = %s
                    )
            """
            params = [CATEGORY_CANCELED, m_id]  # %s 자리에 순서대로 들어갈 값
            # 취소 사유를 보낸 경우에만 조건 추가
            if r_c_category is not None:
                sql += " AND r.r_c_category = %s"
                params.append(r_c_category)
            sql += """
                GROUP BY r.g_code, g.g_name, g.g_num, r.r_date, r.rs_time, r.re_time, r.r_c_category
                ORDER BY r_cancel_date DESC
            """
            cursor.execute(sql, params)  # %s 자리에 값이 순서대로 들어감 (SQL 인젝션 방지)
            rows = cursor.fetchall()

        matches = []
        for row in rows:
            matches.append({
                "g_code": row["g_code"],                                     # 구장코드
                "g_name": row["g_name"],                                     # 구장명 (ground JOIN)
                "g_num": row["g_num"],                                       # 구장 정원
                "r_date": row["r_date"],                                     # 경기일
                "rs_time": format_time(row["rs_time"]),                      # 경기 시작 시간
                "re_time": format_time(row["re_time"]),                      # 경기 종료 시간
                "r_c_category": row["r_c_category"],                         # 취소 사유 (1 / 2 / 3)
                "r_c_category_name": CANCEL_CATEGORY_NAMES.get(row["r_c_category"], "기타"),  # 취소 사유 이름
                "canceled_count": row["canceled_count"],                     # 취소된 예약 수
                "r_cancel_date": row["r_cancel_date"],                       # 취소일
            })
        # 취소된 경기가 하나도 없으면 빈 리스트 [] 가 나감 (에러 아님)
        return {
            "m_id": manager["m_id"],
            "m_name": manager["m_name"],
            "results": matches,
        }
    except HTTPException:
        raise  # 위에서 만든 404는 500으로 바뀌지 않게 그대로 전달
    except pymysql.MySQLError:
        logger.exception("매니저 취소 경기 DB 조회 실패")
        raise HTTPException(status_code=500, detail="취소 경기 조회 중 DB 오류가 발생했습니다.")
    except Exception:
        logger.exception("매니저 취소 경기 조회 실패")
        raise HTTPException(status_code=500, detail="취소 경기 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()

# 최종 수정 일 : 2026-10-26
