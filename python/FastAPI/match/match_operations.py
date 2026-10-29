# 작업자 : 양태건
# 수정일 : 2026-10-26
# [추가 시작] 출석 → 팀 배정 → 경기 기록 → 결과 등록을 서버 상태로 관리합니다.
import logging
import json
import uuid
from copy import deepcopy
from functools import wraps
from threading import RLock
import re
import time
from datetime import date
from typing import Literal

import pymysql
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from database import connect
from .manager_session import require_manager

# 작업자 : 신현진
# 수정일 : 2026-10-29
# [수정 시작] 축구만 지원하던 기록을 4종목(축구·농구·배구·야구)으로 확장하고, 결과 등록 시 회원 등급 점수를 반영합니다.
#   STAT_KEYS          : 종목별 스탯 키 (스탯코드 순서·마이너스 요인 포함, match_result_insert.py와 공용)
#   SPORT_BY_SEQUENCE  : 종목 번호 → 종목코드 (c_prefer_stock 1 축구 / 2 농구 / 3 야구 / 4 배구)
#   apply_member_ratings : 팀 승패 Elo + 개인 스탯 보너스로 c_rating 반영 (팀 매치 결과 등록과 같은 기준)
from .match_result_insert import (
    SPORT_BY_SEQUENCE,
    SPORT_NAMES,
    STAT_KEYS,
    apply_member_ratings,
    pack_statcode,
    unpack_statcode,
)
# [수정 끝]

router = APIRouter(prefix="/match/operations", tags=["Match Operations"])
logger = logging.getLogger(__name__)

# 작업자 : 신현진
# 수정일 : 2026-10-29
# [수정 시작] 종목별 기록 버튼 (기존 STATS = 축구 5개 고정 → 종목코드별 버튼)
#   kind     : 앱에서 보내는 버튼 값 (축구는 기존 goal/assist/shot/yellow/red 값을 그대로 유지)
#   stats    : 이 버튼을 누르면 올라가는 스탯 키·개수
#   own      : 버튼을 누른 선수 팀에 더해지는 점수
#   opponent : 상대 팀에 더해지는 점수 (배구의 파울·범실은 상대 팀 득점)
#   runners  : True면 기록할 때 홈인한 주자(같은 팀, 최대 3명)를 함께 받음 (야구 홈런)
#   야구 홈런 : 버튼 1번 + 홈인한 주자 선택으로 한 번에 기록
#          타자 : 홈런 1, 안타 1, 본인 득점 1, 타점 (주자 수 + 1) / 주자 : 각각 득점 1 / 팀 : +(주자 수 + 1)
#          예) 1점 +1 / 2점 +2 / 3점 +3 / 만루 홈런(주자 3명) +4 → 타자 4타점, 주자 3명 각 1득점
#          "마지막 기록 취소"는 홈런 1건(주자 득점·타점 포함)을 한 번에 되돌림
#   안타·희생타 등으로 주자가 들어올 때는 주자에게 "득점(홈인)"(팀 +1), 타자에게 "타점"을 따로 눌러 줌
SPORT_EVENTS = {
    "SOCCER": [
        dict(kind="goal", label="골", stats={"G": 1}, own=1, opponent=0),
        dict(kind="assist", label="도움", stats={"A": 1}, own=0, opponent=0),
        dict(kind="shot", label="슈팅", stats={"S": 1}, own=0, opponent=0),
        dict(kind="foul", label="파울", stats={"F": 1}, own=0, opponent=0),
        dict(kind="miss", label="찬스미스", stats={"M": 1}, own=0, opponent=0),
        dict(kind="error", label="실책", stats={"E": 1}, own=0, opponent=0),
        dict(kind="yellow", label="경고", stats={"Y": 1}, own=0, opponent=0),
        dict(kind="red", label="퇴장", stats={"R": 1}, own=0, opponent=0),
    ],
    "BASKETBALL": [
        dict(kind="free_throw", label="자유투 1점", stats={"P": 1}, own=1, opponent=0),
        dict(kind="two_point", label="2점", stats={"P": 2}, own=2, opponent=0),
        dict(kind="three_point", label="3점", stats={"P": 3, "T": 1}, own=3, opponent=0),
        dict(kind="assist", label="어시스트", stats={"A": 1}, own=0, opponent=0),
        dict(kind="rebound", label="리바운드", stats={"RB": 1}, own=0, opponent=0),
        dict(kind="foul", label="파울", stats={"F": 1}, own=0, opponent=0),
        dict(kind="turnover", label="턴오버", stats={"TO": 1}, own=0, opponent=0),
    ],
    "VOLLEYBALL": [
        dict(kind="attack", label="공격 득점", stats={"P": 1}, own=1, opponent=0),
        dict(kind="block", label="블로킹", stats={"B": 1}, own=1, opponent=0),
        dict(kind="ace", label="서브에이스", stats={"SA": 1}, own=1, opponent=0),
        dict(kind="foul", label="파울", stats={"F": 1}, own=0, opponent=1),
        dict(kind="error", label="범실", stats={"E": 1}, own=0, opponent=1),
    ],
    "BASEBALL": [
        dict(kind="hit", label="안타", stats={"H": 1}, own=0, opponent=0),
        # 주자 1명마다 : 주자 RS +1, 타자 RBI +1, 팀 +1 (totals에서 계산)
        dict(kind="homerun", label="홈런", stats={"HR": 1, "H": 1, "RS": 1, "RBI": 1}, own=1, opponent=0,
             runners=True),
        dict(kind="rbi", label="타점", stats={"RBI": 1}, own=0, opponent=0),
        dict(kind="run", label="득점(홈인)", stats={"RS": 1}, own=1, opponent=0),
        dict(kind="walk", label="볼넷", stats={"BB": 1}, own=0, opponent=0),
        dict(kind="out", label="아웃", stats={"O": 1}, own=0, opponent=0),
        dict(kind="strikeout", label="삼진", stats={"K": 1}, own=0, opponent=0),
        dict(kind="error", label="실책", stats={"E": 1}, own=0, opponent=0),
    ],
}

