# 작업자 : 신현진
# 최초 작업 일 : 2026-10-28

# 경기 매니저 구장 일정 조회 API (main.py에서 prefix="/match"로 등록되어 실제 주소 앞에 /match 가 붙음)
#   GET /match/schedule/{m_id}?r_date=2026-10-30      매니저가 그날 담당하는 구장의 시간대별 일정
#       ?g_code= 담당 구장 중 1곳만 보기 (안 보내면 그날 담당하는 구장 전체)
# 조회만 하고 받는 값(body)이 없어서 BaseModel class 없음
#
# [시간대별로 보여주는 것] 시간대마다 아래 중 하나
#   team_match 팀 대 팀 매칭 : 구장대여 예약으로 팀 매칭이 성사됨 (홈·원정 팀 이름)
#   rental     구장대여      : 회원(팀장)이 시간대 전체를 빌림 (팀 매칭 대기 중이거나 팀 자체 경기)
#   pickup     실력매칭      : 회원들이 자리를 1개씩 예약 (예약 인원 / 구장 정원)
#   empty      비어 있음     : 예약 없음
#
# [사용 테이블] 공용 DB(회원 앱과 같은 구조) 기준
#   assign       : 매니저 배정표 (a_day 요일 목록 예: '월,화,수' / a_time 시간 범위 예: '08:00~22:00')
#   reservation  : 예약 (reservation_category 1 실력매칭 / 2 구장대여, 매니저 컬럼은 없음)
#   team_match   : 성사된 팀 매치 (team_start = 구장대여 예약의 날짜·시작 시간)
#   team / team_create / team_captain_change : 팀 이름, 팀장 이력
#
# [담당 매니저 기준] 회원 앱(match/reservation.py find_assigned_manager)과 같은 기준
#   그날 요일이 a_day에 들어 있고, 시간대가 a_time 범위 안에 있는 배정
#   같은 구장·시간대에 배정이 여러 개면 가장 최근 배정(assign_seq가 큰 것)의 매니저가 담당
#   → 다른 매니저가 더 최근에 배정된 시간대는 이 매니저의 일정에서 빠짐
#
# [취소된 예약] 회원 앱(match/reservation_status.py category_condition)과 같은 기준으로 제외
#   r_c_category에 값이 있거나('' / '0' 제외) r_category = 2 이면 취소
#
# [팀 대 팀 매칭 찾기] team_match에는 구장 컬럼이 없어서 구장대여 예약으로 연결
#   같은 날짜·시작 시간의 team_match 중, 홈 팀의 팀장 이력(팀 개설 회원 + 팀장 변경 기록)에
#   구장대여 예약한 회원이 들어 있는 매치 (team_match_search.py와 같은 기준)
import logging
from datetime import date, timedelta
from typing import Optional

import pymysql
from fastapi import APIRouter, HTTPException, Query

from database import connect  # 공용 DB 연결 함수 (python/database.py)

# 이 파일의 API들을 담는 라우터 (main.py에서 prefix="/match"로 등록)
router = APIRouter()
logger = logging.getLogger(__name__)

# 예약 시간대 (회원 앱 match/reservation.py의 TIME_SLOTS와 같은 값, 08:00 ~ 24:00 2시간 단위)
TIME_SLOTS = {
    "08:00": "10:00", "10:00": "12:00", "12:00": "14:00", "14:00": "16:00",
    "16:00": "18:00", "18:00": "20:00", "20:00": "22:00", "22:00": "24:00",
}

# 요일 이름 (Python date.weekday() : 월요일 0 ~ 일요일 6, assign.a_day에 저장된 글자와 같음)
WEEKDAY_NAMES = ["월", "화", "수", "목", "금", "토", "일"]

# 예약 구분 (reservation.reservation_category)
RESERVATION_PICKUP = 1   # 실력매칭
RESERVATION_RENTAL = 2   # 구장대여

