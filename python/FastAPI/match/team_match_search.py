# 작업자 : 신현진
# 최초 작업 일 : 2026-10-28

# 본사 팀 대 팀 매칭 조회 API (main.py에서 prefix="/match"로 등록되어 실제 주소 앞에 /match 가 붙음)
#   GET /match/team_match                     성사된 팀 매칭 목록 (홈·원정 팀, 경기 일시·구장·담당 매니저, 진행 상태, 결과)
#       ?status= scheduled 경기 예정 / waiting_result 결과 대기 / finished 경기 종료 (안 보내면 전체)
#       ?t_id= 특정 팀이 홈 또는 원정으로 참여한 매칭만 / ?keyword= 홈 또는 원정 팀 이름 검색
#   GET /match/team_match/{team_code}         팀 매칭 1건 상세 (두 팀 정보·전적 + 경기 결과 + 참가 회원별 기록)
# 조회만 하고 받는 값(body)이 없어서 BaseModel class 없음
# 팀 매칭 신청·수락은 회원 앱(Bootcamp_Gongin_User team_match_connect.py)에서 처리하고, 본사는 이 API로 조회만 함
#
# [사용 테이블]
#   team_match       : 성사된 팀 매치 (회원 앱에서 매칭 수락 시 저장)
#                      team_code 매치코드 / home_t_id 홈 팀(매칭신청 글을 쓴 팀) / away_t_id 원정 팀(신청한 팀)
#                      team_num 경기 인원(구장 수용인원) / team_start·team_end 경기 시작·종료 일시
#   team / team_create / team_captain_change : 팀 이름·로고·팀장 (팀장 기준은 팀 관리 API와 동일)
#   reservation      : 홈 팀 팀장이 한 구장대여 예약 → 경기 전에도 구장·담당 매니저를 보여줄 때 사용
#   t_result_record  : 팀 경기 결과 (팀마다 1줄씩 저장)
#                      t_r_r_m_code(경기코드) = team_match.team_code 로 두 팀 결과를 매치와 연결
#                      t_r_r_score "우리팀점수:상대팀점수" / m_id 담당 매니저 / g_code 경기 구장
#   c_result_record  : 참가 회원별 경기 기록 (c_r_r_code = team_code, 상세 조회에서만 사용)
#                      c_r_r_team 결과 등록 당시 팀 이름 / c_r_r_statcode "G:1,A:0,..." / c_r_r_attendance 출석
#                      c_r_r_rating_before / after 그 경기 반영 전 / 후 회원 점수 (2026.10.29 추가)
#   t_result_record.t_r_r_rating_after : 그 경기 반영 후 팀 점수 (2026.10.29 추가, 전 점수는 직전 기록의 후 점수)
#
# [팀장]
#   화면에 보여주는 팀장 = 현재 팀장 (team_captain_change의 가장 최근 1줄, 기록이 없으면 팀을 개설한 회원)
#   → 경기 당일 매니저가 연락할 수 있게 현재 팀장 이름·전화번호를 보냄
#
# [구장·담당 매니저] team_match에는 구장·매니저 컬럼이 없어서 아래 순서로 찾음
#   1) 경기 결과가 등록됐으면 결과 기록(t_result_record)의 구장·매니저
#   2) 결과 등록 전이면 홈 팀 팀장의 구장대여 예약(reservation)의 구장·매니저
#      회원 앱에서 매칭이 수락되면 team_start·team_end에 구장대여 예약의 날짜·시간이 그대로 들어가고
#      예약은 성사(r_check = 1)로 바뀌므로, 같은 날짜·시작 시간의 성사된 예약을 찾음
#      예약 후 경기 전에 팀장이 바뀌면 예약은 예전 팀장 ID로 남아 있어서
#      현재 팀장만이 아니라 "팀장 이력 전체"(팀 개설 회원 + 팀장 변경 기록)에서 예약한 회원을 찾음
#      (예전 팀장 ID는 예약을 찾는 데만 쓰고 응답에는 넣지 않음 → 화면에는 현재 팀장만 보임)
#   중간 수정 작성자 - 신현진
#   수정일 2026.10.28
#   공용 DB 기준으로 변경
#     - reservation에는 매니저 컬럼이 없어서, 구장대여 예약의 담당 매니저는
#       회원 앱과 같은 배정표(assign의 요일 a_day · 시간 a_time) 기준으로 찾음 (match_schedule.py 공용 SQL)
#     - 구장대여(reservation_category = 2)만 찾고, 취소 여부도 회원 앱과 같은 기준으로 확인
#
# [진행 상태] DB에 저장된 값이 아니라 경기 일시와 결과 기록으로 계산
#   scheduled      경기 예정 : 경기 시작 일시가 아직 안 됨 (일시가 비어 있어도 예정으로 봄)
#   waiting_result 결과 대기 : 경기 시작 일시가 지났는데 t_result_record에 결과가 아직 없음
#   finished       경기 종료 : t_result_record에 결과가 등록됨
import logging
from datetime import datetime
from typing import Optional