# 저장된 스탯으로 팀 점수를 다시 계산하는 규칙 (서버 재시작 후 결과 복원 시 팀 순서 확인용)
#   (우리 팀 스탯 중 점수가 되는 키, 상대 팀 스탯 중 우리 점수가 되는 키)
SCORE_RULES = {
    "SOCCER": ({"G": 1}, {}),
    "BASKETBALL": ({"P": 1}, {}),
    "VOLLEYBALL": ({"P": 1, "B": 1, "SA": 1}, {"F": 1, "E": 1}),
    "BASEBALL": ({"RS": 1}, {}),
}


# 경기 종목코드 (참가 회원의 c_prefer_stock이 모두 같아야 함, 섞여 있거나 모르면 None)
def sport_code(state):
    numbers = {str(p.get("c_prefer_stock")) for p in state["players"]}
    if len(numbers) != 1:
        return None
    return SPORT_BY_SEQUENCE.get(numbers.pop())


# 화면에 그릴 종목 정보 (버튼·스탯 이름), 종목을 모르면 축구 기준으로 표시
def sport_info(state):
    e_code = sport_code(state) or "SOCCER"
    return dict(
        e_code=e_code,
        name=SPORT_NAMES[e_code],
        known=sport_code(state) is not None,
        # runners : True면 앱에서 홈인한 주자 선택 창을 띄움 (야구 홈런)
        events=[dict(kind=e["kind"], label=e["label"], own=e["own"], opponent=e["opponent"],
                     runners=e.get("runners", False))
                for e in SPORT_EVENTS[e_code]],
        stats=[dict(key=key, label=name) for key, name, _ in STAT_KEYS[e_code]],
    )


# 팀 스탯 합계로 팀 점수 계산 (SCORE_RULES 기준)
def team_points(e_code, own_stats, opponent_stats):
    own_rule, opponent_rule = SCORE_RULES[e_code]
    return sum(own_stats.get(k, 0) * v for k, v in own_rule.items()) + sum(
        opponent_stats.get(k, 0) * v for k, v in opponent_rule.items()
    )


# [수정 끝]
ROSTER_SQL = """
 SELECT r.r_seq, r.c_id_seq, r.g_code, r.r_date,
        TIME_FORMAT(r.rs_time, '%%H:%%i:%%s') AS rs_time,
        TIME_FORMAT(r.re_time, '%%H:%%i:%%s') AS re_time,
        g.g_name, c.c_name, c.c_position, c.c_rating, c.c_prefer_stock,
        CONCAT(r.g_code, '_', DATE_FORMAT(r.r_date, '%%Y%%m%%d'), '_',
               TIME_FORMAT(r.rs_time, '%%H%%i%%s')) AS match_code
 FROM reservation r JOIN ground g ON g.g_code = r.g_code
 JOIN customer c ON c.c_id_seq = r.c_id_seq
"""


# 작업자 : 양태건
# 수정일 : 2026-10-26
# [수정 시작] 새 DB 테이블 없이 한 서버 프로세스의 메모리에 진행 상태를 보관합니다.
# SQL 저장 성공 전에는 캐시를 갱신하지 않으며, 동시에 들어온 명령은 순서대로 처리합니다.
_MATCHES = {}
_MATCH_LOCK = RLock()


def serialized(function):
    @wraps(function)
    def wrapped(*args, **kwargs):
        with _MATCH_LOCK:
            return function(*args, **kwargs)

    return wrapped


def remember(record, state):
    _MATCHES[record["match_code"]] = (deepcopy(record), deepcopy(state))


# [수정 끝]


