# 작업자 : 신현진
# 작업 일 : 2026-10-27

# 본사 팀 관리 조회 API (main.py에서 prefix="/management"로 등록되어 실제 주소 앞에 /management 가 붙음)
#   GET /management/teams                 전체 팀 목록 (팀 등급·전적·팀장·지역·팀원 수)
#       ?keyword= 팀 이름 또는 팀장 이름 검색 / ?category= 종목 (축구, 배구, 농구, 야구)
#   GET /management/teams/{t_id}          팀 1건 상세 (팀 정보 + 팀원 목록 + 전적 + 최근 경기 결과)
#       ?recent_limit= 최근 경기 결과 개수 (기본 5)
# 조회만 하고 받는 값(body)이 없어서 BaseModel class 없음
#
# [팀 관련 테이블]
#   team                 : 팀 기본 정보 (t_id 팀ID, t_name 팀명, t_logo 로고)
#   team_create          : 팀 개설 정보 (c_id_seq 개설한 회원, c_date 개설일, c_category 종목)
#   team_captain_change  : 팀장 변경 기록 (t_c_captain 새 팀장, t_c_date 변경일)
#                          → 가장 최근 기록이 현재 팀장, 기록이 없으면 팀을 개설한 회원이 팀장
#   t_register           : 팀원 등록 (c_id_seq 회원, tr_date 가입일)
#   t_result_record      : 팀 경기 결과 (팀마다 1줄씩 저장)
#                          t_r_r_m_code 경기코드 : 같은 경기를 한 두 팀은 같은 경기코드를 가짐 → 상대 팀을 찾을 때 사용
#                          t_r_r_score 스코어    : "우리팀점수:상대팀점수" 형식 (예: 52:47) → 승/무/패 계산에 사용
#                          m_id 담당 매니저 / g_code 경기 구장 / t_r_r_date 경기일
#
# [팀 등급] DB에 저장된 값이 아니라 승률로 계산해서 붙이는 값 (관리자 목업의 등급 기준)
#   승률 = 승 / 전체 경기 수 × 100 (무승부는 경기 수에만 포함)
#   S : 70% 이상 / A : 55% 이상 / B : 45% 이상 / C : 30% 이상 / D : 30% 미만 / 경기 기록이 없으면 None
import logging
from typing import Optional

import pymysql
from fastapi import APIRouter, HTTPException, Query

from database import connect  # 공용 DB 연결 함수 (python/database.py)

# 이 파일의 API들을 담는 라우터 (main.py에서 prefix="/management"로 등록)
router = APIRouter()
logger = logging.getLogger(__name__)

# 등급 기준 (승률이 위에서부터 처음으로 기준 이상이 되는 등급을 사용)
GRADE_RULES = [
    ("S", 70),
    ("A", 55),
    ("B", 45),
    ("C", 30),
]
GRADE_LOWEST = "D"  # 위 기준을 하나도 넘지 못하면 D 등급

# 경기 결과 이름 (앱에서 "승", "무", "패" 배지로 바로 표시)
RESULT_WIN = "승"
RESULT_DRAW = "무"
RESULT_LOSS = "패"


# 팀 목록·상세에서 공통으로 쓰는 SELECT
# t / tc / cap 는 테이블 별칭 (team / team_create / customer(팀장))
# 안쪽 SELECT(base) : 팀마다 현재 팀장 ID를 먼저 구함
#   COALESCE(A, B) : A가 NULL이면 B를 사용 → 팀장 변경 기록이 없으면 팀을 개설한 회원(tc.c_id_seq)
#   ORDER BY t_c_date DESC LIMIT 1 : 팀장 변경 기록 중 가장 최근 1건
# LEFT JOIN : team_create나 팀장 정보가 없는 팀도 목록에서 빠지지 않게 함 (값은 None)
# member_count : t_register에 등록된 팀원 수 (탈퇴한 회원 c_deletdate 는 제외)
TEAM_SELECT = """
    SELECT base.t_id, base.t_name, base.t_logo, base.category, base.created_date,
        base.captain_id, cap.c_name AS captain_name, cap.c_address AS captain_address,
        (
            SELECT COUNT(*)
            FROM t_register AS tr
            INNER JOIN customer AS mc ON mc.c_id_seq = tr.c_id_seq
            WHERE tr.t_id = base.t_id
                AND mc.c_deletdate IS NULL
        ) AS member_count
    FROM (
        SELECT t.t_id, t.t_name, t.t_logo,
            tc.c_category AS category,
            tc.c_date AS created_date,
            COALESCE(
                (
                    SELECT tcc.t_c_captain
                    FROM team_captain_change AS tcc
                    WHERE tcc.t_id = t.t_id
                    ORDER BY tcc.t_c_date DESC, tcc.t_c_seq DESC
                    LIMIT 1
                ),
                tc.c_id_seq
            ) AS captain_id
        FROM team AS t
        LEFT JOIN team_create AS tc ON tc.t_id = t.t_id
    ) AS base
    LEFT JOIN customer AS cap ON cap.c_id_seq = base.captain_id
"""


