# 작업자 : 김병재
# 최초 작업 일 : 2026-10-27

# 관리자 제재·이의신청 API(list_appeal / list_sanction / detail_appeal / review_appeal)가 함께 쓰는 공통 코드
#   - 종목/상태 이름표, 이의신청(appeal) a_reason 분리, 제재(c_sanction) cs_detail 분리
#   - 제재·이의신청 조회 SQL과 화면용 dict 만들기, 탭 건수 계산
#
# [cs_detail 형식] 사용자 앱 제재 내역과 같은 형식: "[제재종류] 제재 내용" (예: "[경고] 폭언 비매너")
#
# [a_reason 형식] appeal 테이블에는 제재 번호·결과 컬럼이 없어서 a_reason 앞에 대괄호 태그를 붙여 저장 (태그 순서는 상관없음)
#   "[제재:12][사유:사실과 다름][증빙:링크1,링크2] 상세 내용"
#     제재 : 이의신청 대상 제재 번호 (c_sanction.cs_seq)
#     사유 : 이의신청 사유 종류 (화면 제목의 "사실과 다름")
#     증빙 : 증빙 링크 (쉼표로 이어 저장). a_evidence는 50자라 링크가 안 들어가서 a_reason에 저장하고, a_evidence에 값이 있으면 함께 읽음
#     결과 : 본사 처리 결과 "인용" 또는 "기각" (결과 처리는 다음 작업, 지금은 읽기만 지원)
#
# [이의신청 상태] appeal 테이블에 상태 컬럼이 없어서 아래 규칙으로 판단
#   인용 / 기각 : a_reason에 [결과:인용] 또는 [결과:기각] 태그가 있음
#   재심의 중   : h_id에 재심의를 시작한 본사 직원 ID가 있고 결과는 아직 없음
#   접수        : h_id가 NULL
import re
from datetime import datetime, timedelta

# 이의신청 상태 번호 → 이름
STATE_RECEIVED = 0   # 접수
STATE_REVIEWING = 1  # 재심의 중
STATE_ACCEPTED = 2   # 인용
STATE_REJECTED = 3   # 기각
STATE_TEXT = {
    STATE_RECEIVED: "접수",
    STATE_REVIEWING: "재심의 중",
    STATE_ACCEPTED: "인용",
    STATE_REJECTED: "기각",
}
RESULT_STATE = {"인용": STATE_ACCEPTED, "기각": STATE_REJECTED}

# 제재 종류 이름 / 경고 소멸 기준 (사용자 앱 sanction/list_sanction.py와 같은 규칙)
TYPE_WARNING = "경고"
TYPE_ETC = "기타"
WARNING_EXPIRE_DAYS = 90  # 경고는 제재일로부터 90일 후 소멸

# 회원 선호 종목(customer.c_prefer_stock) → 종목 코드/종목명. 목록에 없는 값은 'ETC'(기타)로 묶음
# 제재에는 종목 정보가 없어서 제재받은 회원의 선호 종목을 종목으로 사용 (1 = 축구는 경기 기록 코드에서 확인, 나머지는 화면 칩 순서 기준 추정)
SPORT_BY_PREFER = {
    "1": "SOCCER",
    "2": "VOLLEYBALL",
    "3": "BASKETBALL",
    "4": "BASEBALL",
}
SPORT_NAME = {
    "SOCCER": "축구",
    "VOLLEYBALL": "배구",
    "BASKETBALL": "농구",
    "BASEBALL": "야구",
}
SPORT_ETC = "ETC"

# 대괄호 태그 하나("[이름:값]")를 문자열 맨 앞에서 떼어 내는 패턴
TAG_PATTERN = re.compile(r"^\[([^\[\]:]+):([^\[\]]*)\]\s*")
# cs_detail 앞의 "[제재종류] 제재 내용" 분리용
DETAIL_PATTERN = re.compile(r"^\[([^\[\]]+)\]\s*(.*)$", re.DOTALL)

# 제재 조회 SQL (DictCursor 전용). 회원 이름/선호 종목은 customer, 처리자 이름은 headquarter에서 가져옴
SELECT_SANCTION = """
    SELECT s.cs_seq, s.c_id_seq, c.c_name, c.c_prefer_stock, s.h_id, h.h_name, s.cs_date, s.cs_detail
    FROM c_sanction AS s
    LEFT JOIN customer AS c ON c.c_id_seq = s.c_id_seq
    LEFT JOIN headquarter AS h ON h.h_id = s.h_id
    ORDER BY s.cs_date ASC, s.cs_seq ASC
    """