import pymysql
from fastapi import APIRouter, HTTPException, Query

from database import connect  # 공용 DB 연결 함수 (python/database.py)
# 팀 관리 API와 같은 기준으로 스코어·승패·팀 등급을 계산하기 위해 공용 함수를 가져옴
#   parse_score     : "52:47" → (52, 47)
#   match_result    : 우리팀 점수와 상대팀 점수로 승/무/패 결정
#   load_team_stats : 전체 팀 전적·승률·등급 계산 / empty_stats : 경기 기록이 없는 팀의 기본 전적
from FastAPI.management.team_management import empty_stats, load_team_stats, match_result, parse_score
# 중간 수정 작성자 - 신현진
# 수정일 2026.10.28
# 매니저 구장 일정 API와 같은 기준을 쓰기 위해 공용 값·SQL을 가져옴
#   ASSIGNED_MANAGER_SQL   : 예약 날짜·시간에 배정된 담당 매니저 (assign 요일·시간 기준)
#   NOT_CANCELED_CONDITION : 취소되지 않은 예약 조건 (회원 앱과 같은 기준)
#   RESERVATION_RENTAL     : 예약 구분 2 = 구장대여
from FastAPI.match.match_schedule import ASSIGNED_MANAGER_SQL, NOT_CANCELED_CONDITION, RESERVATION_RENTAL

# 이 파일의 API들을 담는 라우터 (main.py에서 prefix="/match"로 등록)
router = APIRouter()
logger = logging.getLogger(__name__)

# 진행 상태 값과 이름 (앱에서 배지로 바로 표시)
STATUS_SCHEDULED = "scheduled"
STATUS_WAITING_RESULT = "waiting_result"
STATUS_FINISHED = "finished"
STATUS_NAMES = {
    STATUS_SCHEDULED: "경기 예정",
    STATUS_WAITING_RESULT: "결과 대기",
    STATUS_FINISHED: "경기 종료",
}

# 팀 시작 점수 (match_result_insert.py RATING_START와 같은 값, 순환 import를 피하려고 따로 둠 - 2026.10.29 신현진)
TEAM_RATING_START = 1500

# 팀의 현재 팀장 ID를 구하는 SQL 조각 (팀 관리 API와 같은 기준)
#   COALESCE(A, B) : A가 NULL이면 B를 사용
#   A = team_captain_change의 가장 최근 팀장 / B = 팀을 개설한 회원(team_create.c_id_seq)
# {t_id} 자리에 홈 팀 / 원정 팀 컬럼이 들어감 (서버에서 정한 고정 문자열만 넣으므로 SQL 인젝션 위험 없음)
CAPTAIN_ID_SQL = """
    COALESCE(
        (
            SELECT cc.t_c_captain
            FROM team_captain_change AS cc
            WHERE cc.t_id = {t_id}
            ORDER BY cc.t_c_date DESC, cc.t_c_seq DESC
            LIMIT 1
        ),
        (SELECT tc.c_id_seq FROM team_create AS tc WHERE tc.t_id = {t_id})
    )
"""

