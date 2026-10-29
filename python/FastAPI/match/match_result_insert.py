# 작업자 : 신현진
# 최초 작업 일 : 2026-10-29

# 경기 결과 등록 + 회원·팀 등급 점수 반영 API (main.py에서 prefix="/match"로 등록되어 실제 주소 앞에 /match 가 붙음)
#   POST /match/team_result/{m_id}/{team_code}    담당 매니저가 팀 대 팀 매칭 결과 등록
#        → 팀 스코어(t_result_record) + 회원별 스탯(c_result_record) 저장, 회원 c_rating · 팀 t_rating 반영
#   GET  /match/rating/stat_keys                   종목별 스탯 키·가중치 표 (앱의 기록 입력 화면용)
#
# 실력매칭 결과는 경기 진행 API(match_operations.py)에서 저장하고,
# 결과 등록이 끝날 때 이 파일의 apply_member_ratings()를 불러서 같은 기준으로 회원 점수를 반영함
#
# [회원 등급 점수 c_rating] 회원 ID가 종목마다 다르므로(아이디_01 축구 ~ _04 배구) 종목별로 따로 쌓임
#   가입 시 1500 (비기너 1, DB 기본값) / 최저 1000 / 프로 3000 이상
#   상대 점수   = 상대 팀 참가 회원들의 평균 c_rating
#   기대 승률 E = 1 / (1 + 10^((상대 점수 - 내 점수) / 400))
#   승패 점수   = 40 × (결과 - E)        결과 : 승 1 / 무 0.5 / 패 0
#                 1200점 미만이면 얻을 때 ×1.5, 잃을 때 ×0.5 (낮은 구간에서 빨리 올라오게)
#   개인 보너스 = 종목별 (스탯 개수 × 가중치) 합계, 최대 ±10
#   새 점수     = max(1000, 이전 점수 + 승패 점수 + 개인 보너스)
#
# [팀 등급 점수 t_rating] FIFA 랭킹 방식 (친선 매치 위주라 중요도 I를 FIFA 친선전보다 높게 설정)
#   기대 승률 We = 1 / (10^(-(우리 팀 점수 - 상대 팀 점수) / 600) + 1)
#   새 팀 점수   = 이전 팀 점수 + 40 × (결과 - We)
#
# [두 번 반영 방지] c_rating / t_rating을 바로 업데이트
#   결과 저장과 점수 반영을 한 트랜잭션으로 처리하고, 같은 경기의 결과가 이미 있으면 등록을 막음
#   → 결과 확정 후에는 수정하지 않음 (경기 진행 API와 같은 규칙)
#
# 중간 수정 작성자 - 신현진 / 수정일 2026.10.29
# [경기별 점수 기록] 지난 경기의 점수 변동·내 수준 통계(점수 추이)를 볼 수 있게 결과 기록에 함께 저장
#   c_result_record.c_r_r_rating_before / c_r_r_rating_after : 회원의 그 경기 반영 전 / 후 점수 (변동 = 후 - 전)
#   t_result_record.t_r_r_rating_after                       : 팀의 그 경기 반영 후 점수
#     팀 기록은 결과 등록 순서대로 쌓이므로 직전 기록의 후 점수 = 이번 경기 전 점수 (직전 기록이 없으면 시작 점수)
#   컬럼 추가 전 기록은 NULL (변동 기록 없음)
#
# [팀 매치 경기코드] t_result_record.t_r_r_m_code / c_result_record.c_r_r_code = team_match.team_code (숫자 글자)
#   실력매칭 경기코드는 항상 "구장_날짜_시간" 형식(밑줄 포함)이라 겹치지 않음 (team_match_search.py와 같은 기준)
import logging
import math
import re
from datetime import datetime
from typing import Optional

import pymysql
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from database import connect  # 공용 DB 연결 함수 (python/database.py)
# 팀 매칭 조회와 같은 기준으로 홈·원정 팀, 구장대여 예약의 구장·담당 매니저를 가져옴
#   TEAM_MATCH_SELECT : 팀 매칭 + 홈/원정 팀 + 구장대여 예약(구장·배정표 기준 담당 매니저)
from FastAPI.match.team_match_search import TEAM_MATCH_SELECT