class Command(BaseModel):
    model_config = ConfigDict(extra="forbid")
    version: int = Field(ge=0)
    action: Literal[
        "attendance",
        "back",
        "teams",
        "start",
        "pause",
        "resume",
        "event",
        "undo",
        "injury",
        "end",
        "edit",
        "publish",
    ]
    r_seq: int | None = None
    attendance: bool | None = None
    assignments: dict[str, str] = Field(default_factory=dict)
    team_names: list[str] = Field(
        default_factory=lambda: ["블루팀", "화이트팀"], min_length=2, max_length=2
    )
    team_colors: list[str] = Field(
        default_factory=lambda: ["blue", "grey"], min_length=2, max_length=2
    )
    # 작업자 : 신현진 / 수정일 : 2026-10-29
    # 종목마다 버튼이 달라서 고정 목록 대신 글자로 받고, 기록할 때 SPORT_EVENTS로 확인합니다.
    kind: str | None = Field(default=None, max_length=20)
    # 야구 홈런 때 홈인한 주자 예약번호 (같은 팀, 최대 3명 = 만루 홈런)
    runners: list[int] = Field(default_factory=list, max_length=3)
    body_parts: list[str] = Field(default_factory=list, max_length=8)
    severity: Literal["mild", "moderate", "severe"] | None = None
    measures: list[str] = Field(default_factory=list, max_length=7)
    description: str = Field(default="", max_length=2000)
    contact: bool = False
    occurred_seconds: int | None = Field(default=None, ge=0)


def schedule_matches(row, assignments):
    """구장뿐 아니라 배정 요일·시간까지 비교합니다. 해석 불가 배정은 허용하지 않습니다."""
    weekday = "월화수목금토일"[date.fromisoformat(str(row["r_date"])).weekday()]
    for assignment in assignments:
        if assignment["g_code"] != row["g_code"]:
            continue
        days = assignment["a_day"] or ""
        times = re.findall(r"\d{1,2}:\d{2}", assignment["a_time"] or "")
        if weekday not in days or len(times) != 2:
            continue
        start, end = [int(t.split(":")[0]) * 60 + int(t.split(":")[1]) for t in times]
        hour, minute, *_ = row["rs_time"].split(":")
        slot = int(hour) * 60 + int(minute)
        if (start <= slot < end) if start < end else (slot >= start or slot < end):
            return True
    return False


def assignments_for(cursor, manager_id):
    cursor.execute(
        "SELECT g_code, a_day, a_time FROM assign WHERE m_id = %s", (manager_id,)
    )
    return cursor.fetchall()


def elapsed(state):
    seconds = state.get("elapsed_seconds", 0)
    if state.get("running_since") is not None:
        seconds += max(0, time.time() - state["running_since"])
    return int(seconds)


def pause_clock(state):
    state["elapsed_seconds"] = elapsed(state)
    state["running_since"] = None


# 작업자 : 신현진
# 수정일 : 2026-10-29
# [수정 시작] 종목별 버튼 정의(SPORT_EVENTS)로 회원 스탯과 팀 점수를 계산합니다.
#   스탯은 스탯코드 키(G, A, P, RBI ...) 기준으로 모읍니다.
def totals(state):
    if "final_stats" in state:
        return deepcopy(state["final_stats"]), deepcopy(state["final_scores"])
    e_code = sport_code(state) or "SOCCER"
    keys = [key for key, _, _ in STAT_KEYS[e_code]]
    events = {e["kind"]: e for e in SPORT_EVENTS[e_code]}
    result = {str(p["r_seq"]): dict.fromkeys(keys, 0) for p in state["players"]}
    scores = {"A": 0, "B": 0}
    for event in state["events"]:
        definition = events.get(event["kind"])
        if definition is None:
            continue  # 종목에 없는 예전 기록은 계산하지 않음
        for key, count in definition["stats"].items():
            result[str(event["r_seq"])][key] += count
        opponent = "B" if event["team"] == "A" else "A"
        scores[event["team"]] += definition["own"]
        scores[opponent] += definition["opponent"]
        # 야구 홈런의 홈인 주자 : 주자 득점 +1, 타자 타점 +1, 팀 +1 (주자 1명마다)
        for runner in event.get("runners", []):
            result[str(runner)]["RS"] += 1
            result[str(event["r_seq"])]["RBI"] += 1
            scores[event["team"]] += 1
    return result, scores


# [수정 끝]


def initial_state(rows):
    seen = set()
    players = []
    for row in rows:
        if row["c_id_seq"] in seen:
            continue
        seen.add(row["c_id_seq"])
        players.append(
            {
                key: row[key]
                for key in (
                    "r_seq",
                    "c_id_seq",
                    "c_name",
                    "c_position",
                    "c_rating",
                    "c_prefer_stock",
                )
            }
        )
    return dict(
        players=players,
        attendance={},
        assignments={},
        team_names=["블루팀", "화이트팀"],
        team_colors=["blue", "grey"],
        events=[],
        injuries=[],
        elapsed_seconds=0,
        running_since=None,
        storage_mode="memory",
    )


# 작업자 : 양태건
# 수정일 : 2026-10-26
# [수정 시작] 기존 결과는 값을 추정하거나 옮기지 않고 읽기 전용으로 표시합니다.
def legacy_results(cursor, code, manager_id=None):
    sql = """
        SELECT r.c_r_r_seq, r.c_id_seq, c.c_name, r.m_id,
               r.c_r_r_team, r.e_code, r.c_r_r_statcode,
               r.c_r_r_score, r.c_r_r_attendance, r.c_r_r_date, r.c_r_r_injury
        FROM c_result_record r LEFT JOIN customer c ON c.c_id_seq=r.c_id_seq
        WHERE r.c_r_r_code=%s AND r.c_r_r_score IS NOT NULL
    """
    params = [code]
    if manager_id is not None:
        sql += " AND r.m_id=%s"
        params.append(manager_id)
    cursor.execute(sql + " ORDER BY r.c_r_r_seq", params)
    return cursor.fetchall()