# 스코어 문자열 → (우리팀 점수, 상대팀 점수) 숫자로 변환
# 예: "52:47" → (52, 47)
# 형식이 맞지 않으면 (빈 값, "3-2", "A:B" 등) None → 전적 계산에서 제외
def parse_score(score: Optional[str]):
    if not score or ":" not in score:
        return None
    my_text, opponent_text = score.split(":", 1)  # 처음 나오는 ":" 기준으로 둘로 나눔
    if not (my_text.strip().isdigit() and opponent_text.strip().isdigit()):
        return None
    return int(my_text), int(opponent_text)


# 우리팀 점수와 상대팀 점수를 비교해서 승/무/패 결정
def match_result(my_score: int, opponent_score: int) -> str:
    if my_score > opponent_score:
        return RESULT_WIN
    if my_score == opponent_score:
        return RESULT_DRAW
    return RESULT_LOSS


# 승률로 팀 등급 계산 (경기 기록이 없으면 None)
def team_grade(games: int, win_rate: Optional[int]) -> Optional[str]:
    if games == 0:
        return None
    for grade, min_rate in GRADE_RULES:
        if win_rate >= min_rate:
            return grade
    return GRADE_LOWEST


# 팀장 주소 → 지역 (주소 앞 두 단어)
# 예: "서울 마포구 월드컵로 240" → "서울 마포구"
# 팀 테이블에 지역 컬럼이 없어서 팀장 주소로 대신 표시
def region_from_address(address: Optional[str]) -> Optional[str]:
    if not address:
        return None
    return " ".join(address.split()[:2])


# 전체 팀의 경기 결과를 한 번에 읽어서 팀별 전적 계산
# 목록에서는 모든 팀의 등급이, 상세에서는 상대 팀 등급이 필요해서 팀 전체를 한 번에 계산
# 반환 : {t_id: {"wins": 승, "draws": 무, "losses": 패, "games": 경기 수, "win_rate": 승률,
#                "points_for": 득점, "points_against": 실점, "grade": 등급}}
def load_team_stats(cursor) -> dict:
    cursor.execute(
        """
        SELECT t_id, t_r_r_score
        FROM t_result_record
        WHERE t_r_r_score IS NOT NULL
        """
    )
    stats = {}
    for row in cursor.fetchall():
        score = parse_score(row["t_r_r_score"])
        if score is None:
            continue  # 스코어 형식이 잘못된 기록은 전적에서 제외
        my_score, opponent_score = score
        # setdefault : 처음 나온 팀이면 0으로 채운 dict를 만들고, 이미 있으면 그 dict를 그대로 사용
        team = stats.setdefault(row["t_id"], {
            "wins": 0, "draws": 0, "losses": 0, "points_for": 0, "points_against": 0,
        })
        result = match_result(my_score, opponent_score)
        if result == RESULT_WIN:
            team["wins"] += 1
        elif result == RESULT_DRAW:
            team["draws"] += 1
        else:
            team["losses"] += 1
        team["points_for"] += my_score            # 득점 누적
        team["points_against"] += opponent_score  # 실점 누적

    # 경기 수·승률·등급은 모든 기록을 다 센 뒤에 계산
    for team in stats.values():
        team["games"] = team["wins"] + team["draws"] + team["losses"]
        # round : 소수점 첫째 자리에서 반올림한 정수 승률 (예: 66.7 → 67)
        team["win_rate"] = round(team["wins"] / team["games"] * 100)
        team["grade"] = team_grade(team["games"], team["win_rate"])
    return stats


# 경기 기록이 하나도 없는 팀에 쓰는 기본 전적
def empty_stats() -> dict:
    return {
        "wins": 0, "draws": 0, "losses": 0, "games": 0, "win_rate": None,
        "points_for": 0, "points_against": 0, "grade": None,
    }