# 이 파일의 API들을 담는 라우터 (main.py에서 prefix="/match"로 등록)
router = APIRouter()
logger = logging.getLogger(__name__)

# ------------------------------------------------------------
# 종목별 스탯 키 · 가중치
# ------------------------------------------------------------

# 종목코드(e_code)별 스탯 키 (순서대로 스탯코드 "G:1,A:0,..." 를 만듦)
#   (키, 이름, 가중치) : 가중치가 음수면 마이너스 요인 (실책·범실·찬스미스 등)
STAT_KEYS = {
    "SOCCER": [
        ("G", "득점", 3), ("A", "어시스트", 2), ("S", "슈팅", 0.5),
        ("F", "파울", -0.5), ("M", "찬스미스", -1), ("E", "실책", -2),
        ("Y", "경고", -2), ("R", "퇴장", -5),
    ],
    "BASKETBALL": [
        # 농구 득점은 한 경기에 20점 이상도 나와서 1점당 가중치를 작게 둠
        ("P", "득점", 0.2), ("T", "3점", 0.5), ("A", "어시스트", 1), ("RB", "리바운드", 0.5),
        ("F", "파울", -0.5), ("TO", "턴오버", -1),
    ],
    "VOLLEYBALL": [
        ("P", "득점", 0.5), ("B", "블로킹", 1), ("SA", "서브에이스", 1.5),
        ("F", "파울", -0.5), ("E", "범실", -1),
    ],
    "BASEBALL": [
        # 홈런은 안타·본인 득점·타점이 함께 기록되므로 홈런 자체 가중치는 낮게 둠 (솔로 홈런 합계 +5.5)
        # RBI 타점 : 타자가 불러들인 점수 / RS 득점 : 본인이 홈인한 점수 (팀 점수 = 팀 RS 합계)
        ("H", "안타", 1.5), ("HR", "홈런", 2), ("RBI", "타점", 1), ("RS", "득점", 1), ("BB", "볼넷", 0.5),
        ("O", "아웃", -0.3), ("K", "삼진", -1), ("E", "실책", -2),
    ],
}

# 종목코드 → 종목 이름 (앱 표시용)
SPORT_NAMES = {"SOCCER": "축구", "BASKETBALL": "농구", "VOLLEYBALL": "배구", "BASEBALL": "야구"}

# 팀 종목(team_create.c_category) → 종목코드
SPORT_CODES = {"축구": "SOCCER", "농구": "BASKETBALL", "야구": "BASEBALL", "배구": "VOLLEYBALL"}

# 회원 ID 끝 번호 → 종목코드 (회원 앱 SPORT_BY_SEQUENCE {1 축구, 2 농구, 3 야구, 4 배구}와 같은 기준)
SPORT_BY_SEQUENCE = {"1": "SOCCER", "2": "BASKETBALL", "3": "BASEBALL", "4": "VOLLEYBALL"}
CUSTOMER_SEQUENCE_PATTERN = re.compile(r"^.+_0([1-4])$")

# 스탯코드 컬럼 길이 (c_r_r_statcode VARCHAR(50))
STATCODE_MAX_LENGTH = 50

# ------------------------------------------------------------
# 점수 계산 기준 값
# ------------------------------------------------------------
RATING_START = 1500           # 가입 시작 점수 (비기너 1, DB 기본값)
RATING_FLOOR = 1000           # 최저 점수
RATING_K = 40                 # 회원 승패 점수 변동 폭 (동급끼리 승 +20 / 패 -20)
RATING_SCALE = 400            # 회원 기대 승률 계산의 점수 차 기준
LOW_RATING_LINE = 1200        # 이 점수 미만이면 낮은 구간 보정
LOW_GAIN_RATE = 1.5           # 낮은 구간에서 얻는 점수 배율
LOW_LOSS_RATE = 0.5           # 낮은 구간에서 잃는 점수 배율
BONUS_LIMIT = 10              # 개인 보너스 최대 ±10
TEAM_IMPORTANCE = 40          # 팀 점수 중요도 I (FIFA 친선전 5~10보다 높게)
TEAM_SCALE = 600              # 팀 기대 승률 계산의 점수 차 기준 (FIFA 값)