def legacy_response(record, state):
    return dict(
        match_code=record["match_code"],
        r_seq=record["anchor_r_seq"],
        status="completed",
        version=0,
        legacy=True,
        state=state,
        stats={},
        scores=None,
        elapsed_seconds=0,
        server_time=time.time(),
        sport=sport_info(state),  # 작업자 : 신현진 / 수정일 : 2026-10-29 종목 정보
    )


# [수정 끝]


def response_for(record, state):
    if record.get("legacy"):
        return legacy_response(record, state)
    stats, scores = totals(state)
    return dict(
        match_code=record["match_code"],
        r_seq=record["anchor_r_seq"],
        status=record["status"],
        version=record["version"],
        state=state,
        stats=stats,
        scores=scores,
        elapsed_seconds=elapsed(state),
        server_time=time.time(),
        # 작업자 : 신현진 / 수정일 : 2026-10-29
        # 종목 정보 (앱은 이 값으로 기록 버튼·스탯 이름을 그림)
        sport=sport_info(state),
    )


# 작업자 : 양태건
# 수정일 : 2026-10-26
# [수정 시작] 결과는 기존 c_result_record에서 읽고 미등록 상태만 메모리에 유지합니다.
# 작업자 : 양태건
# 수정일 : 2026-10-26
# [추가 시작] 회원별 c_r_r_injury의 JSON 목록을 읽고 이전 텍스트도 보존합니다.
def injuries_from_rows(rows, players):
    injuries, seen = [], set()
    by_id = {p["c_id_seq"]: p for p in players}
    for row in rows:
        raw = row.get("c_r_r_injury")
        if not raw:
            continue
        try:
            parsed = json.loads(raw)
        except (ValueError, TypeError):
            parsed = raw
        if not isinstance(parsed, list):
            parsed = [dict(description=str(parsed), body_parts=["기타"])]
        player = by_id.get(row["c_id_seq"], {})
        for entry in parsed:
            if not isinstance(entry, dict):
                entry = dict(description=str(entry), body_parts=["기타"])
            key = (
                row["c_id_seq"],
                json.dumps(entry, ensure_ascii=False, sort_keys=True),
            )
            if key in seen:
                continue
            seen.add(key)
            injuries.append(
                dict(
                    id=entry.get("id"),
                    r_seq=player.get("r_seq"),
                    name=player.get("c_name") or row.get("c_name") or row["c_id_seq"],
                    body_parts=(
                        entry.get("body_parts")
                        if isinstance(entry.get("body_parts"), list)
                        else ["기타"]
                    ),
                    severity=entry.get("severity"),
                    measures=(
                        entry.get("measures")
                        if isinstance(entry.get("measures"), list)
                        else []
                    ),
                    description=str(entry.get("description", "")),
                    contact=entry.get("contact"),
                    elapsed_seconds=(
                        entry.get("elapsed_seconds")
                        if isinstance(entry.get("elapsed_seconds"), (int, float))
                        else None
                    ),
                )
            )
    return injuries


def read_injuries(cursor, record, players):
    cursor.execute(
        "SELECT c_id_seq,c_r_r_injury FROM c_result_record WHERE c_r_r_code=%s AND m_id=%s ORDER BY c_r_r_seq",
        (record["match_code"], record["m_id"]),
    )
    return injuries_from_rows(cursor.fetchall(), players)


def save_injury(cursor, record, player, injury):
    # 출석 행을 확보하고 잠근 뒤 저장합니다. 다른 회원·다른 경기의 부상은 갱신하지 않습니다.
    write_attendance(cursor, record, player, True)
    cursor.execute(
        "SELECT c_id_seq,c_r_r_injury FROM c_result_record WHERE c_r_r_code=%s AND c_id_seq=%s ORDER BY c_r_r_seq FOR UPDATE",
        (record["match_code"], player["c_id_seq"]),
    )
    previous = injuries_from_rows(cursor.fetchall(), [player])
    value = json.dumps(previous + [injury], ensure_ascii=False, separators=(",", ":"))
    if len(value.encode("utf-8")) > 65535:
        raise HTTPException(422, "부상 기록이 컬럼 저장 한도를 초과했습니다.")
    cursor.execute(
        "UPDATE c_result_record SET c_r_r_injury=%s WHERE c_r_r_code=%s AND c_id_seq=%s",
        (value, record["match_code"], player["c_id_seq"]),
    )


# [추가 끝]


