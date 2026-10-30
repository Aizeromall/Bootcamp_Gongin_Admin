# 작업자 : 신현진
# 최초 작업 일 : 2026-10-26

# 경기 매니저 매칭 취소 API (router prefix로 실제 주소 앞에 /match 가 붙음)
#   PATCH /match/manage/cancel/{m_id}     매니저가 담당 구장의 경기(구장·날짜·시작시간) 1건 매칭 취소
#   GET   /match/manage/cancel/{m_id}     매니저 담당 구장에서 취소된 경기 목록
#       ?r_c_category=1 시설 문제 / 2 우천·기상악화 / 3 노쇼 및 환불 (안 보내면 전체)
#
# reservation.r_category : 예약 구분
#   1 = 예약 / 2 = 취소 (취소해도 행을 지우지 않고 r_category만 2로 바꿔서 취소 내역을 조회할 수 있게 함)
# 중간 수정 작성자 - 신현진
# 수정일 2026.10.28
# reservation.r_c_category : 예약 취소 사유 (VARCHAR, 회원 앱과 같은 컬럼을 함께 사용)
#   매니저가 취소할 때는 '1' / '2' / '3' 코드만 저장
#   그 외 (회원이 직접 쓴 글) = 회원 직접 취소 (회원 앱에서 저장) → 매니저 취소가 아니므로 이 API의 조회에서 제외
#     ('0' ~ '3'은 회원 앱에서 입력을 막아 둠, 사유 이름은 "회원 개인 사정"으로 표시하고 원문은 보내지 않음)
#   1 = 시설 문제       : 시설 이상으로 진행할 수 없는 경기 (정원·성사 여부와 무관)
#                         기존 코드 1의 정원 미달 의미를 시설 문제로 변경 (2026.10.30 양태건)
#   2 = 우천·기상악화   : 불가피한 상황이라 성사 여부(r_check)와 상관없이 취소 가능
#   3 = 노쇼 및 환불    : 노쇼 회원이 있고, 빈자리 재예약까지 합쳐도 참여 인원이 정원의 70% 미만인 경기
# 성사 여부(r_check)가 0이든 1이든 위 사유 조건만 맞으면 매니저가 취소할 수 있음
#
# 취소하면 해당 경기에 예약된 회원 전체가 한 번에 취소되고, 결제 내역(pay)은 삭제 (환불 처리)
import logging
from datetime import date, timedelta
from typing import Literal

import pymysql
from fastapi import APIRouter, HTTPException, Query, Header
from pydantic import BaseModel, Field

# 수정 일 : 2026-10-30 / 작업자 : 양태건
from . import match_operations as operations
from .manager_session import require_manager
from .team_match_search import TEAM_MATCH_SELECT

from database import connect  # 공용 DB 연결 함수 (python/database.py)

# 이 파일의 API들을 담는 라우터 (main.py에서 include_router로 등록)
router = APIRouter(prefix="/match", tags=["매니저 매칭 취소"])
logger = logging.getLogger(__name__)

# 예약 구분 값 (DB의 r_category 숫자에 이름을 붙여서 코드에서 1, 2를 직접 쓰지 않게 함)
CATEGORY_RESERVED = 1   # 예약
CATEGORY_CANCELED = 2   # 취소

# 예약 취소 사유 값 (매니저가 요청 body로 보내는 숫자 1 / 2 / 3)
CANCEL_FACILITY = 1   # 시설 문제
CANCEL_WEATHER = 2          # 우천·기상악화
CANCEL_NO_SHOW = 3          # 노쇼 및 환불