# 이의신청 조회 SQL (DictCursor 전용). 신청 회원 이름/선호 종목은 customer, 재심의 처리자 이름은 headquarter에서 가져옴
SELECT_APPEAL = """
    SELECT a.a_seq, a.c_id_seq, c.c_name, c.c_prefer_stock, a.h_id, h.h_name,
           a.a_date, a.a_reason, a.a_evidence
    FROM appeal AS a
    LEFT JOIN customer AS c ON c.c_id_seq = a.c_id_seq
    LEFT JOIN headquarter AS h ON h.h_id = a.h_id
    ORDER BY a.a_date DESC, a.a_seq DESC
    """


# 회원 선호 종목 값 → 종목 코드 (모르는 값이나 NULL은 ETC)
def get_sport(prefer_stock) -> str:
    return SPORT_BY_PREFER.get(str(prefer_stock), SPORT_ETC) if prefer_stock is not None else SPORT_ETC


# a_reason 앞에 붙은 "[이름:값]" 태그들을 모두 떼어 {이름: 값}과 나머지 본문으로 반환
def parse_appeal_reason(reason: str):
    tags = {}
    text = reason or ""
    while True:
        found = TAG_PATTERN.match(text)
        if not found:
            break
        tags[found.group(1).strip()] = found.group(2).strip()
        text = text[found.end():]
    return tags, text


# 제재 전체를 조회해 화면용 dict 목록(제재일 오름차순)으로 반환
# 경고 N회의 N은 "같은 회원의 경고 중 몇 번째인지"를 제재일 순으로 센 값
def fetch_sanctions(cursor, now: datetime) -> list:
    cursor.execute(SELECT_SANCTION)
    rows = cursor.fetchall()

    warning_order = {}  # 회원별로 지금까지 센 경고 수
    result = []
    for row in rows:
        detail = row["cs_detail"] or ""
        found = DETAIL_PATTERN.match(detail)
        sanction_type = found.group(1).strip() if found else TYPE_ETC
        content = found.group(2) if found else detail  # [제재종류] 부분을 뺀 순수 제재 내용

        # 소멸은 경고에만 적용 (이용정지 등은 소멸일이 없음)
        expire_at = row["cs_date"] + timedelta(days=WARNING_EXPIRE_DAYS) if sanction_type == TYPE_WARNING else None
        expired = expire_at is not None and expire_at <= now

        # "경고 1회 · 10.14" 형태의 제재 이름표. 경고가 아니면 "이용정지 · 10.14"처럼 종류만 사용
        date_text = f"{row['cs_date'].month}.{row['cs_date'].day}"
        if sanction_type == TYPE_WARNING:
            warning_order[row["c_id_seq"]] = warning_order.get(row["c_id_seq"], 0) + 1
            label = f"{TYPE_WARNING} {warning_order[row['c_id_seq']]}회 · {date_text}"
        else:
            label = f"{sanction_type} · {date_text}"

        sport = get_sport(row["c_prefer_stock"])
        result.append({
            "cs_seq": row["cs_seq"],                                      # 제재번호
            "c_id_seq": row["c_id_seq"],                                  # 제재받은 회원 아이디
            "member_name": row["c_name"],                                 # 제재받은 회원 이름
            "cs_date": row["cs_date"],                                    # 제재일
            "sanction_type": sanction_type,                               # 제재 종류 (경고 / 이용정지 / 기타)
            "label": label,                                               # 화면용 제재 이름표 (예: 경고 1회 · 10.14)
            "cs_detail": content,                                         # 제재 내용 (예: 폭언·욕설 (10/11 고척))
            "expired": expired,                                           # 소멸 여부
            "expire_date": expire_at.date().isoformat() if expire_at else None,  # 경고 소멸일
            "tag": "소멸" if expired else "유효",                         # 화면 태그 (유효 / 소멸)
            "h_id": row["h_id"],                                          # 제재 처리 본사 직원 아이디
            "h_name": row["h_name"],                                      # 제재 처리 본사 직원 이름
            "sport": sport,                                               # 종목 코드 (회원 선호 종목 기준)
            "sport_name": SPORT_NAME.get(sport, "기타"),                  # 종목명
        })
    return result