# 시간대 종류 값과 이름 (앱에서 배지로 바로 표시)
SLOT_TEAM_MATCH = "team_match"
SLOT_RENTAL = "rental"
SLOT_PICKUP = "pickup"
SLOT_EMPTY = "empty"
SLOT_NAMES = {
    SLOT_TEAM_MATCH: "팀 대 팀 매칭",
    SLOT_RENTAL: "구장대여",
    SLOT_PICKUP: "실력매칭",
    SLOT_EMPTY: "비어 있음",
}

# 취소되지 않은 예약 조건 (회원 앱 category_condition(False)와 같은 기준)
# TRIM(COALESCE(값, '')) : NULL과 앞뒤 공백을 빈 글자로 맞춘 뒤 비교
# 서버에서 정한 고정 문자열이라 SQL에 바로 넣어도 SQL 인젝션 위험 없음
NOT_CANCELED_CONDITION = (
    "NOT (TRIM(COALESCE(r.r_c_category, '')) NOT IN ('', '0') "
    "OR TRIM(COALESCE(r.r_category, '')) = '2')"
)

# 예약 1줄(r)의 날짜·시간에 배정된 담당 매니저ID를 구하는 SQL 조각 (위 [담당 매니저 기준])
#   ELT(WEEKDAY(날짜) + 1, '월', ...) : 날짜 → 요일 글자 (WEEKDAY는 월요일 0)
#   FIND_IN_SET(요일, '월,화,수') > 0 : a_day 목록에 그 요일이 들어 있는지 (REPLACE로 공백 제거)
#   SUBSTRING_INDEX(a_time, '~', 1 / -1) : '08:00~22:00' → 시작 '08:00' / 끝 '22:00'
#   TIME_TO_SEC : 시간을 초로 바꿔서 비교 (24:00 종료도 86400초로 비교됨)
# team_match_search.py에서도 구장대여 예약의 담당 매니저를 찾을 때 같이 사용
# {alias} 자리에는 서버에서 정한 테이블 별칭만 넣음
ASSIGNED_MANAGER_SQL = """
    (
        SELECT a.m_id
        FROM assign AS a
        WHERE a.g_code = {alias}.g_code
            AND FIND_IN_SET(
                ELT(WEEKDAY({alias}.r_date) + 1, '월', '화', '수', '목', '금', '토', '일'),
                REPLACE(a.a_day, ' ', '')
            ) > 0
            AND TIME_TO_SEC({alias}.rs_time) >= TIME_TO_SEC(TRIM(SUBSTRING_INDEX(a.a_time, '~', 1)))
            AND TIME_TO_SEC({alias}.re_time) <= TIME_TO_SEC(TRIM(SUBSTRING_INDEX(a.a_time, '~', -1)))
        ORDER BY a.assign_seq DESC
        LIMIT 1
    )
"""


# 시간 값 → "08:00" 형식 문자열로 통일
# DB 컬럼이 TIME 타입이면 pymysql이 timedelta로 주기 때문에 그대로 보내면 초(숫자)로 바뀜
# 문자열(varchar)로 저장된 경우에는 앞 5글자(HH:MM)만 사용
def format_time(value) -> str:
    if isinstance(value, timedelta):
        total_minutes = int(value.total_seconds()) // 60
        return f"{total_minutes // 60:02d}:{total_minutes % 60:02d}"
    return str(value)[:5]


# "08:00" → 480 (자정부터 몇 분인지) / "24:00" → 1440
# 형식이 잘못된 값은 None (배정 시간 범위를 읽지 못하면 그 배정은 건너뜀)
def to_minutes(text: str) -> Optional[int]:
    try:
        hour, minute = text.strip().split(":")[:2]
        return int(hour) * 60 + int(minute)
    except (AttributeError, ValueError):
        return None


# 배정 시간 범위 "08:00~22:00" → (480, 1320) / 읽지 못하면 None
def parse_assign_time(a_time: Optional[str]):
    if not a_time or "~" not in a_time:
        return None
    start_text, end_text = a_time.split("~", 1)
    start, end = to_minutes(start_text), to_minutes(end_text)
    if start is None or end is None:
        return None
    return start, end