def completed_state(rows, results):
    state = initial_state(rows)
    state["legacy_records"] = results
    state["injuries"] = injuries_from_rows(results, state["players"])
    teams = list(dict.fromkeys(r["c_r_r_team"] for r in results))
    scores = {r["c_r_r_score"] for r in results}
    # 작업자 : 신현진
    # 수정일 : 2026-10-29
    # [수정 시작] 4종목 스탯코드를 종목 키 기준으로 읽고, 종목별 점수 규칙(SCORE_RULES)으로 팀 순서를 확인합니다.
    #   예전 축구 형식(G:1,A:0,S:0,Y:0,R:0)도 그대로 읽힘 (없는 키는 0)
    e_codes = {r["e_code"] for r in results}
    e_code = next(iter(e_codes)) if len(e_codes) == 1 else None
    allowed = {key for key, _, _ in STAT_KEYS.get(e_code, [])}
    parsed = {r["c_id_seq"]: unpack_statcode(r["c_r_r_statcode"]) for r in results}
    # 새 형식의 개인 기록·최종 점수는 서버 재시작 후에도 기존 결과 테이블에서 복원합니다.
    if (
        len(teams) == 2
        and all(teams)
        and len(scores) == 1
        and e_code in STAT_KEYS
        and all(stats and set(stats) <= allowed for stats in parsed.values())
        and re.fullmatch(r"\d+:\d+", str(next(iter(scores))))
    ):
        a, b = map(int, next(iter(scores)).split(":"))
        keys = [key for key, _, _ in STAT_KEYS[e_code]]

        def team_sum(name):
            total = dict.fromkeys(keys, 0)
            for r in results:
                if r["c_r_r_team"] == name:
                    for key, value in parsed[r["c_id_seq"]].items():
                        total[key] += value
            return total

        sums = [team_sum(name) for name in teams]
        team_goals = [team_points(e_code, sums[0], sums[1]), team_points(e_code, sums[1], sums[0])]
        if team_goals == [b, a] and a != b:
            teams.reverse()
        elif team_goals != [a, b]:
            return state, True  # 일관되지 않은 기존 결과는 원문으로 표시합니다.
        state.update(
            team_names=teams,
            duration_unknown=True,
            final_scores={"A": a, "B": b},
            final_stats={
                str(p["r_seq"]): dict.fromkeys(keys, 0) for p in state["players"]
            },
        )
        # [수정 끝]
        for player in state["players"]:
            result = next(
                (r for r in results if r["c_id_seq"] == player["c_id_seq"]), None
            )
            if result is None:
                continue
            key = str(player["r_seq"])
            state["attendance"][key] = bool(result["c_r_r_attendance"])
            state["assignments"][key] = "A" if result["c_r_r_team"] == teams[0] else "B"
            # 작업자 : 신현진 / 수정일 : 2026-10-29 종목 키 기준으로 복원
            state["final_stats"][key].update(parsed[player["c_id_seq"]])
        return state, False
    return state, True


def load_match(cursor, anchor, manager_id, *, lock=False):
    cursor.execute(ROSTER_SQL + " WHERE r.r_seq = %s", (anchor,))
    row = cursor.fetchone()
    if row is None:
        raise HTTPException(404, "경기를 찾을 수 없습니다.")
    code = row["match_code"]
    cursor.execute(
        ROSTER_SQL
        + " WHERE r.g_code=%s AND r.r_date=%s AND r.rs_time=%s ORDER BY r.r_seq",
        (row["g_code"], row["r_date"], row["rs_time"]),
    )
    rows = cursor.fetchall()
    record = dict(
        match_code=code,
        anchor_r_seq=rows[0]["r_seq"],
        m_id=manager_id,
        g_code=row["g_code"],
        g_name=row["g_name"],
        match_date=str(row["r_date"]),
        start_time=row["rs_time"],
        status="attendance",
        version=0,
    )
    prior_results = legacy_results(cursor, code)
    cached = _MATCHES.get(code)
    if prior_results:
        own = [r for r in prior_results if r["m_id"] == manager_id]
        if not own:
            raise HTTPException(403, "다른 매니저가 등록한 경기 결과입니다.")
        if (
            cached
            and cached[0]["m_id"] == manager_id
            and cached[0]["status"] == "completed"
        ):
            return deepcopy(cached)
        state, legacy = completed_state(rows, own)
        record.update(status="completed", legacy=legacy)
        return record, state
    if not schedule_matches(row, assignments_for(cursor, manager_id)):
        raise HTTPException(403, "배정된 요일·시간의 경기만 진행할 수 있습니다.")
    if cached:
        if cached[0]["m_id"] != manager_id:
            raise HTTPException(403, "다른 매니저가 진행하는 경기입니다.")
        record, state = deepcopy(cached)
        state["injuries"] = read_injuries(cursor, record, state["players"])
        if record["status"] == "attendance":
            state["players"] = initial_state(rows)["players"]
            ids = {str(p["r_seq"]) for p in state["players"]}
            state["attendance"] = {
                k: v for k, v in state["attendance"].items() if k in ids
            }
        return record, state
    state = initial_state(rows)
    cursor.execute(
        "SELECT c_id_seq,c_r_r_attendance FROM c_result_record WHERE c_r_r_code=%s ORDER BY c_r_r_seq",
        (code,),
    )
    for old in cursor.fetchall():
        for player in state["players"]:
            if (
                player["c_id_seq"] == old["c_id_seq"]
                and old["c_r_r_attendance"] is not None
            ):
                state["attendance"][str(player["r_seq"])] = bool(
                    old["c_r_r_attendance"]
                )
    state["injuries"] = read_injuries(cursor, record, state["players"])
    return record, state


# [수정 끝]