# 홈 팀 팀장이 한 구장대여 예약번호를 찾는 SQL 조각 (위 [구장·담당 매니저] 2번)
#   r.r_date = DATE(경기 시작 일시) AND r.rs_time = TIME(경기 시작 일시) : 같은 날짜·시작 시간
#   r.r_check = 1 : 팀 매칭이 성사된 예약
#   중간 수정 작성자 - 신현진 / 수정일 2026.10.28
#   r.reservation_category = 2 : 구장대여 예약만 / NOT_CANCELED_CONDITION : 취소되지 않은 예약 (회원 앱 기준)
#   r.c_id_seq IN (...) : 홈 팀의 팀장 이력 전체 (팀 개설 회원 + 팀장 변경 기록의 모든 팀장)
#     UNION : 두 SELECT 결과를 하나로 합침 (같은 회원은 한 번만)
#   ORDER BY r_seq DESC LIMIT 1 : 혹시 여러 건이 걸려도 가장 최근 예약 1건만 사용 → 매치 1건당 1줄 유지
RENTAL_SEQ_SQL = f"""
    (
        SELECT r.r_seq
        FROM reservation AS r
        WHERE r.r_date = DATE(tm.team_start)
            AND r.rs_time = TIME(tm.team_start)
            AND r.r_check = 1
            AND r.reservation_category = {RESERVATION_RENTAL}
            AND {NOT_CANCELED_CONDITION}
            AND r.c_id_seq IN (
                SELECT tc2.c_id_seq FROM team_create AS tc2 WHERE tc2.t_id = tm.home_t_id
                UNION
                SELECT cc2.t_c_captain FROM team_captain_change AS cc2 WHERE cc2.t_id = tm.home_t_id
            )
        ORDER BY r.r_seq DESC
        LIMIT 1
    )
"""

# 팀 매칭 목록·상세에서 공통으로 쓰는 SELECT
# 안쪽 SELECT(base) : 매치 정보 + 홈/원정 팀 이름·로고 + 홈/원정 현재 팀장 ID + 구장대여 예약번호
#   tm / ht / awt 는 테이블 별칭 (team_match / team(홈) / team(원정))
#   LEFT JOIN team : 팀이 삭제된 경우에도 매치는 빠지지 않고 나옴 (팀 값은 None)
# 바깥 SELECT
#   hc / ac : 현재 팀장 (customer) → 이름·전화번호 (hc = 홈 팀장, ac = 원정 팀장)
#   rv / rg / rm : 구장대여 예약 (reservation) → 구장(ground)·담당 매니저(match_manager)
#   중간 수정 작성자 - 신현진 / 수정일 2026.10.28
#   rm : 예약에 매니저 컬럼이 없어서 배정표(assign) 기준으로 찾은 담당 매니저 (ASSIGNED_MANAGER_SQL)
#   LEFT JOIN : 예약을 못 찾아도 매치는 빠지지 않고 나옴 (구장·매니저 값은 None)
TEAM_MATCH_SELECT = f"""
    SELECT base.*,
        hc.c_name AS home_captain_name, hc.c_phone AS home_captain_phone,
        ac.c_name AS away_captain_name, ac.c_phone AS away_captain_phone,
        rv.g_code AS rental_g_code, rg.g_name AS rental_g_name,
        rm.m_id AS rental_m_id, rm.m_name AS rental_m_name
    FROM (
        SELECT tm.team_code, tm.team_num, tm.team_start, tm.team_end,
            (SELECT tc.c_category FROM team_create tc WHERE tc.t_id=tm.home_t_id LIMIT 1) AS home_category,
            (SELECT tc.c_category FROM team_create tc WHERE tc.t_id=tm.away_t_id LIMIT 1) AS away_category,
            tm.home_t_id, ht.t_name AS home_t_name, ht.t_logo AS home_t_logo,
            tm.away_t_id, awt.t_name AS away_t_name, awt.t_logo AS away_t_logo,
            {CAPTAIN_ID_SQL.format(t_id="tm.home_t_id")} AS home_captain_id,
            {CAPTAIN_ID_SQL.format(t_id="tm.away_t_id")} AS away_captain_id,
            {RENTAL_SEQ_SQL} AS rental_r_seq
        FROM team_match AS tm
        LEFT JOIN team AS ht ON ht.t_id = tm.home_t_id
        LEFT JOIN team AS awt ON awt.t_id = tm.away_t_id
    ) AS base
    LEFT JOIN customer AS hc ON hc.c_id_seq = base.home_captain_id
    LEFT JOIN customer AS ac ON ac.c_id_seq = base.away_captain_id
    LEFT JOIN reservation AS rv ON rv.r_seq = base.rental_r_seq
    LEFT JOIN ground AS rg ON rg.g_code = rv.g_code
    LEFT JOIN match_manager AS rm ON rm.m_id = {ASSIGNED_MANAGER_SQL.format(alias="rv")}
"""