# 구장·시간대마다 담당 매니저 정하기 (위 [담당 매니저 기준])
# assigns : 그날 요일에 배정된 해당 구장들의 배정 목록 (assign_seq 큰 순서로 정렬된 상태)
# 반환 : {(구장코드, 시작 시간): 담당 매니저ID}
def slot_managers(assigns: list) -> dict:
    managers = {}
    for assign in assigns:
        time_range = parse_assign_time(assign["a_time"])
        if time_range is None:
            continue
        window_start, window_end = time_range
        for rs_time, re_time in TIME_SLOTS.items():
            key = (assign["g_code"], rs_time)
            # 시간대 전체가 배정 시간 범위 안에 있어야 담당 (회원 앱과 같은 비교)
            inside = window_start <= to_minutes(rs_time) and to_minutes(re_time) <= window_end
            # setdefault : 최근 배정부터 보므로 처음 정해진 매니저를 그대로 유지
            if inside:
                managers.setdefault(key, assign["m_id"])
    return managers


# 시간대 1개의 일정 정리
# 같은 시간대에 실력매칭과 구장대여는 회원 앱에서 서로 막지만, 데이터가 겹쳐도 모두 보여줌
# 시간대 종류는 팀 대 팀 매칭 → 구장대여 → 실력매칭 → 비어 있음 순서로 정함
def slot_to_dict(rs_time: str, g_num, pickups: list, rental: Optional[dict], team_match: Optional[dict]) -> dict:
    if team_match is not None:
        slot_type = SLOT_TEAM_MATCH
    elif rental is not None:
        slot_type = SLOT_RENTAL
    elif pickups:
        slot_type = SLOT_PICKUP
    else:
        slot_type = SLOT_EMPTY
    return {
        "rs_time": rs_time,                                  # 시작 시간
        "re_time": TIME_SLOTS[rs_time],                      # 종료 시간
        "slot_type": slot_type,                              # 시간대 종류 (team_match / rental / pickup / empty)
        "slot_type_name": SLOT_NAMES[slot_type],             # 시간대 종류 이름 (앱에서 바로 표시)
        # 실력매칭 (예약이 없으면 None)
        "pickup": {
            "reservation_count": len(pickups),               # 예약 인원
            "g_num": g_num,                                  # 구장 정원
            # r_check : 정원이 차서 매치가 성사됐는지 (회원 앱에서 정원이 차면 같은 시간대 전체를 1로 바꿈)
            "is_full": any(bool(row["r_check"]) for row in pickups),
        } if pickups else None,
        # 구장대여 (대여가 없으면 None)
        "rental": {
            "r_seq": rental["r_seq"],                        # 구장대여 예약번호
            "c_id_seq": rental["c_id_seq"],                  # 대여한 회원 (팀장)
            "c_name": rental["c_name"],                      # 대여한 회원 이름
            "is_matched": bool(rental["r_check"]),           # 팀 매칭 성사 여부
        } if rental else None,
        # 팀 대 팀 매칭 (성사된 매칭이 없으면 None, 자세한 정보는 /match/team_match/{team_code})
        "team_match": team_match,
    }


