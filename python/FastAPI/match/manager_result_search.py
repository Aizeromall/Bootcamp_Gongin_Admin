# 수정 일 : 2026-10-29 / 작업자 : 양태건
# 기존 결과 테이블을 읽기만 합니다. 점수 변동·새 테이블·컬럼을 생성하지 않습니다.
from collections import defaultdict
from datetime import datetime
from zoneinfo import ZoneInfo
import logging
from typing import Literal

import pymysql
from fastapi import APIRouter, Depends, HTTPException, Query
from database import connect
from .manager_session import require_manager
from .match_result_insert import STAT_KEYS, RATING_START, rating_tier, unpack_statcode
from .team_match_search import parse_score, TEAM_MATCH_SELECT, team_match_to_dict
from .match_operations import match_list, team_points
from .match_schedule import NOT_CANCELED_CONDITION

router = APIRouter(prefix="/match/manager", tags=["매니저 결과 조회"])
logger = logging.getLogger(__name__)


def score_value(value):
    return parse_score(str(value)) if value is not None else None


def member_document(row):
    rating = row.get("c_rating")
    rating = int(rating) if rating is not None else None
    # 수정 일 : 2026-10-30 / 작업자 : 양태건
    # SELECT rr.*에 포함된 경기 전·후 점수로 변동을 반환합니다.
    # 현재 등급 점수나 서버 메모리로 과거 NULL 기록을 추정하지 않습니다.
    before, after = row.get("c_r_r_rating_before"), row.get("c_r_r_rating_after")
    # 수정 일 : 2026-10-30 / 작업자 : 양태건
    # 사용자가 확인한 최초 경기의 기존 NULL 이력만 복원합니다.
    # 담당자·조회 필터와 무관하게 전체 완료 경기 수가 1인 회원만 허용합니다.
    if before is None and after is None and row.get("completed_match_count") == 1 and rating is not None:
        before, after = RATING_START, rating
    rating_change = after - before if before is not None and after is not None else None
    return {
        "c_id_seq": row["c_id_seq"], "name": row.get("c_name") or row["c_id_seq"],
        "position": row.get("c_position"), "team": row.get("c_r_r_team"),
        "stats": unpack_statcode(row.get("c_r_r_statcode")),
        "record_text": row.get("c_r_r_statcode") if not unpack_statcode(row.get("c_r_r_statcode")) else None,
        "current_rating": rating, "current_tier": rating_tier(rating) if rating is not None else None,
        "rating_before": before, "rating_after": after,
        "tier_after": rating_tier(after) if after is not None else None,
        "rating_change": rating_change,
    }