# DB에서 받은 팀 1줄(dict) + 전적 → 앱으로 보낼 JSON(dict)으로 정리
# DictCursor를 쓰기 때문에 row["컬럼명"]으로 값을 꺼냄
def team_to_dict(row: dict, stats: dict) -> dict:
    return {
        "t_id": row["t_id"],                                         # 팀ID
        "t_name": row["t_name"],                                     # 팀 이름
        "t_logo": row["t_logo"],                                     # 팀 로고 (없으면 None → 앱에서 팀 이름 첫 글자로 표시)
        "category": row["category"],                                 # 종목 (team_create.c_category)
        "created_date": row["created_date"],                         # 팀 생성일 (team_create.c_date)
        "captain_id": row["captain_id"],                             # 팀장 회원ID
        "captain_name": row["captain_name"],                         # 팀장 이름
        "region": region_from_address(row["captain_address"]),      # 지역 (팀장 주소 앞 두 단어)
        "member_count": row["member_count"],                         # 팀원 수
        "wins": stats["wins"],                                       # 승
        "draws": stats["draws"],                                     # 무
        "losses": stats["losses"],                                   # 패
        "games": stats["games"],                                     # 전체 경기 수
        "win_rate": stats["win_rate"],                               # 승률 (%, 경기 기록이 없으면 None)
        "grade": stats["grade"],                                     # 등급 (S/A/B/C/D, 경기 기록이 없으면 None)
    }