# 등급 구간 (점수가 위에서부터 처음으로 기준 이상이 되는 등급)
# 1000 ~ 1199 는 보호 구간이라 루키 1로 표시
TIERS = [
    (3000, "프로"),
    (2700, "세미프로 5"), (2600, "세미프로 4"), (2500, "세미프로 3"), (2400, "세미프로 2"), (2300, "세미프로 1"),
    (2200, "아마추어 5"), (2100, "아마추어 4"), (2000, "아마추어 3"), (1900, "아마추어 2"), (1800, "아마추어 1"),
    (1700, "비기너 3"), (1600, "비기너 2"), (1500, "비기너 1"),
    (1400, "루키 3"), (1300, "루키 2"),
]
TIER_LOWEST = "루키 1"


# 결과 값 (승 1 / 무 0.5 / 패 0)
def result_value(my_score: int, opponent_score: int) -> float:
    if my_score > opponent_score:
        return 1.0
    if my_score == opponent_score:
        return 0.5
    return 0.0


# 결과 이름 (응답 표시용)
def result_name(value: float) -> str:
    return {1.0: "승", 0.5: "무", 0.0: "패"}[value]


# 반올림 (0.5는 올림, 음수도 -2.5 → -2 처럼 큰 쪽으로)
# Python round()는 2.5 → 2 처럼 짝수 쪽으로 반올림해서 직접 계산
def round_half_up(value: float) -> int:
    return math.floor(value + 0.5)


# 점수 → 등급 이름 (예: 1650 → "비기너 2")
def rating_tier(rating: int) -> str:
    for min_rating, name in TIERS:
        if rating >= min_rating:
            return name
    return TIER_LOWEST


# 종목 스탯 dict → 스탯코드 문자열 (예: {"G": 1, "A": 2} → "G:1,A:2,S:0,F:0,M:0,E:0,Y:0,R:0")
# 표에 있는 키 순서대로 만들고, 보내지 않은 키는 0
def pack_statcode(e_code: str, stats: dict) -> str:
    return ",".join(f"{key}:{int(stats.get(key, 0))}" for key, _, _ in STAT_KEYS[e_code])


# 스탯코드 문자열 → dict (예: "G:1,A:0" → {"G": 1, "A": 0}), 경기 진행 API에서 저장한 값을 읽을 때 사용
# 형식이 잘못된 조각은 건너뜀
def unpack_statcode(statcode: Optional[str]) -> dict:
    stats = {}
    for part in (statcode or "").split(","):
        key, _, value = part.partition(":")
        if key.strip() and value.strip().isdigit():
            stats[key.strip()] = int(value)
    return stats


# 개인 보너스 = 종목별 (스탯 개수 × 가중치) 합계, 최대 ±10
def stat_bonus(e_code: str, stats: dict) -> float:
    total = sum(stats.get(key, 0) * weight for key, _, weight in STAT_KEYS[e_code])
    return max(-BONUS_LIMIT, min(BONUS_LIMIT, total))


# 회원 1명의 새 점수 계산 (위 [회원 등급 점수] 공식)
# 반환 : (새 점수, 승패 점수, 개인 보너스)
def member_new_rating(rating: int, opponent_average: float, result: float, bonus: float):
    expected = 1 / (1 + 10 ** ((opponent_average - rating) / RATING_SCALE))
    change = RATING_K * (result - expected)
    if rating < LOW_RATING_LINE:
        change *= LOW_GAIN_RATE if change > 0 else LOW_LOSS_RATE
    new_rating = max(RATING_FLOOR, round_half_up(rating + change + bonus))
    return new_rating, change, bonus