# 이의신청 상태 번호 판단: 결과 태그가 있으면 인용/기각 > 처리자가 있으면 재심의 중 > 접수
def get_state(row: dict, tags: dict) -> int:
    if tags.get("결과") in RESULT_STATE:
        return RESULT_STATE[tags["결과"]]
    if row["h_id"] is not None:
        return STATE_REVIEWING
    return STATE_RECEIVED


# 이의신청 1줄(dict) → 화면으로 보낼 JSON(dict)으로 정리
# sanctions_by_seq: fetch_sanctions() 결과를 {cs_seq: 제재}로 바꾼 것 (대상 제재 연결용)
def build_appeal(row: dict, sanctions_by_seq: dict) -> dict:
    tags, body = parse_appeal_reason(row["a_reason"])
    state = get_state(row, tags)

    # 증빙 링크: [증빙:...] 태그(쉼표로 구분)와 a_evidence에 든 값을 합침 (중복 제거, 순서 유지)
    evidence = []
    for raw in (tags.get("증빙", ""), row["a_evidence"] or ""):
        for link in raw.split(","):
            link = link.strip()
            if link and link not in evidence:
                evidence.append(link)

    # 대상 제재 연결: [제재:번호] 태그가 숫자가 아니거나 제재가 없으면 None
    cs_seq = int(tags["제재"]) if tags.get("제재", "").isdigit() else None
    sanction = sanctions_by_seq.get(cs_seq)

    reason_type = tags.get("사유")
    # 종목: 이의신청한 회원(= 제재받은 회원)의 선호 종목
    sport = get_sport(row["c_prefer_stock"])
    return {
        "a_seq": row["a_seq"],                                  # 이의신청번호
        "a_date": row["a_date"],                                # 신청일
        "state": state,                                         # 0 = 접수 / 1 = 재심의 중 / 2 = 인용 / 3 = 기각
        "state_text": STATE_TEXT[state],
        "c_id_seq": row["c_id_seq"],                            # 신청 회원 아이디
        "member_name": row["c_name"],                           # 신청 회원 이름
        "reason_type": reason_type,                             # 이의신청 사유 종류 (예: 사실과 다름)
        "title": f"{row['c_name']} · {reason_type}" if reason_type else row["c_name"],  # 목록 제목 (예: 김민준 · 사실과 다름)
        "a_reason": body,                                       # 이의신청 상세 내용
        "a_evidence": evidence,                                 # 증빙 링크 목록
        "h_id": row["h_id"],                                    # 재심의를 시작한 본사 직원 아이디 (접수면 None)
        "h_name": row["h_name"],                                # 재심의를 시작한 본사 직원 이름
        "cs_seq": cs_seq,                                       # 대상 제재번호
        "sanction": sanction,                                   # 대상 제재 (없으면 None)
        "sport": sport,                                         # 종목 코드
        "sport_name": SPORT_NAME.get(sport, "기타"),            # 종목명
    }


# 이의신청 전체를 조회해 화면용 dict 목록(최신순)으로 반환. 대상 제재도 함께 연결
def fetch_appeals(cursor, now: datetime, sanctions: list = None) -> list:
    if sanctions is None:
        sanctions = fetch_sanctions(cursor, now)
    sanctions_by_seq = {s["cs_seq"]: s for s in sanctions}
    cursor.execute(SELECT_APPEAL)
    return [build_appeal(row, sanctions_by_seq) for row in cursor.fetchall()]


# 이의신청 1건 조회. 없으면 None
def fetch_appeal(cursor, a_seq: int, now: datetime):
    for appeal in fetch_appeals(cursor, now):
        if appeal["a_seq"] == a_seq:
            return appeal
    return None


# 종목 칩 건수 만들기: 고정 4종목은 항상, 목록에 없는 종목은 있을 때만 '기타' 칩으로 추가
def make_sport_counts(items: list) -> list:
    counts = [
        {"sport": code, "sport_name": name, "count": sum(1 for i in items if i["sport"] == code)}
        for code, name in SPORT_NAME.items()
    ]
    etc_count = sum(1 for i in items if i["sport"] == SPORT_ETC)
    if etc_count:
        counts.append({"sport": SPORT_ETC, "sport_name": "기타", "count": etc_count})
    return counts

# 최종 수정 일 : 2026-10-27