# 매치코드 목록으로 팀 경기 결과를 한 번에 조회
# 반환 : {(경기코드, 팀ID): 결과 1줄} → 매치마다 홈/원정 팀 결과를 바로 꺼내 쓸 수 있음
# t_r_r_m_code는 문자열 컬럼이라 매치코드(숫자)를 문자열로 바꿔서 비교
def load_match_results(cursor, team_codes: list) -> dict:
    if not team_codes:
        return {}
    # IN (%s, %s, ...) : 매치코드 개수만큼 자리표시를 만들어서 한 번에 조회
    placeholders = ", ".join(["%s"] * len(team_codes))
    # placeholders는 "%s" 문자열만 들어가므로 f-string을 써도 SQL 인젝션 위험 없음
    # rr / mm / g 는 테이블 별칭 (t_result_record / match_manager / ground)
    # 중간 수정 작성자 - 신현진 / 수정일 2026.10.29
    # t_r_r_rating_after : 그 경기 반영 후 팀 점수
    # prev_count / prev_rating_after : 같은 팀의 직전 결과 기록 수 / 직전 기록의 후 점수 (= 이번 경기 전 점수)
    #   팀 기록은 결과 등록 순서대로 쌓이므로 t_r_r_seq가 작은 쪽이 먼저 반영된 경기
    cursor.execute(
        f"""
        SELECT rr.t_r_r_m_code, rr.t_id, rr.t_r_r_score, rr.t_r_r_date,
            rr.m_id, mm.m_name, rr.g_code, g.g_name, rr.t_r_r_rating_after, t.t_rating AS current_team_rating,
            (SELECT COUNT(DISTINCT all_rr.t_r_r_m_code) FROM t_result_record all_rr
             WHERE all_rr.t_id=rr.t_id AND all_rr.t_r_r_score IS NOT NULL) AS completed_match_count,
            (SELECT COUNT(*) FROM t_result_record AS pv
             WHERE pv.t_id = rr.t_id AND pv.t_r_r_seq < rr.t_r_r_seq) AS prev_count,
            (SELECT pv.t_r_r_rating_after FROM t_result_record AS pv
             WHERE pv.t_id = rr.t_id AND pv.t_r_r_seq < rr.t_r_r_seq
             ORDER BY pv.t_r_r_seq DESC LIMIT 1) AS prev_rating_after
        FROM t_result_record AS rr
        LEFT JOIN team AS t ON t.t_id=rr.t_id
        LEFT JOIN match_manager AS mm ON mm.m_id = rr.m_id
        LEFT JOIN ground AS g ON g.g_code = rr.g_code
        WHERE rr.t_r_r_m_code IN ({placeholders})
        ORDER BY rr.t_r_r_seq
        """,
        [str(code) for code in team_codes],
    )
    return {(row["t_r_r_m_code"], row["t_id"]): row for row in cursor.fetchall()}


# 중간 수정 작성자 - 신현진 / 수정일 2026.10.29
# 팀 결과 기록 1줄 → 그 경기 반영 전 / 후 팀 점수와 변동
#   전 점수 = 직전 기록의 후 점수 (직전 기록이 없으면 시작 점수 1500)
#   후 점수 또는 직전 기록의 후 점수가 NULL(컬럼 추가 전 기록)이면 변동은 None
def team_rating_change(record: Optional[dict]) -> dict:
    after = record["t_r_r_rating_after"] if record else None
    if record is None or record["prev_count"] == 0:
        before = TEAM_RATING_START if after is not None else None
    else:
        before = record["prev_rating_after"]
    # 수정 일 : 2026-10-30 / 작업자 : 양태건
    # 첫 경기이며 저장 후 점수가 없는 기존 기록만 초기 1500 대비 현재 팀 점수로 복원합니다.
    if record and after is None and record.get("completed_match_count") == 1 and record.get("prev_count") == 0:
        after = record.get("current_team_rating")
        before = TEAM_RATING_START if after is not None else None
    has_change = before is not None and after is not None
    return {
        "rating_before": before,                              # 경기 전 팀 점수
        "rating_after": after,                                # 경기 후 팀 점수
        "rating_change": after - before if has_change else None,  # 팀 점수 변동
    }