# 팀 1개의 새 점수 계산 (위 [팀 등급 점수] FIFA 공식)
def team_new_rating(rating: int, opponent_rating: int, result: float) -> int:
    expected = 1 / (10 ** (-(rating - opponent_rating) / TEAM_SCALE) + 1)
    return round_half_up(rating + TEAM_IMPORTANCE * (result - expected))


# ------------------------------------------------------------
# 회원 등급 점수 반영 (실력매칭 · 팀 매치 공용)
# ------------------------------------------------------------

# 두 팀의 참가 회원 점수를 한 번에 계산하고 customer.c_rating을 업데이트
# 결과를 저장하는 쪽의 트랜잭션 안에서 호출해야 함 (commit은 호출한 쪽에서)
#   e_code      : 종목코드 (SOCCER / BASKETBALL / VOLLEYBALL / BASEBALL)
#   team_a / b  : [{"c_id_seq": 회원ID, "stats": {"G": 1, ...}}, ...]  (출석한 참가 회원만)
#   score_a / b : 팀 최종 점수
# 반환 : 회원별 {c_id_seq, team, result, rating_before, rating_after, rating_change, elo_change, bonus, tier}
#
# 경기 진행 API(match_operations.py)에서는 결과 등록(publish) 저장이 끝난 뒤 아래처럼 호출
#   apply_member_ratings(cursor, "SOCCER",
#       [{"c_id_seq": 회원ID, "stats": unpack_statcode(저장한 스탯코드)} for A팀 출석 회원], ...B팀...,
#       scores["A"], scores["B"], match_code=경기코드)
#   match_code : 경기코드를 주면 그 경기의 회원 결과 기록(c_result_record)에 반영 전 / 후 점수도 저장
#                (기록 줄이 먼저 저장돼 있어야 함, 2026.10.29 신현진)
#                결석 회원 기록(같은 경기코드, 점수가 빈 줄)은 전 = 후 = 현재 c_rating으로 저장 (2026.10.29 신현진)
def apply_member_ratings(cursor, e_code: str, team_a: list, team_b: list, score_a: int, score_b: int,
                         match_code: Optional[str] = None) -> list:
    if e_code not in STAT_KEYS:
        raise HTTPException(status_code=422, detail="지원하지 않는 종목코드입니다.")
    players = team_a + team_b
    if not team_a or not team_b:
        raise HTTPException(status_code=422, detail="두 팀 모두 참가 회원이 1명 이상 있어야 합니다.")

    # 1) 참가 회원 현재 점수 (FOR UPDATE : 반영하는 동안 다른 요청이 같은 회원 점수를 바꾸지 못하게 잠금)
    ids = [player["c_id_seq"] for player in players]
    placeholders = ", ".join(["%s"] * len(ids))
    # placeholders는 "%s" 문자열만 들어가므로 f-string을 써도 SQL 인젝션 위험 없음
    cursor.execute(
        f"SELECT c_id_seq, c_rating FROM customer WHERE c_id_seq IN ({placeholders}) FOR UPDATE",
        ids,
    )
    ratings = {row["c_id_seq"]: row["c_rating"] for row in cursor.fetchall()}
    missing = [c_id for c_id in ids if c_id not in ratings]
    if missing:
        raise HTTPException(status_code=404, detail=f"존재하지 않는 회원입니다: {', '.join(missing)}")

    # 2) 팀별 평균 점수 (점수가 비어 있으면 시작 점수로 계산)
    def average(team: list) -> float:
        return sum(ratings[p["c_id_seq"]] or RATING_START for p in team) / len(team)

    averages = {"A": average(team_a), "B": average(team_b)}
    results = {"A": result_value(score_a, score_b), "B": result_value(score_b, score_a)}

    # 3) 회원별 새 점수 계산 + 업데이트
    changes = []
    for side, team, opponent in (("A", team_a, "B"), ("B", team_b, "A")):
        for player in team:
            before = ratings[player["c_id_seq"]] or RATING_START
            bonus = stat_bonus(e_code, player.get("stats", {}))
            after, elo_change, bonus = member_new_rating(before, averages[opponent], results[side], bonus)
            cursor.execute(
                "UPDATE customer SET c_rating = %s WHERE c_id_seq = %s",
                (after, player["c_id_seq"]),
            )
            if match_code is not None:
                # 그 경기의 회원 기록에 반영 전 / 후 점수 저장 (2026.10.29 신현진)
                cursor.execute(
                    """
                    UPDATE c_result_record SET c_r_r_rating_before = %s, c_r_r_rating_after = %s
                    WHERE c_r_r_code = %s AND c_id_seq = %s
                    """,
                    (before, after, match_code, player["c_id_seq"]),
                )
            changes.append({
                "c_id_seq": player["c_id_seq"],          # 회원ID
                "team": side,                            # A / B (팀 매치는 A = 홈, B = 원정)
                "result": result_name(results[side]),    # 승 / 무 / 패
                "rating_before": before,                 # 경기 전 점수
                "rating_after": after,                   # 경기 후 점수
                "rating_change": after - before,         # 점수 변동 (최저 점수 보정 포함)
                "elo_change": round(elo_change, 1),      # 승패 점수 (낮은 구간 보정 포함)
                "bonus": round(bonus, 1),                # 개인 보너스 (±10 이내)
                "tier_before": rating_tier(before),      # 경기 전 등급
                "tier_after": rating_tier(after),        # 경기 후 등급
            })

    # 중간 수정 작성자 - 신현진
    # 수정일 2026.10.29
    # 4) 결석한 회원 기록에도 전 / 후 점수 저장 (점수 미반영 → 전 = 후 = 그 회원의 현재 c_rating)
    #    출석 회원은 위 3)에서 이미 저장했으므로, 그 경기 기록 중 점수가 아직 비어 있는 줄이 결석 회원
    #    DB 기본값(1500)을 쓰면 실제 점수가 다른 회원도 1500으로 보이므로 회원의 현재 점수로 채움
    #    (회원 앱의 점수 변동 목록·추이 그래프에 결석 경기도 실제 점수로 이어서 표시)
    #    팀 매치 결과 등록은 참가 회원 기록만 저장하므로 해당하는 줄이 없음
    if match_code is not None:
        cursor.execute(
            """
            UPDATE c_result_record AS r
            INNER JOIN customer AS c ON c.c_id_seq = r.c_id_seq
            SET r.c_r_r_rating_before = COALESCE(c.c_rating, %s),
                r.c_r_r_rating_after = COALESCE(c.c_rating, %s)
            WHERE r.c_r_r_code = %s
                AND r.c_r_r_rating_before IS NULL AND r.c_r_r_rating_after IS NULL
            """,
            (RATING_START, RATING_START, match_code),
        )
    return changes