def group_results(member_rows, team_rows, manager_id):
    members, teams = defaultdict(list), defaultdict(list)
    for row in member_rows:
        members[str(row["c_r_r_code"])].append(row)
    for row in team_rows:
        teams[str(row["t_r_r_m_code"])].append(row)
    records = []
    for code in members.keys() | teams.keys():
        rows, team_records = members.get(code, []), teams.get(code, [])
        kind = "pickup" if "_" in code else "team"
        # 수정 일 : 2026-10-30 / 작업자 : 양태건
        # 최종 등록으로 차감 이력이 저장된 결석자는 별도 명단에 표시합니다.
        absentees = [r for r in rows if r.get("c_r_r_attendance") == 0
                     and r.get("c_r_r_rating_before") is not None
                     and r.get("c_r_r_rating_after") is not None]
        # 출석만 저장된 행은 경기 완료 결과가 아닙니다.
        rows = [r for r in rows if r.get("c_r_r_score") is not None]
        if not rows and not team_records:
            continue
        origin = rows[0] if rows else team_records[0]
        sport_codes = {r.get("e_code") for r in rows + team_records if r.get("e_code")}
        sport = next(iter(sport_codes)) if len(sport_codes) == 1 else None
        # 과거 스탯은 기록에 저장된 팀명으로 묶습니다. 현재 소속으로 과거 팀을 바꾸지 않습니다.
        sides = defaultdict(dict)
        for row in rows:
            sides[row.get("c_r_r_team") or "팀명 미기록"][row["c_id_seq"]] = member_document(row)
        ordered_teams = sorted(team_records, key=lambda r: (r.get("t_id") != r.get("home_t_id"), r.get("t_r_r_seq", 0)))
        pair = score_value(ordered_teams[0].get("t_r_r_score")) if ordered_teams else score_value(rows[0].get("c_r_r_score"))
        side_names = list(sides)
        if kind == "pickup" and pair and len(side_names) == 2 and sport in STAT_KEYS:
            totals = []
            for side_name in side_names:
                sums = {key: sum(player["stats"].get(key, 0) for player in sides[side_name].values()) for key, _, _ in STAT_KEYS[sport]}
                totals.append(sums)
            calculated = [team_points(sport, totals[0], totals[1]), team_points(sport, totals[1], totals[0])]
            if calculated == [pair[1], pair[0]] and pair[0] != pair[1]:
                side_names.reverse()
        if kind == "team" and ordered_teams:
            display_names = [r.get("t_name") or "팀명 미기록" for r in ordered_teams[:2]]
        else:
            display_names = side_names[:2]
        while len(display_names) < 2:
            display_names.append("팀명 미기록")
        # 실력매칭의 최종 스코어는 서버가 저장한 A:B 그대로 사용합니다.
        saved_date = origin.get("c_r_r_date") or origin.get("t_r_r_date")
        game_date, game_time = None, None
        if kind == "pickup":
            parts = code.rsplit("_", 2)
            if len(parts) == 3:
                try:
                    parsed = datetime.strptime(parts[1] + parts[2], "%Y%m%d%H%M%S")
                    game_date, game_time = parsed.date().isoformat(), parsed.strftime("%H:%M")
                except ValueError:
                    pass
        elif ordered_teams and ordered_teams[0].get("team_start"):
            parsed = ordered_teams[0]["team_start"]
            game_date, game_time = parsed.date().isoformat(), parsed.strftime("%H:%M")
        records.append({
            "code": code, "kind": kind, "e_code": sport,
            "g_code": origin.get("g_code"), "ground": origin.get("g_name"),
            "date": game_date, "time": game_time, "recorded_at": saved_date,
            "manager_name": origin.get("m_name"),
            "home": display_names[0], "away": display_names[1],
            "raw_score": None if pair else origin.get("c_r_r_score") or origin.get("t_r_r_score"),
            "home_score": pair[0] if pair else None, "away_score": pair[1] if pair else None,
            "stat_columns": [{"key": key, "label": label} for key, label, _ in STAT_KEYS.get(sport, [])],
            "sides": [{"name": name, "members": list(players.values())} for name, players in sides.items()]
                + ([{"name": "결석 · 노쇼 패널티", "members": list({r["c_id_seq"]: member_document(r) for r in absentees}.values())}]
                   if absentees else []),
            "team_summary": [{
                "name": r.get("t_name"), "t_id": r["t_id"],
                "score": (score_value(r.get("t_r_r_score")) or (None, None))[0],
                "result": ("승" if v[0] > v[1] else "패" if v[0] < v[1] else "무") if (v := score_value(r.get("t_r_r_score"))) else None,
                "stats": unpack_statcode(r.get("t_r_r_statcode")),
                "current_rating": r.get("t_rating"), "rating_change": None,
            } for r in ordered_teams],
        })
    return sorted(records, key=lambda r: (str(r["date"] or ""), str(r["time"] or ""), str(r["recorded_at"] or "")), reverse=True)


def read_results(manager_id, code=None):
    conn = None
    try:
        conn = connect()
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            member_sql = """SELECT rr.*, c.c_name, c.c_position, c.c_rating, g.g_name, mm.m_name,
                (SELECT COUNT(DISTINCT history.c_r_r_code) FROM c_result_record history
                 WHERE history.c_id_seq=rr.c_id_seq AND history.c_r_r_score IS NOT NULL) AS completed_match_count
                FROM c_result_record rr LEFT JOIN customer c ON c.c_id_seq=rr.c_id_seq
                LEFT JOIN ground g ON g.g_code=rr.g_code LEFT JOIN match_manager mm ON mm.m_id=rr.m_id
                WHERE rr.m_id=%s AND (rr.c_r_r_score IS NOT NULL OR
                    (rr.c_r_r_attendance=0 AND rr.c_r_r_rating_before IS NOT NULL
                     AND rr.c_r_r_rating_after IS NOT NULL))"""
            params = [manager_id]
            if code is not None:
                member_sql += " AND rr.c_r_r_code=%s"
                params.append(code)
            cursor.execute(member_sql + " ORDER BY rr.c_r_r_seq", params)
            members = cursor.fetchall()
            # 수정 일 : 2026-10-29 / 작업자 : 양태건
            # 실제 경기코드 컬럼은 utf8mb4_unicode_ci입니다. 숫자→문자 변환도
            # 같은 규칙으로 비교해 연결 기본값(0900_ai_ci)과의 1267 충돌을 막습니다.
            team_sql = """SELECT rr.*, t.t_name, t.t_rating, g.g_name, mm.m_name, tm.home_t_id, tm.team_start
                FROM t_result_record rr LEFT JOIN team t ON t.t_id=rr.t_id
                LEFT JOIN ground g ON g.g_code=rr.g_code LEFT JOIN match_manager mm ON mm.m_id=rr.m_id
                LEFT JOIN team_match tm ON CAST(tm.team_code AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci=rr.t_r_r_m_code
                WHERE rr.m_id=%s"""
            params = [manager_id]
            if code is not None:
                team_sql += " AND rr.t_r_r_m_code=%s"
                params.append(code)
            cursor.execute(team_sql + " ORDER BY rr.t_r_r_seq", params)
            teams = cursor.fetchall()
        return group_results(members, teams, manager_id)
    except pymysql.MySQLError:
        logger.exception("매니저 결과 조회 실패")
        raise HTTPException(500, "경기 결과를 불러오지 못했습니다.")
    finally:
        if conn is not None:
            conn.close()