# 홈 팀 / 원정 팀 결과 기록으로 경기 결과 정리 (결과가 없으면 None)
# 스코어는 홈 팀 기록을 기준으로 쓰고, 홈 팀 기록이 없으면 원정 팀 기록을 뒤집어서 사용
#   예: 원정 팀 기록 "47:52" → 홈 52 / 원정 47
# 결과 기록의 구장·매니저는 경기 정보(venue)를 정할 때 쓰도록 record로 함께 돌려줌
def build_result(home_record: Optional[dict], away_record: Optional[dict]):
    record = home_record or away_record
    if record is None:
        return None, None

    home_score = away_score = None
    home_parsed = parse_score(home_record["t_r_r_score"]) if home_record else None
    away_parsed = parse_score(away_record["t_r_r_score"]) if away_record else None
    if home_parsed:
        home_score, away_score = home_parsed
    elif away_parsed:
        away_score, home_score = away_parsed  # 원정 팀 기준 스코어라서 순서를 뒤집음

    has_score = home_score is not None
    result = {
        "home_score": home_score,                                               # 홈 팀 점수
        "away_score": away_score,                                               # 원정 팀 점수
        "score": f"{home_score}:{away_score}" if has_score else None,           # 스코어 (홈:원정)
        "home_result": match_result(home_score, away_score) if has_score else None,  # 홈 팀 기준 승/무/패
        "away_result": match_result(away_score, home_score) if has_score else None,  # 원정 팀 기준 승/무/패
        "t_r_r_date": record["t_r_r_date"],                                     # 결과 등록일
        "home_rating": team_rating_change(home_record),                         # 홈 팀 점수 전 / 후 / 변동 (2026.10.29 신현진)
        "away_rating": team_rating_change(away_record),                         # 원정 팀 점수 전 / 후 / 변동
    }
    return result, record


# 중간 수정 작성자 - 신현진
# 수정일 2026.10.29
# 팀 경기의 참가 회원별 기록 → 홈 / 원정 팀별 목록 (결과 등록 전이면 빈 목록)
#   팀 구분 1) c_r_r_team(결과 등록 당시 팀 이름)이 홈 / 원정 팀 이름과 같은 쪽
#           2) 경기 뒤 팀 이름이 바뀌었으면 현재 두 팀 중 가입된 팀 (t_register)
#           3) 둘 다 아니면 other (팀을 탈퇴한 회원 등, 기록이 빠지지 않게 따로 보냄)
#   그 경기 반영 전 / 후 점수(c_r_r_rating_before / after)와 변동 + 현재 등급 점수(c_rating)·등급
#   컬럼 추가 전에 등록된 경기는 전 / 후 점수가 NULL → 변동도 None (앱에서 '변동 기록 없음')
def load_match_players(cursor, row: dict) -> dict:
    # match_result_insert.py가 이 파일의 TEAM_MATCH_SELECT를 가져다 쓰기 때문에
    # 파일 맨 위에서 가져오면 서로를 먼저 불러오려는 순환 import 에러가 나서 함수 안에서 가져옴
    from FastAPI.match.match_result_insert import RATING_START, rating_tier, unpack_statcode

    # register_t_id : 이 회원이 지금 가입된 팀 (홈 / 원정 중 하나, 없으면 None)
    cursor.execute(
        """
        SELECT cr.c_id_seq, c.c_name, c.c_rating, cr.c_r_r_team, cr.e_code,
            cr.c_r_r_statcode, cr.c_r_r_attendance, cr.c_r_r_rating_before, cr.c_r_r_rating_after,
            (SELECT COUNT(DISTINCT history.c_r_r_code) FROM c_result_record history
             WHERE history.c_id_seq=cr.c_id_seq AND history.c_r_r_score IS NOT NULL) AS completed_match_count,
            (
                SELECT tr.t_id
                FROM t_register AS tr
                WHERE tr.c_id_seq = cr.c_id_seq AND tr.t_id IN (%s, %s)
                LIMIT 1
            ) AS register_t_id
        FROM c_result_record AS cr
        LEFT JOIN customer AS c ON c.c_id_seq = cr.c_id_seq
        WHERE cr.c_r_r_code = %s
        ORDER BY cr.c_r_r_seq
        """,
        (row["home_t_id"], row["away_t_id"], str(row["team_code"])),
    )
    players = {"home": [], "away": [], "other": []}
    for item in cursor.fetchall():
        if row["home_t_name"] and item["c_r_r_team"] == row["home_t_name"]:
            side = "home"
        elif row["away_t_name"] and item["c_r_r_team"] == row["away_t_name"]:
            side = "away"
        elif item["register_t_id"] == row["home_t_id"]:
            side = "home"
        elif item["register_t_id"] == row["away_t_id"]:
            side = "away"
        else:
            side = "other"
        rating = item["c_rating"] if item["c_rating"] is not None else RATING_START
        before, after = item["c_r_r_rating_before"], item["c_r_r_rating_after"]
        # 수정 일 : 2026-10-30 / 작업자 : 양태건
        # 전체 완료 경기가 하나인 기존 첫 경기만 현재 점수 - 초기 1500으로 복원합니다.
        if before is None and after is None and item.get("completed_match_count") == 1 and item["c_rating"] is not None:
            before, after = RATING_START, item["c_rating"]
        has_change = before is not None and after is not None
        players[side].append({
            "c_id_seq": item["c_id_seq"],                         # 회원ID (종목별 ID)
            "c_name": item["c_name"],                             # 회원 이름 (탈퇴 등으로 없으면 None)
            "c_r_r_team": item["c_r_r_team"],                     # 결과 등록 당시 팀 이름
            "e_code": item["e_code"],                             # 종목코드
            "statcode": item["c_r_r_statcode"],                   # 스탯코드 원본
            "stats": unpack_statcode(item["c_r_r_statcode"]),     # 스탯 {"G": 1, "A": 0, ...}
            "attendance": bool(item["c_r_r_attendance"]),         # 출석 여부
            "rating_before": before,                              # 그 경기 반영 전 점수 (기록 없으면 None)
            "rating_after": after,                                # 그 경기 반영 후 점수
            "rating_change": after - before if has_change else None,  # 그 경기 점수 변동
            "tier_after": rating_tier(after) if after is not None else None,  # 그 경기 후 등급
            "c_rating": rating,                                   # 현재 등급 점수
            "tier": rating_tier(rating),                          # 현재 등급
        })
    return players


