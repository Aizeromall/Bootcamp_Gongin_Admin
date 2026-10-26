# 작업자 : 김병재
# 최초 작업 일 : 2026-10-26

# 관리자 신고 API(list/detail/review)가 함께 쓰는 공통 코드
#   - 신고 유형/종목 이름표, 처리 상태 판단 규칙
#   - report 조회 SQL, r_reason 분리, 경기 정보 조회, 응답 dict 만들기
#
# [처리 상태] report 테이블에 상태 컬럼이 없어서 아래 규칙으로 판단
#   처리완료 : 신고일(r_date) 이후 신고 대상(r_person)에게 c_sanction(제재)이 등록됨 (사용자 앱 신고내역과 동일 기준)
#   심의중   : h_id(처리자)에 심의를 시작한 본사 직원 ID가 있음 (제재는 아직 없음)
#   접수     : h_id가 NULL (아직 아무도 심의를 시작하지 않음)
#   기각     : 저장할 컬럼이 없어서 아직 지원하지 않음 (제재/기각 백엔드 작업 때 다시 정함)
import re

# 신고 유형 번호 매핑 (사용자 앱 insert_report.py와 동일, r_option 컬럼에는 번호 문자열이 저장됨)
REPORT_OPTION = {
    "1": "폭언·욕설",
    "2": "폭행·위협",
    "3": "고의적 거친 플레이",
    "4": "노쇼·지각",
    "5": "기타",
}

# 종목 코드(c_result_record.e_code) → 종목명. 목록에 없는 코드는 'ETC'(기타)로 묶음
SPORT_NAME = {
    "SOCCER": "축구",
    "VOLLEYBALL": "배구",
    "BASKETBALL": "농구",
    "BASEBALL": "야구",
}
SPORT_ETC = "ETC"

# 처리 상태 번호 → 이름. state_text를 화면 탭/배지에 그대로 사용
STATE_RECEIVED = 0   # 접수
STATE_REVIEWING = 1  # 심의중
STATE_DONE = 2       # 처리완료
STATE_TEXT = {STATE_RECEIVED: "접수", STATE_REVIEWING: "심의중", STATE_DONE: "처리완료"}

# 신고 작성 시 r_reason 앞에 붙여 저장한 "[경기:경기코드] 상황 설명" 분리용
# 경기코드 = 구장코드_날짜_시작시간 (예: 1_20261026_180000)
REASON_PATTERN = re.compile(r"^\[경기:((\d+)_(\d{8})_(\d{6}))\]\s*(.*)$", re.DOTALL)

# 신고 조회 SQL (DictCursor 전용). 신고자/신고 대상 이름은 customer, 처리자 이름은 headquarter에서 가져옴
# sanctioned: 신고일 이후 신고 대상에게 제재가 있는지 (EXISTS라서 제재가 여러 건이어도 신고가 중복으로 나오지 않음)
SELECT_REPORT = """
    SELECT r.r_seq, r.c_id_seq, rc.c_name AS reporter_name,
           r.r_person, tc.c_name AS target_name,
           r.h_id, h.h_name, r.r_date, r.r_option, r.r_reason, r.r_evidence,
           EXISTS (
               SELECT 1 FROM c_sanction AS s
               WHERE s.c_id_seq = r.r_person AND s.cs_date >= r.r_date
           ) AS sanctioned
    FROM report AS r
    LEFT JOIN customer AS rc ON rc.c_id_seq = r.c_id_seq
    LEFT JOIN customer AS tc ON tc.c_id_seq = r.r_person
    LEFT JOIN headquarter AS h ON h.h_id = r.h_id
    """


# 신고 1줄(dict)의 처리 상태 번호 판단: 제재가 있으면 처리완료 > 처리자가 있으면 심의중 > 접수
def get_state(row: dict) -> int:
    if row["sanctioned"]:
        return STATE_DONE
    if row["h_id"] is not None:
        return STATE_REVIEWING
    return STATE_RECEIVED