def write_attendance(cursor, record, player, present):
    cursor.execute(
        "SELECT c_r_r_seq, c_r_r_score FROM c_result_record WHERE c_r_r_code=%s AND c_id_seq=%s FOR UPDATE",
        (record["match_code"], player["c_id_seq"]),
    )
    old = cursor.fetchall()
    if any(r["c_r_r_score"] is not None for r in old):
        raise HTTPException(409, "결과가 이미 등록된 회원입니다.")
    if old:
        cursor.execute(
            "UPDATE c_result_record SET c_r_r_attendance=%s, m_id=%s WHERE c_r_r_code=%s AND c_id_seq=%s",
            (present, record["m_id"], record["match_code"], player["c_id_seq"]),
        )
    else:
        cursor.execute(
            "INSERT INTO c_result_record (m_id,g_code,c_id_seq,c_r_r_code,c_r_r_attendance,c_r_r_injury) VALUES (%s,%s,%s,%s,%s,'')",
            (
                record["m_id"],
                record["g_code"],
                player["c_id_seq"],
                record["match_code"],
                present,
            ),
        )


def mutate(cursor, record, state, command):
    # 작업자 : 양태건
    # 수정일 : 2026-10-26
    # [수정 시작] 기존 완료 결과는 재등록·수정하지 않습니다.
    if record.get("legacy"):
        raise HTTPException(409, "기존 경기 결과는 읽기 전용입니다.")
    # [수정 끝]
    action, status = command.action, record["status"]
    if status == "completed":
        if action == "publish":
            return  # 재전송 시 기존 결과를 반환하여 중복 저장하지 않습니다.
        raise HTTPException(409, "결과 등록이 완료된 경기는 수정할 수 없습니다.")
    if command.version != record["version"]:
        raise HTTPException(
            409, "다른 작업에서 갱신됐습니다. 다시 불러온 뒤 작업해 주세요."
        )
    player = next((p for p in state["players"] if p["r_seq"] == command.r_seq), None)
    if action == "attendance":
        if status != "attendance" or player is None or command.attendance is None:
            raise HTTPException(409, "출석 확인 화면에서 대상 회원을 선택해 주세요.")
        write_attendance(cursor, record, player, command.attendance)
        state["attendance"][str(player["r_seq"])] = command.attendance
    elif action == "back":
        if status != "teams":
            raise HTTPException(409, "팀 설정에서만 출석으로 돌아갈 수 있습니다.")
        record["status"] = "attendance"
        state["assignments"] = {}
    elif action == "teams":
        if status not in ("attendance", "teams"):
            raise HTTPException(409, "팀 설정은 경기 시작 전에 진행해 주세요.")
        # 작업자 : 신현진 / 수정일 : 2026-10-29
        # 축구만 허용하던 확인을 4종목으로 변경 (참가 회원의 종목이 모두 같아야 함)
        if sport_code(state) is None:
            raise HTTPException(409, "참가 회원의 종목을 확인할 수 없거나 종목이 섞여 있습니다.")
        if any(str(p["r_seq"]) not in state["attendance"] for p in state["players"]):
            raise HTTPException(409, "모든 예약자의 출석 또는 결석을 확인해 주세요.")
        state.update(
            assignments=command.assignments,
            team_names=command.team_names,
            team_colors=command.team_colors,
        )
        record["status"] = "teams"
    elif action == "start":
        present = {
            str(p["r_seq"])
            for p in state["players"]
            if state["attendance"].get(str(p["r_seq"]))
        }
        assigned = state["assignments"]
        counts = [list(assigned.values()).count(t) for t in ("A", "B")]
        if (
            status != "teams"
            or set(assigned) != present
            or any(t not in ("A", "B") for t in assigned.values())
            or min(counts) == 0
            or abs(counts[0] - counts[1]) > 1
        ):
            raise HTTPException(
                409,
                "출석자를 두 팀에 모두 배정하고 인원 차이를 1명 이하로 맞춰 주세요.",
            )
        if (
            len(set(n.strip() for n in state["team_names"])) != 2
            or any(not n.strip() or len(n) > 50 for n in state["team_names"])
            or len(set(state["team_colors"])) != 2
            or any(
                c not in ("blue", "grey", "red", "green", "orange", "navy")
                for c in state["team_colors"]
            )
        ):
            raise HTTPException(422, "팀 이름과 서로 다른 조끼 색을 확인해 주세요.")
        record["status"] = "live"
        state["running_since"] = time.time()
    elif action in ("pause", "resume"):
        if status != "live":
            raise HTTPException(409, "진행 중인 경기에서만 사용할 수 있습니다.")
        if action == "pause":
            pause_clock(state)
        elif state["running_since"] is None:
            state["running_since"] = time.time()
    elif action == "event":
        if (
            status != "live"
            or player is None
            or str(player["r_seq"]) not in state["assignments"]
            or command.kind is None
        ):
            raise HTTPException(409, "진행 중인 경기의 선수를 먼저 선택해 주세요.")
        # 작업자 : 신현진
        # 수정일 : 2026-10-29
        # [수정 시작] 이 경기 종목의 버튼인지 확인하고, 축구 퇴장(R)만 추가 기록을 막습니다.
        e_code = sport_code(state)
        definition = next((e for e in SPORT_EVENTS.get(e_code, []) if e["kind"] == command.kind), None)
        if definition is None:
            raise HTTPException(422, "이 종목에 없는 기록입니다.")
        stats, _ = totals(state)
        if e_code == "SOCCER" and stats[str(player["r_seq"])]["R"]:
            raise HTTPException(409, "퇴장한 선수는 추가 기록을 입력할 수 없습니다.")
        # 홈인 주자 확인 (야구 홈런만, 같은 팀 출전 선수, 타자 본인·중복 제외, 최대 3명)
        team = state["assignments"][str(player["r_seq"])]
        runners = command.runners
        if runners and not definition.get("runners"):
            raise HTTPException(422, "홈인 주자는 홈런 기록에서만 선택할 수 있습니다.")
        if len(set(runners)) != len(runners) or player["r_seq"] in runners:
            raise HTTPException(422, "홈인 주자를 다시 선택해 주세요. (타자 본인·중복 선택 불가)")
        if any(state["assignments"].get(str(r)) != team for r in runners):
            raise HTTPException(422, "홈인 주자는 같은 팀 출전 선수만 선택할 수 있습니다.")
        names = {p["r_seq"]: p["c_name"] for p in state["players"]}
        # [수정 끝]
        state["events"].append(
            dict(
                r_seq=player["r_seq"],
                name=player["c_name"],
                kind=command.kind,
                team=team,
                elapsed_seconds=elapsed(state),
                # 작업자 : 신현진 / 수정일 : 2026-10-29 홈런 홈인 주자 (기록 목록 표시용 이름 포함)
                runners=runners,
                runner_names=[names[r] for r in runners],
            )
        )
    elif action == "undo":
        if status != "live" or not state["events"]:
            raise HTTPException(409, "취소할 기록이 없습니다.")
        state["events"].pop()
    elif action == "injury":
        parts = {
            "머리·얼굴",
            "목·어깨",
            "팔·손목",
            "손가락",
            "허리·등",
            "무릎",
            "발목·발",
            "기타",
        }
        measures = {
            "아이싱",
            "응급처치·밴드",
            "경기 일시 중단",
            "교체·퇴장",
            "119 신고",
            "병원 이송",
            "보호자 연락",
        }
        if (
            status != "live"
            or player is None
            or str(player["r_seq"]) not in state["assignments"]
        ):
            raise HTTPException(409, "부상을 기록할 출석 선수를 선택해 주세요.")
        if (
            not command.body_parts
            or not set(command.body_parts) <= parts
            or not set(command.measures) <= measures
            or command.severity is None
            or not command.description.strip()
        ):
            raise HTTPException(422, "부상 부위·정도·상황을 입력해 주세요.")
        # 작업자 : 양태건
        # 수정일 : 2026-10-26
        # [수정 시작] 부상 저장 즉시 해당 회원의 경기 결과 행에 상세 내용을 누적합니다.
        injury = dict(
            id=uuid.uuid4().hex,
            r_seq=player["r_seq"],
            name=player["c_name"],
            body_parts=command.body_parts,
            severity=command.severity,
            measures=command.measures,
            description=command.description.strip(),
            contact=command.contact,
            elapsed_seconds=min(
                (
                    command.occurred_seconds
                    if command.occurred_seconds is not None
                    else elapsed(state)
                ),
                elapsed(state),
            ),
        )
        save_injury(cursor, record, player, injury)
        state["injuries"].append(injury)
        # [수정 끝]
        if "경기 일시 중단" in command.measures:
            pause_clock(state)
    elif action == "end":
        if status != "live":
            raise HTTPException(409, "진행 중인 경기만 종료할 수 있습니다.")
        pause_clock(state)
        record["status"] = "review"
    elif action == "edit":
        if status != "review":
            raise HTTPException(409, "결과 확인 화면에서만 돌아갈 수 있습니다.")
        record["status"] = "live"  # 기록 정정 중에는 시계를 정지 상태로 유지합니다.
    elif action == "publish":
        if status != "review":
            raise HTTPException(409, "경기를 종료하고 결과를 확인해 주세요.")
        stats, scores = totals(state)
        # 작업자 : 양태건
        # 수정일 : 2026-10-26
        # 기존 예약 행을 잠가 재등록을 방지하고 전원의 결과를 한 트랜잭션으로 저장합니다.
        cursor.execute(
            "SELECT r_seq FROM reservation WHERE g_code=%s AND CONCAT(g_code, '_', DATE_FORMAT(r_date, '%%Y%%m%%d'), '_', TIME_FORMAT(rs_time, '%%H%%i%%s'))=%s ORDER BY r_seq FOR UPDATE",
            (record["g_code"], record["match_code"]),
        )
        cursor.fetchall()
        # 팀 이름 중복은 완료 결과의 팀 복원을 불가능하게 하므로 시작 전에 막습니다.
        # 작업자 : 신현진
        # 수정일 : 2026-10-29
        # [수정 시작] 경기 종목의 스탯코드·종목코드로 저장하고, 같은 트랜잭션에서 회원 등급 점수(c_rating)를 반영합니다.
        e_code = sport_code(state)
        if e_code is None:
            raise HTTPException(409, "참가 회원의 종목을 확인할 수 없거나 종목이 섞여 있습니다.")
        rating_teams = {"A": [], "B": []}  # 등급 점수 계산용 팀별 출석 회원
        for p in state["players"]:
            present = state["attendance"].get(str(p["r_seq"]), False)
            write_attendance(cursor, record, p, present)
            if not present:
                continue
            s = stats[str(p["r_seq"])]
            packed = pack_statcode(e_code, s)
            if len(packed) > 50:
                raise HTTPException(422, "기록 수가 저장 가능한 범위를 초과했습니다.")
            team = state["assignments"][str(p["r_seq"])]
            cursor.execute(
                "UPDATE c_result_record SET c_r_r_team=%s,e_code=%s,c_r_r_statcode=%s,c_r_r_score=%s WHERE c_r_r_code=%s AND c_id_seq=%s",
                (
                    state["team_names"][0 if team == "A" else 1],
                    e_code,
                    packed,
                    f"{scores['A']}:{scores['B']}",
                    record["match_code"],
                    p["c_id_seq"],
                ),
            )
            rating_teams[team].append(dict(c_id_seq=p["c_id_seq"], stats=s))
        # 결과 저장과 같은 트랜잭션이라 저장이 실패하면 점수 반영도 함께 되돌아감
        # 결과 등록은 한 번만 가능해서(completed 이후 재등록 불가) 점수도 한 번만 반영됨
        # match_code : 회원 결과 기록에 반영 전 / 후 점수(c_r_r_rating_before / after)도 저장 (2026-10-29 신현진)
        state["rating_changes"] = apply_member_ratings(
            cursor, e_code, rating_teams["A"], rating_teams["B"], scores["A"], scores["B"],
            match_code=record["match_code"],
        )
        # [수정 끝]
        record["status"] = "completed"