# 경기 일시와 결과로 진행 상태 계산 (위 [진행 상태] 기준)
def match_status(team_start, result: Optional[dict]) -> str:
    if result is not None:
        return STATUS_FINISHED
    if team_start is not None and team_start <= datetime.now():
        return STATUS_WAITING_RESULT
    return STATUS_SCHEDULED


# 경기 구장·담당 매니저 정리 (위 [구장·담당 매니저] 기준)
# 결과 기록이 있으면 결과 기록, 없으면 구장대여 예약 값을 사용 (둘 다 없으면 None)
def venue_to_dict(row: dict, result_record: Optional[dict]) -> dict:
    if result_record is not None:
        return {
            "g_code": result_record["g_code"],      # 경기 구장코드
            "g_name": result_record["g_name"],      # 경기 구장 이름
            "m_id": result_record["m_id"],          # 담당 매니저ID
            "m_name": result_record["m_name"],      # 담당 매니저 이름
            "venue_source": "result",               # 값 출처 : 경기 결과 기록
        }
    has_rental = row["rental_r_seq"] is not None
    return {
        "g_code": row["rental_g_code"],
        "g_name": row["rental_g_name"],
        "m_id": row["rental_m_id"],
        "m_name": row["rental_m_name"],
        "venue_source": "rental" if has_rental else None,  # 값 출처 : 구장대여 예약 (못 찾으면 None)
    }


# 홈 또는 원정 팀 정보 정리 (side = "home" / "away" → row의 컬럼 이름 앞부분)
# 팀장은 현재 팀장만 보냄 (경기 당일 매니저가 연락할 대상)
def side_team_to_dict(row: dict, side: str, stats: dict) -> dict:
    t_id = row[f"{side}_t_id"]
    team_stats = stats.get(t_id, empty_stats())
    return {
        "t_id": t_id,                                        # 팀ID
        "t_name": row[f"{side}_t_name"],                     # 팀 이름 (팀이 삭제됐으면 None)
        "t_logo": row[f"{side}_t_logo"],                     # 팀 로고
        "captain_id": row[f"{side}_captain_id"],             # 현재 팀장 회원ID
        "captain_name": row[f"{side}_captain_name"],         # 현재 팀장 이름
        "captain_phone": row[f"{side}_captain_phone"],       # 현재 팀장 전화번호 (경기 당일 연락용)
        "grade": team_stats["grade"],                        # 팀 등급 (팀 관리 API와 같은 승률 기준)
    }