# 전체 팀 목록 조회
# keyword가 있으면 팀 이름 또는 팀장 이름에 keyword가 들어간 팀만 조회
# category가 있으면 해당 종목 팀만 조회
# 예: /management/teams
#     /management/teams?keyword=빅맨즈
#     /management/teams?category=농구
@router.get("/teams")
def select_teams(
    keyword: Optional[str] = Query(None, description="팀 이름 또는 팀장 이름 검색"),
    category: Optional[str] = Query(None, description="종목 (축구, 배구, 농구, 야구)"),
):
    connection = None
    try:
        connection = connect()  # DB 연결
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:  # SQL을 실행할 커서 (with가 끝나면 자동으로 닫힘)
            sql = TEAM_SELECT
            conditions = []  # WHERE 뒤에 AND로 이어 붙일 조건들
            params = []      # %s 자리에 순서대로 들어갈 값
            if keyword and keyword.strip():
                # LIKE '%검색어%' : 앞뒤에 무엇이 와도 검색어가 포함되면 조회
                conditions.append("(base.t_name LIKE %s OR cap.c_name LIKE %s)")
                like_keyword = f"%{keyword.strip()}%"
                params.extend([like_keyword, like_keyword])
            if category and category.strip():
                conditions.append("base.category = %s")
                params.append(category.strip())
            if conditions:
                sql += " WHERE " + " AND ".join(conditions)
            sql += " ORDER BY base.t_name"  # 팀 이름 가나다순 정렬
            cursor.execute(sql, params)  # %s 자리에 값이 순서대로 들어감 (SQL 인젝션 방지)
            rows = cursor.fetchall()  # 결과 전체를 dict 목록으로 받음

            stats = load_team_stats(cursor)  # 전체 팀 전적·등급
        teams = [team_to_dict(row, stats.get(row["t_id"], empty_stats())) for row in rows]
        # 팀이 하나도 없으면 빈 리스트 [] 가 나감 (에러 아님)
        return {
            "total": len(teams),  # 전체 팀 수 (목업 오른쪽 위 "전체 9팀")
            "results": teams,
        }
    except pymysql.MySQLError:
        logger.exception("팀 목록 DB 조회 실패")
        raise HTTPException(status_code=500, detail="팀 조회 중 DB 오류가 발생했습니다.")
    except Exception:
        logger.exception("팀 목록 조회 실패")
        raise HTTPException(status_code=500, detail="팀 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()  # 성공/실패 상관없이 DB 연결 종료


# 팀 1건 상세 조회 (팀 정보 + 팀원 목록 + 전적 + 최근 경기 결과)
# 주의: "/teams" 보다 아래에 있어야 하며, 주소의 t_id로 팀 1개만 조회
# 예: /management/teams/5
#     /management/teams/5?recent_limit=2
@router.get("/teams/{t_id}")
def select_team(
    t_id: int,
    # ge=1, le=20 : 1~20 밖의 값이 오면 FastAPI가 자동으로 422 에러 처리
    recent_limit: int = Query(5, ge=1, le=20, description="최근 경기 결과 개수"),
):
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            # 1) 팀 기본 정보
            cursor.execute(TEAM_SELECT + " WHERE base.t_id = %s", (t_id,))  # 값이 1개여도 튜플이라 (t_id,) 처럼 쉼표 필요
            team_row = cursor.fetchone()  # 1건만 받음 (없으면 None)
            if team_row is None:
                raise HTTPException(status_code=404, detail="존재하지 않는 팀입니다.")

            # 2) 팀원 목록
            # tr / c 는 테이블 별칭 (t_register / customer)
            # 탈퇴한 회원(c_deletdate 값이 있음)은 제외, 먼저 가입한 순서대로 정렬
            cursor.execute(
                """
                SELECT tr.c_id_seq, c.c_name, c.c_gender, c.c_phone, c.c_position, tr.tr_date
                FROM t_register AS tr
                INNER JOIN customer AS c ON c.c_id_seq = tr.c_id_seq
                WHERE tr.t_id = %s
                    AND c.c_deletdate IS NULL
                ORDER BY tr.tr_date, tr.tr_seq
                """,
                (t_id,),
            )
            member_rows = cursor.fetchall()

            # 3) 전체 팀 전적 (이 팀 전적 + 상대 팀 등급 표시에 사용)
            stats = load_team_stats(cursor)

            # 4) 최근 경기 결과
            # my / op 는 같은 t_result_record 테이블을 두 번 쓰는 별칭 (my = 이 팀 기록, op = 상대 팀 기록)
            # LEFT JOIN op : 같은 경기코드(t_r_r_m_code)이면서 팀이 다른 기록 = 상대 팀
            #                상대 팀 기록이 아직 없어도 이 팀 경기는 빠지지 않고 나옴 (상대 팀 값은 None)
            # LEFT JOIN match_manager : 담당 매니저 이름 / LEFT JOIN ground : 경기 구장 이름
            # 경기일 최신순으로 recent_limit 개만 조회
            cursor.execute(
                """
                SELECT my.t_r_r_seq, my.t_r_r_m_code, my.t_r_r_date, my.t_r_r_score,
                    my.g_code, g.g_name,
                    my.m_id, mm.m_name,
                    op.t_id AS opponent_t_id, ot.t_name AS opponent_t_name
                FROM t_result_record AS my
                LEFT JOIN t_result_record AS op
                    ON op.t_r_r_m_code = my.t_r_r_m_code
                    AND op.t_id <> my.t_id
                LEFT JOIN team AS ot ON ot.t_id = op.t_id
                LEFT JOIN match_manager AS mm ON mm.m_id = my.m_id
                LEFT JOIN ground AS g ON g.g_code = my.g_code
                WHERE my.t_id = %s
                ORDER BY my.t_r_r_date DESC, my.t_r_r_seq DESC
                LIMIT %s
                """,
                (t_id, recent_limit),
            )
            match_rows = cursor.fetchall()

        team_stats = stats.get(t_id, empty_stats())
        result = team_to_dict(team_row, team_stats)

        # 득점 / 실점 / 득실차 (스코어가 저장된 전체 경기 기준)
        result["points_for"] = team_stats["points_for"]
        result["points_against"] = team_stats["points_against"]
        result["points_diff"] = team_stats["points_for"] - team_stats["points_against"]

        # 팀원 목록 (현재 팀장이면 is_captain = True)
        result["members"] = [
            {
                "c_id_seq": row["c_id_seq"],                          # 회원ID
                "c_name": row["c_name"],                              # 이름
                "c_gender": row["c_gender"],                          # 성별
                "c_phone": row["c_phone"],                            # 전화번호
                "c_position": row["c_position"],                      # 선호 포지션
                "tr_date": row["tr_date"],                            # 팀 가입일
                "is_captain": row["c_id_seq"] == team_row["captain_id"],  # 팀장 여부
            }
            for row in member_rows
        ]

        # 최근 경기 결과
        recent_matches = []
        for row in match_rows:
            score = parse_score(row["t_r_r_score"])
            opponent_stats = stats.get(row["opponent_t_id"], empty_stats())
            recent_matches.append({
                "t_r_r_m_code": row["t_r_r_m_code"],                 # 경기코드
                "t_r_r_date": row["t_r_r_date"],                     # 경기일
                "opponent_t_id": row["opponent_t_id"],               # 상대 팀ID (상대 기록이 없으면 None)
                "opponent_t_name": row["opponent_t_name"],           # 상대 팀 이름
                "opponent_grade": opponent_stats["grade"],           # 상대 팀 등급
                "score": row["t_r_r_score"],                         # 스코어 (우리팀:상대팀)
                # 승/무/패 (스코어가 없거나 형식이 잘못되면 None)
                "result": None if score is None else match_result(*score),
                "g_code": row["g_code"],                             # 경기 구장코드
                "g_name": row["g_name"],                             # 경기 구장 이름
                "m_id": row["m_id"],                                 # 담당 매니저ID
                "m_name": row["m_name"],                             # 담당 매니저 이름
            })
        result["recent_matches"] = recent_matches
        return result
    except HTTPException:
        raise  # 위에서 만든 404는 500으로 바뀌지 않게 그대로 전달
    except pymysql.MySQLError:
        logger.exception("팀 상세 DB 조회 실패")
        raise HTTPException(status_code=500, detail="팀 조회 중 DB 오류가 발생했습니다.")
    except Exception:
        logger.exception("팀 상세 조회 실패")
        raise HTTPException(status_code=500, detail="팀 조회에 실패했습니다.")
    finally:
        if connection is not None:
            connection.close()

# 최종 수정 일 : 2026-10-27