@router.get("/results")
def results(kind: Literal["pickup", "team"] = Query(...), e_code: str | None = None, manager_id: str = Depends(require_manager)):
    rows = [r for r in read_results(manager_id) if r["kind"] == kind and (e_code is None or r["e_code"] == e_code)]
    # 목록에는 개인정보·개인 스탯을 포함하지 않습니다.
    return {"results": [{k: v for k, v in row.items() if k not in {"sides", "team_summary"}} for row in rows]}


@router.get("/results/{code}")
def result_detail(code: str, manager_id: str = Depends(require_manager)):
    rows = read_results(manager_id, code)
    if not rows:
        raise HTTPException(404, "등록한 경기 결과가 없습니다.")
    return rows[0]

# 최종 수정 일 : 2026-10-29 / 작업자 : 양태건


@router.get("/upcoming")
def upcoming(manager_id: str = Depends(require_manager)):
    """오늘 이후 모든 예정 경기. 기존 운영 조회와 배정표 기준 팀 경기만 읽습니다."""
    today = datetime.now(ZoneInfo("Asia/Seoul")).date()
    operations = [row for row in match_list(manager_id)["results"]
                  if row["status"] in {"attendance", "teams"} and str(row["r_date"]) >= today.isoformat()]
    conn = None
    try:
        conn = connect()
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            if operations:
                placeholders = ",".join(["%s"] * len(operations))
                cursor.execute(f"SELECT r.r_seq FROM reservation r WHERE r.r_seq IN ({placeholders}) AND r.reservation_category=1 AND {NOT_CANCELED_CONDITION}", [row["r_seq"] for row in operations])
                active = {row["r_seq"] for row in cursor.fetchall()}
                operations = [row for row in operations if row["r_seq"] in active]
            # 수정 일 : 2026-10-29 / 작업자 : 양태건
            # 예정 경기의 결과 유무 비교도 같은 경기코드 정렬 규칙을 사용합니다.
            cursor.execute(TEAM_MATCH_SELECT + " WHERE rm.m_id=%s AND DATE(base.team_start)>=%s AND NOT EXISTS "
                           "(SELECT 1 FROM t_result_record rr WHERE rr.t_r_r_m_code=CAST(base.team_code AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci) "
                           "ORDER BY base.team_start, base.team_code", (manager_id, today))
            rows = cursor.fetchall()
        teams = [team_match_to_dict(row, {}, {}) for row in rows]
        return {"operations": operations, "teams": [row for row in teams if row["status"] == "scheduled"]}
    except pymysql.MySQLError:
        logger.exception("예정 경기 조회 실패")
        raise HTTPException(500, "예정 경기를 불러오지 못했습니다.")
    finally:
        if conn is not None:
            conn.close()

# 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

@router.get("/teams/{code}/roster")
def team_roster(code: int, manager_id: str = Depends(require_manager)):
    """담당 팀 경기의 실제 시간대 예약자 출전·출석 명단."""
    conn = None
    try:
        conn = connect()
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute(TEAM_MATCH_SELECT + " WHERE base.team_code=%s AND rm.m_id=%s", (code, manager_id))
            match = cursor.fetchone()
            if match is None:
                raise HTTPException(404, "담당하는 팀 경기가 아닙니다.")
            # 수정 일 : 2026-10-30 / 작업자 : 양태건
            # 전체 팀원 대신 운영 API와 동일한 시간대 예약 명단을 반환합니다.
            from .team_match_operations import load_team
            from .match_operations import _MATCH_LOCK
            with _MATCH_LOCK:
                _, state = load_team(cursor, code, manager_id)
        return {"members": [{"r_seq": p["r_seq"], "name": p["c_name"],
                  "c_id_seq": p["c_id_seq"], "position": p["c_position"],
                  "team": state["team_names"][0 if state["fixed_sides"][str(p["r_seq"])] == "A" else 1],
                  "current_rating": p["c_rating"],
                  "current_tier": rating_tier(int(p["c_rating"])) if p["c_rating"] is not None else None,
                  "attendance": state["attendance"].get(str(p["r_seq"]))}
                 for p in state["players"]], "attendance_supported": True}
    except pymysql.MySQLError:
        logger.exception("팀 경기 명단 조회 실패")
        raise HTTPException(500, "팀 경기 명단을 불러오지 못했습니다.")
    finally:
        if conn is not None:
            conn.close()

# 최종 수정 일 : 2026-10-29 / 작업자 : 양태건

# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