# ------------------------------------------------------------
# 팀 매치 결과 등록
# ------------------------------------------------------------

# 참가 회원 1명의 기록 (스탯은 종목 키만 사용, 보내지 않은 키는 0)
class PlayerRecord(BaseModel):
    c_id_seq: str = Field(min_length=4, max_length=50, description="참가 회원ID (해당 종목 ID, 예: hong_02)")
    # ge=0 을 dict 값마다 걸 수 없어서 아래 검사 함수에서 음수·모르는 키를 확인
    stats: dict[str, int] = Field(default_factory=dict, description='스탯 개수 (예: {"P": 18, "T": 2, "TO": 1})')


# 팀 매치 결과 등록 요청 body
class TeamMatchResult(BaseModel):
    home_score: int = Field(ge=0, description="홈 팀 최종 점수")
    away_score: int = Field(ge=0, description="원정 팀 최종 점수")
    home_players: list[PlayerRecord] = Field(min_length=1, description="홈 팀 참가 회원")
    away_players: list[PlayerRecord] = Field(min_length=1, description="원정 팀 참가 회원")


# 참가 회원 기록 확인 (종목에 없는 키, 음수, 다른 종목 회원ID, 같은 회원 중복)
def validate_players(e_code: str, home: list, away: list):
    allowed = {key for key, _, _ in STAT_KEYS[e_code]}
    seen = set()
    for player in home + away:
        c_id = player.c_id_seq.strip()
        matched = CUSTOMER_SEQUENCE_PATTERN.fullmatch(c_id)
        if matched is None or SPORT_BY_SEQUENCE[matched.group(1)] != e_code:
            raise HTTPException(status_code=422, detail=f"{c_id} : 이 경기 종목의 회원ID가 아닙니다.")
        if c_id in seen:
            raise HTTPException(status_code=422, detail=f"{c_id} : 같은 회원이 두 번 들어 있습니다.")
        seen.add(c_id)
        unknown = set(player.stats) - allowed
        if unknown:
            raise HTTPException(status_code=422, detail=f"{c_id} : 이 종목에 없는 스탯 키입니다 ({', '.join(sorted(unknown))}).")
        if any(value < 0 for value in player.stats.values()):
            raise HTTPException(status_code=422, detail=f"{c_id} : 스탯 개수는 0 이상이어야 합니다.")