# DB에서 받은 매치 1줄(dict) + 결과 + 전적 → 앱으로 보낼 JSON(dict)으로 정리
def team_match_to_dict(row: dict, results: dict, stats: dict) -> dict:
    code = str(row["team_code"])
    result, result_record = build_result(
        results.get((code, row["home_t_id"])),
        results.get((code, row["away_t_id"])),
    )
    status = match_status(row["team_start"], result)
    return {
        # 수정 일 : 2026-10-29 / 작업자 : 양태건
        # 프론트가 팀명으로 종목을 추측하지 않도록 실제 팀 종목을 반환합니다.
        "e_code": {"축구": "SOCCER", "배구": "VOLLEYBALL", "농구": "BASKETBALL", "야구": "BASEBALL"}.get(row.get("home_category")) if row.get("home_category") == row.get("away_category") else None,
        "team_code": row["team_code"],                       # 매치코드
        "team_num": row["team_num"],                         # 경기 인원 (구장 수용인원)
        "team_start": row["team_start"],                     # 경기 시작 일시
        "team_end": row["team_end"],                         # 경기 종료 일시
        "rental_r_seq": row["rental_r_seq"],                 # 연결된 구장대여 예약번호 (못 찾으면 None)
        **venue_to_dict(row, result_record),                 # 경기 구장·담당 매니저
        "status": status,                                    # 진행 상태 (scheduled / waiting_result / finished)
        "status_name": STATUS_NAMES[status],                 # 진행 상태 이름 (앱에서 바로 표시)
        "home_team": side_team_to_dict(row, "home", stats),  # 홈 팀 (매칭신청 글을 쓴 팀)
        "away_team": side_team_to_dict(row, "away", stats),  # 원정 팀 (매칭을 신청한 팀)
        "result": result,                                    # 경기 결과 (결과 등록 전이면 None)
    }