# 매니저 구장 일정 조회 (그날 담당하는 구장 × 시간대)
# 예: /match/schedule/manager01?r_date=2026-10-30
#     /match/schedule/manager01?r_date=2026-10-30&g_code=1
@router.get("/schedule/{m_id}")
def select_manager_schedule(
    m_id: str,
    r_date: date = Query(description="조회할 날짜 (예: 2026-10-30)"),
    g_code: Optional[int] = Query(None, description="담당 구장 중 1곳만 보기 (안 보내면 전체)"),
):
    day_name = WEEKDAY_NAMES[r_date.weekday()]  # 조회 날짜의 요일 글자 (예: '목')
    connection = None
    try:
        connection = connect()  # DB 연결
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:  # SQL을 실행할 커서 (with가 끝나면 자동으로 닫힘)
            # 1) 매니저 확인
            cursor.execute("SELECT m_id, m_name FROM match_manager WHERE m_id = %s", (m_id,))
            manager = cursor.fetchone()  # 1건만 받음 (없으면 None)
            if manager is None:
                raise HTTPException(status_code=404, detail="매니저 ID가 존재하지 않습니다.")

            # 2) 그날 요일에 이 매니저가 배정된 구장
            # FIND_IN_SET(요일, a_day) > 0 : a_day 목록('월,화,수')에 그 요일이 들어 있는지 (REPLACE로 공백 제거)
            sql = """
                SELECT DISTINCT a.g_code, g.g_name, g.g_num
                FROM assign AS a
                INNER JOIN ground AS g ON g.g_code = a.g_code
                WHERE a.m_id = %s
                    AND FIND_IN_SET(%s, REPLACE(a.a_day, ' ', '')) > 0
            """
            params = [m_id, day_name]  # %s 자리에 순서대로 들어갈 값
            if g_code is not None:
                sql += " AND a.g_code = %s"
                params.append(g_code)
            sql += " ORDER BY a.g_code"
            cursor.execute(sql, params)  # %s 자리에 값이 순서대로 들어감 (SQL 인젝션 방지)
            grounds = cursor.fetchall()

            if not grounds:
                # 그날 배정된 구장이 없으면 빈 일정 (에러 아님)
                return {
                    "m_id": manager["m_id"],
                    "m_name": manager["m_name"],
                    "r_date": r_date,
                    "weekday": day_name,
                    "grounds": [],
                }

            ground_codes = [ground["g_code"] for ground in grounds]
            # IN (%s, %s, ...) : 구장 개수만큼 자리표시를 만들어서 한 번에 조회
            # placeholders는 "%s" 문자열만 들어가므로 f-string을 써도 SQL 인젝션 위험 없음
            placeholders = ", ".join(["%s"] * len(ground_codes))

            # 3) 그 구장들의 그날 요일 배정 전체 (다른 매니저 포함, 최근 배정부터)
            # → 시간대마다 실제 담당 매니저를 정해서 이 매니저 담당 시간대만 남김
            cursor.execute(
                f"""
                SELECT a.assign_seq, a.g_code, a.m_id, a.a_time
                FROM assign AS a
                WHERE a.g_code IN ({placeholders})
                    AND FIND_IN_SET(%s, REPLACE(a.a_day, ' ', '')) > 0
                ORDER BY a.assign_seq DESC
                """,
                [*ground_codes, day_name],
            )
            managers = slot_managers(cursor.fetchall())

            # 4) 그날 취소되지 않은 예약 (실력매칭 + 구장대여)
            # r / c 는 테이블 별칭 (reservation / customer)
            cursor.execute(
                f"""
                SELECT r.r_seq, r.g_code, r.rs_time, r.c_id_seq, c.c_name,
                    r.r_check, r.reservation_category
                FROM reservation AS r
                LEFT JOIN customer AS c ON c.c_id_seq = r.c_id_seq
                WHERE r.g_code IN ({placeholders})
                    AND r.r_date = %s
                    AND {NOT_CANCELED_CONDITION}
                ORDER BY r.r_seq
                """,
                [*ground_codes, r_date],
            )
            reservations = cursor.fetchall()

            # 5) 그날 시작하는 팀 매치 + 홈 팀 이름·원정 팀 이름
            # DATE(team_start) = 조회 날짜 : 그날 경기만
            cursor.execute(
                """
                SELECT tm.team_code, tm.home_t_id, ht.t_name AS home_t_name,
                    tm.away_t_id, awt.t_name AS away_t_name, tm.team_start
                FROM team_match AS tm
                LEFT JOIN team AS ht ON ht.t_id = tm.home_t_id
                LEFT JOIN team AS awt ON awt.t_id = tm.away_t_id
                WHERE DATE(tm.team_start) = %s
                """,
                (r_date,),
            )
            team_matches = cursor.fetchall()

            # 6) 그 팀 매치 홈 팀들의 팀장 이력 (팀 개설 회원 + 팀장 변경 기록의 모든 팀장)
            # UNION : 두 SELECT 결과를 하나로 합침 (같은 팀·회원은 한 번만)
            captains = {}  # {팀ID: {팀장이었던 회원ID, ...}}
            home_ids = sorted({row["home_t_id"] for row in team_matches})
            if home_ids:
                team_placeholders = ", ".join(["%s"] * len(home_ids))
                cursor.execute(
                    f"""
                    SELECT tc.t_id, tc.c_id_seq AS captain_id FROM team_create AS tc
                    WHERE tc.t_id IN ({team_placeholders})
                    UNION
                    SELECT cc.t_id, cc.t_c_captain AS captain_id FROM team_captain_change AS cc
                    WHERE cc.t_id IN ({team_placeholders})
                    """,
                    [*home_ids, *home_ids],
                )
                for row in cursor.fetchall():
                    captains.setdefault(row["t_id"], set()).add(row["captain_id"])

        # 예약을 (구장코드, 시작 시간)별로 나눔
        pickups_by_slot = {}  # {(구장코드, 시작 시간): [실력매칭 예약, ...]}
        rentals_by_slot = {}  # {(구장코드, 시작 시간): 구장대여 예약 1건}
        for row in reservations:
            key = (row["g_code"], format_time(row["rs_time"]))
            if row["reservation_category"] == RESERVATION_RENTAL:
                rentals_by_slot.setdefault(key, row)  # 시간대마다 대여는 1건 (먼저 저장된 예약 사용)
            else:
                pickups_by_slot.setdefault(key, []).append(row)

        # 구장대여 예약 → 성사된 팀 매치 연결 (위 [팀 대 팀 매칭 찾기])
        def find_team_match(rental: Optional[dict], rs_time: str) -> Optional[dict]:
            if rental is None:
                return None
            for match in team_matches:
                same_time = format_time(match["team_start"].time()) == rs_time if match["team_start"] else False
                if same_time and rental["c_id_seq"] in captains.get(match["home_t_id"], set()):
                    return {
                        "team_code": match["team_code"],             # 매치코드
                        "home_t_id": match["home_t_id"],             # 홈 팀ID (구장대여한 팀)
                        "home_t_name": match["home_t_name"],         # 홈 팀 이름
                        "away_t_id": match["away_t_id"],             # 원정 팀ID (신청한 팀)
                        "away_t_name": match["away_t_name"],         # 원정 팀 이름
                    }
            return None

        result_grounds = []
        for ground in grounds:
            slots = []
            for rs_time in TIME_SLOTS:
                key = (ground["g_code"], rs_time)
                # 이 매니저가 담당하는 시간대만 (배정 시간 밖이거나 다른 매니저 담당이면 제외)
                if managers.get(key) != m_id:
                    continue
                rental = rentals_by_slot.get(key)
                slots.append(slot_to_dict(
                    rs_time, ground["g_num"], pickups_by_slot.get(key, []),
                    rental, find_team_match(rental, rs_time),
                ))
            result_grounds.append({
                "g_code": ground["g_code"],      # 구장코드
                "g_name": ground["g_name"],      # 구장명
                "g_num": ground["g_num"],        # 구장 정원
                "slots": slots,                  # 담당 시간대별 일정 (시작 시간 순)
            })
        return {
            "m_id": manager["m_id"],             # 매니저ID
            "m_name": manager["m_name"],         # 매니저 이름
            "r_date": r_date,                    # 조회 날짜
            "weekday": day_name,                 # 요일 (assign.a_day 기준 글자)
            "grounds": result_grounds,           # 담당 구장별 일정
        }
    except HTTPException:
        raise  # 위에서 만든 404는 500으로 바뀌지 않게 그대로 전달
    except pymysql.MySQLError:
        logger.exception("매니저 구장 일정 DB 조회 실패")
        raise HTTPException(status_code=500, detail="구장 일정 조회 중 DB 오류가 발생했습니다.")
    except Exception:
        logger.exception("매니저 구장 일정 조회 실패")
        raise HTTPException(status_code=500, detail="구장 일정 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료

# 최종 수정 일 : 2026-10-28