# 팀 매치 결과 등록 (담당 매니저)
# 처리 순서 : 매니저·매칭 확인 → 참가 회원 확인 → 팀 점수 반영 → 결과 저장 → 회원 점수 반영 (한 트랜잭션)
# 예: POST /match/team_result/manager01/3
#     body {"home_score": 52, "away_score": 47,
#           "home_players": [{"c_id_seq": "hong_02", "stats": {"P": 18, "T": 2}}], "away_players": [...]}
@router.post("/team_result/{m_id}/{team_code}")
def insert_team_match_result(m_id: str, team_code: int, body: TeamMatchResult):
    connection = None
    try:
        connection = connect()  # DB 연결
        # DictCursor : 결과를 (값, 값) 튜플 대신 {"컬럼명": 값} dict로 받음
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            # 1) 매니저 확인
            cursor.execute("SELECT m_id, m_name FROM match_manager WHERE m_id = %s", (m_id,))
            manager = cursor.fetchone()  # 1건만 받음 (없으면 None)
            if manager is None:
                raise HTTPException(status_code=404, detail="매니저 ID가 존재하지 않습니다.")

            # 2) 팀 매칭 잠금 (FOR UPDATE : 같은 매칭 결과를 동시에 두 번 등록하지 못하게 함)
            cursor.execute("SELECT team_code FROM team_match WHERE team_code = %s FOR UPDATE", (team_code,))
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="존재하지 않는 팀 매칭입니다.")

            # 3) 매칭 정보 + 구장대여 예약의 구장·담당 매니저 (팀 매칭 조회와 같은 기준)
            cursor.execute(TEAM_MATCH_SELECT + " WHERE base.team_code = %s", (team_code,))
            match = cursor.fetchone()
            if match["rental_r_seq"] is None:
                raise HTTPException(status_code=409, detail="연결된 구장대여 예약을 찾을 수 없어 담당 매니저를 확인할 수 없습니다.")
            # 담당 매니저 = 구장대여 시간대에 배정표 기준으로 배정된 매니저
            if match["rental_m_id"] != m_id:
                raise HTTPException(status_code=403, detail="담당 매니저만 결과를 등록할 수 있습니다.")

            # 4) 이미 결과가 등록됐는지 확인 (결과 확정 후에는 수정하지 않음 → 점수 두 번 반영 방지)
            match_code = str(team_code)  # 팀 매치 경기코드 = team_code
            cursor.execute("SELECT 1 FROM t_result_record WHERE t_r_r_m_code = %s LIMIT 1", (match_code,))
            if cursor.fetchone() is not None:
                raise HTTPException(status_code=409, detail="이미 결과가 등록된 팀 매칭입니다.")
            if match["team_start"] is not None and match["team_start"] > datetime.now():
                raise HTTPException(status_code=409, detail="아직 시작하지 않은 경기입니다.")

            # 5) 종목 확인 (두 팀의 팀 종목이 같아야 함)
            cursor.execute(
                "SELECT t_id, c_category FROM team_create WHERE t_id IN (%s, %s)",
                (match["home_t_id"], match["away_t_id"]),
            )
            categories = {row["t_id"]: SPORT_CODES.get((row["c_category"] or "").strip()) for row in cursor.fetchall()}
            e_code = categories.get(match["home_t_id"])
            if e_code is None or categories.get(match["away_t_id"]) != e_code:
                raise HTTPException(status_code=409, detail="두 팀의 종목을 확인할 수 없거나 서로 다릅니다.")

            # 6) 참가 회원 확인 (형식 + 각 팀에 가입된 회원인지, 탈퇴 회원 제외)
            validate_players(e_code, body.home_players, body.away_players)
            for side, t_id, players in (("홈", match["home_t_id"], body.home_players),
                                        ("원정", match["away_t_id"], body.away_players)):
                ids = [p.c_id_seq.strip() for p in players]
                placeholders = ", ".join(["%s"] * len(ids))
                cursor.execute(
                    f"""
                    SELECT tr.c_id_seq
                    FROM t_register AS tr
                    INNER JOIN customer AS c ON c.c_id_seq = tr.c_id_seq
                    WHERE tr.t_id = %s AND tr.c_id_seq IN ({placeholders})
                        AND c.c_deletdate IS NULL
                    """,
                    [t_id, *ids],
                )
                registered = {row["c_id_seq"] for row in cursor.fetchall()}
                not_member = [c_id for c_id in ids if c_id not in registered]
                if not_member:
                    raise HTTPException(status_code=422, detail=f"{side} 팀 회원이 아닙니다: {', '.join(not_member)}")

            # 중간 수정 작성자 - 신현진 / 수정일 2026.10.29
            # 회원 기록에 반영 전 / 후 점수를 함께 저장하려고 순서 변경 : 팀 점수 → 결과 저장 → 회원 점수
            def to_dicts(players: list) -> list:
                return [{"c_id_seq": p.c_id_seq.strip(), "stats": p.stats} for p in players]

            home_list, away_list = to_dicts(body.home_players), to_dicts(body.away_players)

            # 7) 팀 점수 반영 (FIFA 방식, FOR UPDATE로 두 팀 점수 잠금)
            cursor.execute(
                "SELECT t_id, t_rating FROM team WHERE t_id IN (%s, %s) FOR UPDATE",
                (match["home_t_id"], match["away_t_id"]),
            )
            team_ratings = {row["t_id"]: row["t_rating"] or RATING_START for row in cursor.fetchall()}
            home_before = team_ratings[match["home_t_id"]]
            away_before = team_ratings[match["away_t_id"]]
            home_after = team_new_rating(home_before, away_before, result_value(body.home_score, body.away_score))
            away_after = team_new_rating(away_before, home_before, result_value(body.away_score, body.home_score))
            for t_id, rating in ((match["home_t_id"], home_after), (match["away_t_id"], away_after)):
                cursor.execute("UPDATE team SET t_rating = %s WHERE t_id = %s", (rating, t_id))

            # 8) 결과 저장
            g_code = match["rental_g_code"]
            sides = (
                # (팀ID, 팀 이름, 회원 목록, 우리 점수, 상대 점수, 경기 후 팀 점수)
                (match["home_t_id"], match["home_t_name"], home_list, body.home_score, body.away_score, home_after),
                (match["away_t_id"], match["away_t_name"], away_list, body.away_score, body.home_score, away_after),
            )
            for t_id, t_name, players, my_score, opponent_score, team_after in sides:
                score = f"{my_score}:{opponent_score}"  # 각 팀 기준 스코어 (우리팀:상대팀)
                # 팀 스탯코드 = 참가 회원 스탯 합계
                team_stats = {}
                for player in players:
                    for key, value in player["stats"].items():
                        team_stats[key] = team_stats.get(key, 0) + value
                cursor.execute(
                    """
                    INSERT INTO t_result_record
                        (m_id, g_code, t_id, t_r_r_m_code, t_r_r_date, e_code, t_r_r_statcode, t_r_r_score,
                         t_r_r_rating_after)
                    VALUES (%s, %s, %s, %s, NOW(), %s, %s, %s, %s)
                    """,
                    (m_id, g_code, t_id, match_code, e_code, pack_statcode(e_code, team_stats), score, team_after),
                )
                # 회원별 결과 (출석 1, 부상 기록은 빈 값, 스코어는 회원이 속한 팀 기준)
                for player in players:
                    statcode = pack_statcode(e_code, player["stats"])
                    if len(statcode) > STATCODE_MAX_LENGTH:
                        raise HTTPException(status_code=422, detail="기록 수가 저장 가능한 범위를 초과했습니다.")
                    cursor.execute(
                        """
                        INSERT INTO c_result_record
                            (m_id, g_code, c_id_seq, c_r_r_team, c_r_r_code, c_r_r_score, c_r_r_date,
                             e_code, c_r_r_statcode, c_r_r_attendance, c_r_r_injury)
                        VALUES (%s, %s, %s, %s, %s, %s, NOW(), %s, %s, 1, '')
                        """,
                        (m_id, g_code, player["c_id_seq"], t_name, match_code, score, e_code, statcode),
                    )

            # 9) 회원 점수 반영 (A = 홈, B = 원정) + 위에서 저장한 회원 기록에 반영 전 / 후 점수 저장
            member_changes = apply_member_ratings(
                cursor, e_code, home_list, away_list, body.home_score, body.away_score,
                match_code=match_code,
            )
        connection.commit()  # 결과 저장 + 회원·팀 점수 반영을 한 번에 확정
        return {
            "result": "OK",
            "team_code": team_code,                                          # 매치코드
            "e_code": e_code,                                                # 종목코드
            "score": f"{body.home_score}:{body.away_score}",                 # 스코어 (홈:원정)
            "home_team": {
                "t_id": match["home_t_id"], "t_name": match["home_t_name"],
                "result": result_name(result_value(body.home_score, body.away_score)),
                "rating_before": home_before, "rating_after": home_after,   # 팀 점수 변동
            },
            "away_team": {
                "t_id": match["away_t_id"], "t_name": match["away_t_name"],
                "result": result_name(result_value(body.away_score, body.home_score)),
                "rating_before": away_before, "rating_after": away_after,
            },
            "members": member_changes,                                       # 회원별 점수·등급 변동
        }
    except HTTPException:
        if connection is not None:
            connection.rollback()  # 위에서 만든 404/403/409/422는 되돌린 뒤 그대로 전달
        raise
    except pymysql.MySQLError:
        if connection is not None:
            connection.rollback()  # 에러 시 결과 저장·점수 반영을 모두 되돌림
        logger.exception("팀 매치 결과 DB 저장 실패")
        raise HTTPException(status_code=500, detail="팀 매치 결과 저장 중 DB 오류가 발생했습니다.")
    except Exception:
        if connection is not None:
            connection.rollback()
        logger.exception("팀 매치 결과 저장 실패")
        raise HTTPException(status_code=500, detail="팀 매치 결과 저장에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료


# 종목별 스탯 키·가중치 표 (앱의 기록 입력 버튼·설명 화면용)
# 예: /match/rating/stat_keys
@router.get("/rating/stat_keys")
def select_stat_keys():
    return {
        "sports": {
            e_code: {
                "name": SPORT_NAMES[e_code],                                # 종목 이름
                "stats": [{"key": key, "name": name, "weight": weight, "is_minus": weight < 0}
                          for key, name, weight in keys],
            }
            for e_code, keys in STAT_KEYS.items()
        },
        "bonus_limit": BONUS_LIMIT,                                    # 개인 보너스 최대 ±10
        "tiers": [{"min_rating": RATING_FLOOR, "name": TIER_LOWEST}]    # 등급 구간 (낮은 점수부터)
        + [{"min_rating": min_rating, "name": name} for min_rating, name in reversed(TIERS)],
    }

# 최종 수정 일 : 2026-10-29