# 성사된 팀 매칭 목록 조회
# 예: /match/team_match
#     /match/team_match?status=finished
#     /match/team_match?t_id=5
#     /match/team_match?keyword=빅맨즈
@router.get("/team_match")
def select_team_matches(
    # pattern : 세 가지 상태 값이 아니면 FastAPI가 자동으로 422 에러 처리
    status: Optional[str] = Query(
        None,
        pattern=f"^({STATUS_SCHEDULED}|{STATUS_WAITING_RESULT}|{STATUS_FINISHED})$",
        description="scheduled 경기 예정 / waiting_result 결과 대기 / finished 경기 종료",
    ),
    t_id: Optional[int] = Query(None, description="홈 또는 원정으로 참여한 팀ID"),
    keyword: Optional[str] = Query(None, description="홈 또는 원정 팀 이름 검색"),
):
    connection = None
    try:
        connection = connect()  # DB 연결
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:  # SQL을 실행할 커서 (with가 끝나면 자동으로 닫힘)
            sql = TEAM_MATCH_SELECT
            conditions = []  # WHERE 뒤에 AND로 이어 붙일 조건들
            params = []      # %s 자리에 순서대로 들어갈 값
            if t_id is not None:
                conditions.append("(base.home_t_id = %s OR base.away_t_id = %s)")
                params.extend([t_id, t_id])
            if keyword and keyword.strip():
                # LIKE '%검색어%' : 앞뒤에 무엇이 와도 검색어가 포함되면 조회
                conditions.append("(base.home_t_name LIKE %s OR base.away_t_name LIKE %s)")
                like_keyword = f"%{keyword.strip()}%"
                params.extend([like_keyword, like_keyword])
            if conditions:
                sql += " WHERE " + " AND ".join(conditions)
            sql += " ORDER BY base.team_start DESC, base.team_code DESC"  # 경기 일시 최신순
            cursor.execute(sql, params)  # %s 자리에 값이 순서대로 들어감 (SQL 인젝션 방지)
            rows = cursor.fetchall()  # 결과 전체를 dict 목록으로 받음

            results = load_match_results(cursor, [row["team_code"] for row in rows])  # 매치별 경기 결과
            stats = load_team_stats(cursor)  # 전체 팀 전적·등급
        matches = [team_match_to_dict(row, results, stats) for row in rows]
        # 진행 상태는 DB 값이 아니라 위에서 계산한 값이라 SQL이 아닌 여기서 걸러냄
        if status is not None:
            matches = [match for match in matches if match["status"] == status]
        # 매칭이 하나도 없으면 빈 리스트 [] 가 나감 (에러 아님)
        return {
            "total": len(matches),  # 조회된 매칭 수
            "results": matches,
        }
    except pymysql.MySQLError:
        logger.exception("팀 매칭 목록 DB 조회 실패")
        raise HTTPException(status_code=500, detail="팀 매칭 조회 중 DB 오류가 발생했습니다.")
    except Exception:
        logger.exception("팀 매칭 목록 조회 실패")
        raise HTTPException(status_code=500, detail="팀 매칭 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료


# 팀 매칭 1건 상세 조회 (두 팀 정보·전적 + 경기 결과)
# 주의: "/team_match" 보다 아래에 있어야 하며, 주소의 team_code로 매치 1건만 조회
# 예: /match/team_match/3
@router.get("/team_match/{team_code}")
def select_team_match(team_code: int):
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            # 1) 매치 정보 + 홈/원정 팀 + 구장대여 예약
            cursor.execute(TEAM_MATCH_SELECT + " WHERE base.team_code = %s", (team_code,))  # 값이 1개여도 튜플이라 쉼표 필요
            row = cursor.fetchone()  # 1건만 받음 (없으면 None)
            if row is None:
                raise HTTPException(status_code=404, detail="존재하지 않는 팀 매칭입니다.")

            # 2) 두 팀의 팀원 수 (탈퇴 회원 제외, 팀 관리 API와 같은 기준)
            # GROUP BY t_id : 팀별로 묶어서 COUNT(*)로 인원을 셈
            cursor.execute(
                """
                SELECT tr.t_id, COUNT(*) AS member_count
                FROM t_register AS tr
                INNER JOIN customer AS c ON c.c_id_seq = tr.c_id_seq
                WHERE tr.t_id IN (%s, %s)
                    AND c.c_deletdate IS NULL
                GROUP BY tr.t_id
                """,
                (row["home_t_id"], row["away_t_id"]),
            )
            member_counts = {item["t_id"]: item["member_count"] for item in cursor.fetchall()}

            # 3) 경기 결과 + 전체 팀 전적
            results = load_match_results(cursor, [row["team_code"]])
            stats = load_team_stats(cursor)

            # 4) 참가 회원별 기록 (중간 수정 작성자 - 신현진 / 수정일 2026.10.29)
            players = load_match_players(cursor, row)

        match = team_match_to_dict(row, results, stats)
        # 상세에서는 두 팀의 팀원 수와 전적을 함께 보냄 (상대 전력 비교용)
        for side in ("home", "away"):
            team = match[f"{side}_team"]
            team_stats = stats.get(team["t_id"], empty_stats())
            team["member_count"] = member_counts.get(team["t_id"], 0)  # 팀원 수
            team["wins"] = team_stats["wins"]                          # 승
            team["draws"] = team_stats["draws"]                        # 무
            team["losses"] = team_stats["losses"]                      # 패
            team["win_rate"] = team_stats["win_rate"]                  # 승률 (경기 기록이 없으면 None)
            team["players"] = players[side]                            # 참가 회원별 기록 (결과 등록 전이면 [])
        match["other_players"] = players["other"]                      # 어느 팀인지 확인할 수 없는 회원 기록
        return match
    except HTTPException:
        raise  # 위에서 만든 404는 500으로 바뀌지 않게 그대로 전달
    except pymysql.MySQLError:
        logger.exception("팀 매칭 상세 DB 조회 실패")
        raise HTTPException(status_code=500, detail="팀 매칭 조회 중 DB 오류가 발생했습니다.")
    except Exception:
        logger.exception("팀 매칭 상세 조회 실패")
        raise HTTPException(status_code=500, detail="팀 매칭 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()

# 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