# 경기코드(c_r_r_code)들로 경기 정보를 한 번에 조회 (신고마다 쿼리하지 않기 위함)
# 같은 경기코드에 회원 기록이 여러 줄이라 GROUP BY로 1건으로 합침
# 반환: {경기코드: {"e_code", "m_id", "m_name", "g_name"}}
def fetch_match_info(cursor, codes: set) -> dict:
    if not codes:
        return {}
    placeholders = ", ".join(["%s"] * len(codes))
    cursor.execute(
        f"""
        SELECT x.c_r_r_code, MAX(x.e_code) AS e_code, MIN(x.m_id) AS m_id,
               MIN(m.m_name) AS m_name, MIN(g.g_name) AS g_name
        FROM c_result_record AS x
        LEFT JOIN match_manager AS m ON m.m_id = x.m_id
        LEFT JOIN ground AS g ON g.g_code = x.g_code
        WHERE x.c_r_r_code IN ({placeholders})
        GROUP BY x.c_r_r_code
        """,
        tuple(codes),
    )
    return {row["c_r_r_code"]: row for row in cursor.fetchall()}


# DB에서 받은 신고 1줄(dict) → 화면으로 보낼 JSON(dict)으로 정리
# match_info: fetch_match_info() 결과 {경기코드: 경기 정보}
def build_report(row: dict, match_info: dict) -> dict:
    reason = row["r_reason"] or ""
    found = REASON_PATTERN.match(reason)

    match_code = None
    match_date = None
    match_time = None
    content = reason
    if found:
        match_code = found.group(1)
        ymd, hms = found.group(3), found.group(4)
        match_date = f"{ymd[:4]}-{ymd[4:6]}-{ymd[6:]}"
        match_time = f"{hms[:2]}:{hms[2:4]}"
        content = found.group(5)  # [경기:...] 부분을 뺀 순수 상황 설명

    # 경기 기록이 지워졌거나 경기코드가 없는 신고는 경기 정보를 비워 둠
    info = match_info.get(match_code) or {}
    e_code = info.get("e_code")
    sport = e_code if e_code in SPORT_NAME else SPORT_ETC

    state = get_state(row)
    return {
        "r_seq": row["r_seq"],                                                  # 신고번호
        "r_date": row["r_date"],                                                # 신고일
        "state": state,                                                         # 0 = 접수 / 1 = 심의중 / 2 = 처리완료
        "state_text": STATE_TEXT[state],
        "r_option": row["r_option"],                                            # 신고 유형 번호
        "r_option_name": REPORT_OPTION.get(row["r_option"] or "", "기타"),      # 신고 유형명
        "c_id_seq": row["c_id_seq"],                                            # 신고자 회원 아이디
        "reporter_name": row["reporter_name"],                                  # 신고자 이름
        "r_person": row["r_person"],                                            # 피신고자 회원 아이디
        "target_name": row["target_name"],                                      # 피신고자 이름
        "h_id": row["h_id"],                                                    # 심의를 시작한 본사 직원 아이디 (접수면 None)
        "h_name": row["h_name"],                                                # 심의를 시작한 본사 직원 이름
        "c_r_r_code": match_code,                                               # 경기코드 ([경기 기록 보기] 버튼에 사용)
        "g_name": info.get("g_name"),                                           # 경기 구장명
        "match_date": match_date,                                               # 경기 날짜
        "match_time": match_time,                                               # 경기 시작시간
        "sport": sport,                                                         # 종목 코드 (SOCCER 등, 모르는 코드는 ETC)
        "sport_name": SPORT_NAME.get(sport, "기타"),                            # 종목명
        "m_id": info.get("m_id"),                                               # 담당 매니저 아이디
        "m_name": info.get("m_name"),                                           # 담당 매니저 이름
        "r_reason": content,                                                    # 상황 설명
        "r_evidence": row["r_evidence"].split(",") if row["r_evidence"] else [],  # 증거 자료 목록
    }


# 조건(where_sql)에 맞는 신고를 조회해 화면용 dict 목록으로 반환 (최신순)
# where_sql 예: "WHERE r.r_seq = %s" (조건 없이 전체면 빈 문자열)
def fetch_reports(cursor, where_sql: str = "", params: tuple = ()) -> list:
    cursor.execute(
        SELECT_REPORT + where_sql + " ORDER BY r.r_date DESC, r.r_seq DESC",
        params,
    )
    rows = cursor.fetchall()

    # 신고에 적힌 경기코드를 모아 경기 정보를 한 번에 조회
    codes = set()
    for row in rows:
        found = REASON_PATTERN.match(row["r_reason"] or "")
        if found:
            codes.add(found.group(1))
    match_info = fetch_match_info(cursor, codes)

    return [build_report(row, match_info) for row in rows]


# 신고 1건 조회. 없으면 None
def fetch_report(cursor, r_seq: int):
    reports = fetch_reports(cursor, "WHERE r.r_seq = %s", (r_seq,))
    return reports[0] if reports else None

# 최종 수정 일 : 2026-10-26