# 중간 수정 작성자 - 신현진
# 수정일 2026.10.28
# r_c_category가 VARCHAR라서 DB에는 '1' 같은 글자로 저장되고 조회됨
# → 사유 이름도 글자 키로 찾음 (숫자 키로 찾으면 '1'을 못 찾아서 전부 "회원 개인 사정"으로 나옴)
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
    # 팀매칭은 숫자 경기코드로 출석을 조회하며 실력매칭 요청 계약은 유지합니다.
    team_code: int | None = Field(default=None, ge=1, description="팀매칭 경기코드")
    g_code: str = Field(min_length=1, description="구장코드")
    r_date: date = Field(description="경기일 (예: 2026-10-25)")
    # pattern : "08:00" 형식이 아니면 FastAPI가 자동으로 422 에러 처리
    rs_time: str = Field(pattern=r"^\d{2}:\d{2}$", description="경기 시작 시간 (예: 08:00)")
    # ge=1, le=3 : 1~3 밖의 값이 오면 FastAPI가 자동으로 422 에러 처리
    r_c_category: int = Field(ge=1, le=3, description="1 시설 문제 / 2 우천·기상악화 / 3 노쇼 및 환불")


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
@operations.serialized
def cancel_match(m_id: str, cancel: MatchCancel, authorization: str = Header(default="")):
    # 팀매칭 확장 경로는 로그인한 담당자와 요청 ID를 모두 검증합니다.
    if cancel.team_code is not None and require_manager(authorization) != m_id:
        raise HTTPException(403, "로그인한 담당자의 경기만 취소할 수 있습니다.")
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

            # 수정 일 : 2026-10-30 / 작업자 : 양태건
            # 팀매칭을 잠가 시작/결과 등록과 취소가 동시에 처리되지 않도록 합니다.
            record_code = RECORD_CODE
            record_params = ()
            team_condition = ""
            if cancel.team_code is not None:
                cursor.execute("SELECT team_code FROM team_match WHERE team_code=%s FOR UPDATE", (cancel.team_code,))
                if cursor.fetchone() is None:
                    raise HTTPException(404, "팀매칭을 찾을 수 없습니다.")
                cursor.execute(TEAM_MATCH_SELECT + " WHERE base.team_code=%s AND rm.m_id=%s", (cancel.team_code, m_id))
                team = cursor.fetchone()
                if (team is None or str(team['rental_g_code']) != g_code
                    or team['team_start'].date() != cancel.r_date
                    or team['team_start'].strftime('%H:%M') != cancel.rs_time):
                    raise HTTPException(403, "담당 팀매칭의 구장과 경기 일시를 확인해 주세요.")
                cursor.execute("SELECT 1 FROM t_result_record WHERE t_r_r_m_code=%s LIMIT 1", (str(cancel.team_code),))
                cached = operations._MATCHES.get(str(cancel.team_code))
                if cursor.fetchone() is not None or (cached and cached[0]['status'] != 'attendance'):
                    raise HTTPException(409, "시작했거나 결과가 등록된 팀매칭은 취소할 수 없습니다.")
                record_code = "%s"
                record_params = (str(cancel.team_code),)
                team_condition = " AND r.reservation_category=2"

            # 5) 취소할 경기의 예약 목록 조회
            # r_category = 1 : 아직 예약 상태인 회원만 (이미 취소한 회원은 제외)
            # LEFT JOIN c_result_record : 출석 체크 전인 회원도 빠지지 않고 나옴 (출석 값은 None)
            # FOR UPDATE : 취소하는 동안 다른 요청(회원 취소, 재예약 등)이 이 예약들을 바꾸지 못하게 잠금
            sql = f"""
                SELECT DISTINCT r.r_seq, r.c_id_seq, r.r_check, cr.c_r_r_attendance
                FROM reservation AS r
                LEFT JOIN c_result_record AS cr
                    ON cr.c_id_seq = r.c_id_seq
                    AND cr.g_code = r.g_code
                    AND cr.c_r_r_code = {record_code}
                WHERE r.g_code = %s AND r.r_date = %s AND r.rs_time = %s AND r.r_category = %s
                    {team_condition}
                FOR UPDATE
            """
            cursor.execute(sql, (*record_params, g_code, cancel.r_date, cancel.rs_time, CATEGORY_RESERVED))
            reservations = cursor.fetchall()  # 결과 전체를 dict 목록으로 받음
            if not reservations:
                raise HTTPException(status_code=404, detail="취소할 예약이 없는 경기입니다.")

            capacity = ground["g_num"]                 # 구장 정원
            reservation_count = len(reservations)      # 현재 예약 인원 (빈자리 재예약 포함)
            # 결석(0)으로 출석 체크된 회원 수 (출석 체크 전 None은 노쇼가 아님)
            noshow_count = sum(1 for row in reservations if row["c_r_r_attendance"] == 0)
            attend_count = reservation_count - noshow_count  # 실제 참여 가능한 인원

            # 6) 취소 사유별 조건 확인
            if cancel.r_c_category == CANCEL_NO_SHOW:
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
            # 시설 문제(1)·우천·기상악화(2)는 인원 조건 없이 취소 가능

            # 수정 일 : 2026-10-30 / 작업자 : 양태건
            # 노쇼 취소가 가능한 경우에만 결석자 점수를 같은 트랜잭션에서 차감합니다.
            # 아직 취소 상태로 바꾸기 전의 유효 예약만 대상으로 하며 재요청은 중복 차감하지 않습니다.
            rating_changes = []
            if cancel.r_c_category == CANCEL_NO_SHOW:
                from .match_result_insert import apply_absence_penalties
                penalty_code = (str(cancel.team_code) if cancel.team_code is not None else
                    f"{ground['g_code']}_{cancel.r_date.strftime('%Y%m%d')}_{cancel.rs_time.replace(':', '')}00")
                rating_changes = apply_absence_penalties(cursor, penalty_code,
                    reservation_ids=sorted({row['r_seq'] for row in reservations}))

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
            # 중간 수정 작성자 - 신현진
            # 수정일 2026.10.28
            # str() : VARCHAR 컬럼이라 사유 코드를 '1' 같은 글자로 저장
            cursor.execute(sql, [CATEGORY_CANCELED, str(cancel.r_c_category), *r_seqs, CATEGORY_RESERVED])
            canceled_count = cursor.rowcount  # 실제로 취소된 예약 수

        connection.commit()  # 결제 삭제 + 예약 취소 상태 변경을 한 번에 확정
        canceled_code = (str(cancel.team_code) if cancel.team_code is not None else
            f"{ground['g_code']}_{cancel.r_date.strftime('%Y%m%d')}_{cancel.rs_time.replace(':', '')}00")
        operations._MATCHES.pop(canceled_code, None)
        return {
            "result": "OK",
            "m_id": manager["m_id"],                                         # 취소한 매니저
            "g_code": ground["g_code"],                                      # 구장코드
            "g_name": ground["g_name"],                                      # 구장명
            "r_date": cancel.r_date,                                         # 취소한 경기의 경기일
            "rs_time": cancel.rs_time,                                       # 경기 시작 시간
            "r_c_category": str(cancel.r_c_category),                        # 취소 사유 ('1' / '2' / '3', DB와 같은 글자)
            "r_c_category_name": CANCEL_CATEGORY_NAMES[str(cancel.r_c_category)],  # 취소 사유 이름
            "g_num": capacity,                                               # 구장 정원
            "canceled_count": canceled_count,                                # 취소된 예약 수
            "rating_changes": rating_changes,  # 결석 회원의 실제 전·후 점수와 변동
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
# 중간 수정 작성자 - 신현진
# 수정일 2026.10.28
# r_c_category IN ('1', '2', '3') : 매니저가 취소한 경기만 (회원이 직접 쓴 글로 저장된 회원 취소는 제외)
# GROUP BY : 회원별 예약 여러 줄을 경기(구장·날짜·시작시간·사유) 1줄로 묶음
# 예: /match/manage/cancel/manager01                  전체 취소 경기
#     /match/manage/cancel/manager01?r_c_category=3   노쇼 및 환불로 취소된 경기만
# 수정 일 : 2026-10-30 / 작업자 : 양태건
# 별도 이력 테이블 없이 기존 예약을 구장·날짜·시간·사유별로 묶습니다.
# 회원 소속팀은 현재 값이며, 취소 당시 팀명이라고 추정하지 않습니다.
def canceled_by_kind(cursor, m_id, kind, e_code=None, reason=None):
    # 수정 일 : 2026-10-30 / 작업자 : 양태건
    # 같은 경기·회원·구장의 취소 시점 이전 마지막 기록만 연결합니다.
    # 현재 점수에서 역산하지 않고 저장된 전후 이력으로 실제 차감액을 표시합니다.
    code_condition = (f"history.c_r_r_code={RECORD_CODE}" if kind == 'pickup' else
        """EXISTS (SELECT 1 FROM team_match tm
            WHERE DATE(tm.team_start)=r.r_date AND TIME(tm.team_start)=r.rs_time
              AND history.c_r_r_code=CAST(tm.team_code AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci)""")
    cursor.execute(f"""SELECT r.r_seq,r.g_code,g.g_name,g.g_num,r.r_date,r.rs_time,r.re_time,
            r.r_c_category,r.r_cancel_date,c.c_name,c.c_team,c.c_prefer_stock,
            cr.c_r_r_attendance AS attendance,cr.c_r_r_rating_before AS rating_before,
            cr.c_r_r_rating_after AS rating_after
        FROM reservation r JOIN ground g ON g.g_code=r.g_code
        LEFT JOIN customer c ON c.c_id_seq=r.c_id_seq
        LEFT JOIN c_result_record cr ON cr.c_r_r_seq=(
            SELECT MAX(history.c_r_r_seq) FROM c_result_record history
            WHERE history.c_id_seq=r.c_id_seq AND history.g_code=r.g_code
              AND history.c_r_r_date<=r.r_cancel_date AND {code_condition})
        WHERE r.r_category=%s AND {MANAGER_CANCEL_CONDITION}
          AND r.reservation_category=%s
          AND EXISTS (SELECT 1 FROM assign a WHERE a.g_code=r.g_code AND a.m_id=%s)
          {"AND r.r_c_category=%s" if reason is not None else ""}
        ORDER BY r.r_cancel_date DESC,r.r_date DESC,r.rs_time DESC,r.r_seq""",
        [CATEGORY_CANCELED, '1' if kind == 'pickup' else '2', m_id]
        + ([str(reason)] if reason is not None else []))
    sports = {'1': 'SOCCER', '2': 'BASKETBALL', '3': 'BASEBALL', '4': 'VOLLEYBALL'}
    groups = {}
    for row in cursor.fetchall():
        key = (row['g_code'], str(row['r_date']), format_time(row['rs_time']),
               format_time(row['re_time']), str(row['r_c_category']))
        if key not in groups:
            groups[key] = dict(g_code=row['g_code'], g_name=row['g_name'], g_num=row['g_num'],
                r_date=row['r_date'], rs_time=key[2], re_time=key[3], kind=kind,
                r_c_category=key[4], r_c_category_name=CANCEL_CATEGORY_NAMES.get(key[4], MEMBER_CANCEL_NAME),
                r_cancel_date=row['r_cancel_date'], members=[], _sports=set(), _seen=set())
        group = groups[key]
        if row['r_seq'] in group['_seen']:
            continue
        group['_seen'].add(row['r_seq'])
        group['_sports'].add(sports.get(str(row.get('c_prefer_stock'))))
        attendance = row.get('attendance')
        attendance = None if attendance is None else attendance in (1, '1', True)
        before, after = row.get('rating_before'), row.get('rating_after')
        change = (after - before if key[4] == '3' and attendance is False
                  and before is not None and after is not None else None)
        group['members'].append(dict(r_seq=row['r_seq'], name=row.get('c_name'),
                                     current_team=row.get('c_team'), attendance=attendance,
                                     rating_before=before, rating_after=after, rating_change=change,
                                     penalty_applied=change is not None and change < 0))
    result = []
    for group in groups.values():
        group['e_code'] = next(iter(group['_sports'])) if len(group['_sports']) == 1 else None
        group['canceled_count'] = len(group['members'])
        del group['_sports'], group['_seen']
        if e_code is None or group['e_code'] == e_code:
            result.append(group)
    return result


@router.get("/manage/cancel/{m_id}")
def select_canceled_matches(
    m_id: str,
    # ge=1, le=3 : 1~3 밖의 값이 오면 FastAPI가 자동으로 422 에러 처리
    r_c_category: int | None = Query(None, ge=1, le=3, description="1 시설 문제 / 2 우천·기상악화 / 3 노쇼 및 환불"),
    kind: Literal['pickup', 'team'] | None = None,
    e_code: Literal['SOCCER', 'BASKETBALL', 'BASEBALL', 'VOLLEYBALL'] | None = None,
    authorization: str = Header(default=""),
):
    if kind is not None and require_manager(authorization) != m_id:
        raise HTTPException(403, "로그인한 매니저의 취소 내역만 조회할 수 있습니다.")
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            manager = check_manager(cursor, m_id)
            if kind is not None:
                return {"m_id": manager['m_id'], "m_name": manager['m_name'],
                        "results": canceled_by_kind(cursor, m_id, kind, e_code, r_c_category)}

            # r / g 는 테이블 별칭 (reservation / ground)
            # EXISTS assign : 매니저에게 배정된 구장만 (배정 기록이 여러 개여도 경기 중복 방지)
            sql = f"""
                SELECT r.g_code, g.g_name, g.g_num,
                    r.r_date, r.rs_time, r.re_time, r.r_c_category,
                    COUNT(*) AS canceled_count,
                    MAX(r.r_cancel_date) AS r_cancel_date
                FROM reservation AS r
                INNER JOIN ground AS g ON g.g_code = r.g_code
                WHERE r.r_category = %s
                    AND {MANAGER_CANCEL_CONDITION}
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
                params.append(str(r_c_category))  # VARCHAR 컬럼과 같은 글자로 비교 (2026.10.28 신현진)
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
                "r_c_category": str(row["r_c_category"]),                    # 취소 사유 ('1' / '2' / '3')
                # str() : 글자 키로 이름을 찾고, 1 ~ 3 코드가 아니면 "회원 개인 사정" (2026.10.28 신현진)
                "r_c_category_name": CANCEL_CATEGORY_NAMES.get(str(row["r_c_category"]), MEMBER_CANCEL_NAME),  # 취소 사유 이름
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

# 최종 수정 일 : 2026-10-28

# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