# 작업자 : 양태건
# 수정일 : 2026-10-26
# [수정 시작] 목록·상세·저장 경로에서 삭제된 테이블 참조를 모두 제거합니다.
@router.get("")
@serialized
def match_list(manager_id: str = Depends(require_manager)):
    conn = connect()
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            assignments = assignments_for(cursor, manager_id)
            cursor.execute(
                ROSTER_SQL
                + " WHERE EXISTS (SELECT 1 FROM assign a WHERE a.g_code=r.g_code AND a.m_id=%s) OR EXISTS (SELECT 1 FROM c_result_record old WHERE old.m_id=%s AND old.c_r_r_score IS NOT NULL AND old.c_r_r_code=CONCAT(r.g_code, '_', DATE_FORMAT(r.r_date, '%%Y%%m%%d'), '_', TIME_FORMAT(r.rs_time, '%%H%%i%%s'))) ORDER BY r.r_date,r.rs_time,r.r_seq",
                (manager_id, manager_id),
            )
            rows = cursor.fetchall()
            prior_by_code = {
                code: legacy_results(cursor, code)
                for code in {r["match_code"] for r in rows}
            }
            groups = {}
            for row in rows:
                code = row["match_code"]
                prior = prior_by_code[code]
                own = [r for r in prior if r["m_id"] == manager_id]
                cached = _MATCHES.get(code)
                if (prior and not own) or (
                    not prior and cached and cached[0]["m_id"] != manager_id
                ):
                    continue
                if not own and not schedule_matches(row, assignments):
                    continue
                if code not in groups:
                    groups[code] = dict(
                        match_code=code,
                        r_seq=row["r_seq"],
                        g_name=row["g_name"],
                        r_date=str(row["r_date"]),
                        rs_time=row["rs_time"],
                        count=0,
                        status="attendance",
                    )
                groups[code]["count"] += 1
                if own:
                    groups[code].update(
                        status="completed",
                        result_summary="최종 스코어 "
                        + " / ".join(dict.fromkeys(str(r["c_r_r_score"]) for r in own)),
                    )
                elif cached:
                    groups[code]["status"] = cached[0]["status"]
                    _, groups[code]["scores"] = totals(cached[1])
            return {
                "results": sorted(
                    groups.values(), key=lambda g: (g["r_date"], g["rs_time"])
                )
            }
    finally:
        conn.close()


@router.get("/{anchor}")
@serialized
def match_detail(anchor: int, manager_id: str = Depends(require_manager)):
    conn = connect()
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            record, state = load_match(cursor, anchor, manager_id)
        conn.commit()
        remember(record, state)
        return response_for(record, state)
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


@router.post("/{anchor}")
@serialized
def match_command(
    anchor: int, command: Command, manager_id: str = Depends(require_manager)
):
    conn = connect()
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            record, state = load_match(cursor, anchor, manager_id, lock=True)
            already_completed = record["status"] == "completed"
            mutate(cursor, record, state, command)
            if not already_completed:
                record["version"] += 1
        conn.commit()
        remember(record, state)
        return response_for(record, state)
    except HTTPException:
        conn.rollback()
        raise
    except Exception:
        conn.rollback()
        logger.exception("경기 진행 저장 실패")
        raise HTTPException(500, "경기 저장 중 오류가 발생했습니다.")
    finally:
        conn.close()


# [수정 끝]
