# 작업자 : 최현준
# 작업 일 : 2026-10-27
"""매니저 근무 충돌 검사·계약 최종 반영·계약 이력 조회. 품의 작성은 groundapproval에서 처리합니다."""
import re
import json
from fastapi import APIRouter, Path
from .groundapproval import (API_RESPONSES, database, fail, now, parse_json,
                             read_document)

router = APIRouter(prefix="/approval/contracts", tags=["구장 계약"], responses=API_RESPONSES)

DAYS = "월화수목금토일"


def minute(value, end=False):
    if not isinstance(value, str) or re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", value) is None:
        if end and value == "24:00":
            return 1440
        fail("ASSIGN_TIME_INVALID", "시간은 HH:mm 형식이어야 합니다. 24:00은 종료 시간만 가능합니다.")
    hour, minutes = map(int, value.split(":"))
    return hour * 60 + minutes


def time_range(value):
    if not isinstance(value, str):
        fail("ASSIGN_TIME_INVALID", "근무 시간을 확인해 주세요.")
    match = re.fullmatch(r"\s*(\d{2}:\d{2})\s*[~～\-]\s*(\d{2}:\d{2})\s*", value)
    if not match:
        fail("ASSIGN_TIME_INVALID", "시간 범위는 09:00~18:00 형식으로 입력해 주세요.")
    start, end = minute(match[1]), minute(match[2], end=True)
    if start == end:
        fail("ASSIGN_TIME_INVALID", "시작과 종료 시간은 달라야 합니다. 종일 운영은 00:00~24:00으로 입력해 주세요.")
    return start, end


def day_list(value):
    if isinstance(value, str):
        value = [part for part in re.split(r"[,/\s]+", value.replace("요일", "")) if part]
    if not isinstance(value, list) or not value or any(not isinstance(day, str) or day not in DAYS or len(day) != 1 for day in value):
        fail("ASSIGN_DAY_INVALID", "요일은 월/화/수/목/금/토/일 중 하나 이상 선택해 주세요.")
    return [day for day in DAYS if day in value]


def weekly_slots(days, start, end):
    slots = []
    for day in day_list(days):
        index = DAYS.index(day)
        if start < end:
            slots.append((index, start, end))
        else:
            slots.extend([(index, start, 1440), ((index + 1) % 7, 0, end)])
    return slots


def overlaps(first, second):
    a = weekly_slots(first["a_day"], *time_range(first["a_time"]))
    b = weekly_slots(second["a_day"], *time_range(second["a_time"]))
    return any(day == other and start < finish and begin < end
               for day, start, end in a for other, begin, finish in b)


def normalize_assignments(items):
    """입력 항목을 검증합니다. 별도의 요청 모델 클래스는 사용하지 않습니다."""
    if not isinstance(items, list) or not 1 <= len(items) <= 50:
        fail("ASSIGN_REQUIRED", "매니저 배정은 1건 이상 50건 이하로 입력해 주세요.")
    rows = []
    for item in items:
        if not isinstance(item, dict) or set(item) != {"m_id", "a_day", "a_period", "a_start", "a_end"}:
            fail("ASSIGN_INVALID", "배정 항목은 m_id, a_day, a_period, a_start, a_end로 구성해 주세요.")
        if not isinstance(item["m_id"], str) or not item["m_id"].strip() or len(item["m_id"]) > 50:
            fail("ASSIGN_MANAGER_INVALID", "매니저 아이디를 확인해 주세요.")
        if not isinstance(item["a_day"], list):
            fail("ASSIGN_DAY_INVALID", "a_day는 요일 배열로 입력해 주세요.")
        days = day_list(item["a_day"])
        start, end = minute(item["a_start"]), minute(item["a_end"], end=True)
        period = item["a_period"]
        if start >= end or period not in ("오전", "오후") or (period == "오전" and end > 720) or (period == "오후" and start < 720):
            fail("ASSIGN_PERIOD_INVALID", "오전은 00:00~12:00, 오후는 12:00~24:00 내에서 시작보다 늦은 종료 시간을 선택해 주세요.")
        row = {"m_id": item["m_id"].strip(), "a_day": ",".join(days), "a_period": period,
               "a_time": f"{item['a_start']}~{item['a_end']}"}
        if any(other["m_id"] == row["m_id"] and overlaps(row, other) for other in rows):
            fail("ASSIGN_SELF_OVERLAP", "품의 내 같은 매니저의 근무 시간이 겹칩니다.", 409)
        rows.append(row)
    return rows


def contract_for_ground(cursor, g_code, required=True):
    """기존 소유주·구장 관계와 품의서 내용으로 계약 이력을 확인합니다. 새 FK를 만들지 않습니다."""
    cursor.execute("SELECT c.*,m.m_content FROM contract c LEFT JOIN memorandum m ON m.m_code=c.m_code ORDER BY c.c_seq DESC")
    contracts = cursor.fetchall()
    cursor.execute("SELECT DISTINCT g_code,o_seq FROM maintain")
    links = cursor.fetchall()
    for contract in contracts:
        document = parse_json(contract.get("m_content"), {})
        if not isinstance(document, dict):
            document = {}
        content = document.get("내용", {}) if isinstance(document, dict) else {}
        linked_ground = content.get("g_code")
        if linked_ground is None:
            # 소유주가 여러 구장을 관리하면 임의로 계약 구장을 선택하지 않습니다.
            grounds = {row["g_code"] for row in links if row["o_seq"] == contract["o_seq"]}
            if grounds == {g_code}:
                linked_ground = g_code
        if linked_ground != g_code:
            continue
        if document.get("유형") == "해지":
            if required:
                fail("CONTRACT_NOT_ACTIVE", "이미 해지된 계약입니다.", 409)
            return None
        return contract
    if required:
        fail("CONTRACT_NOT_FOUND", "기존 관계에서 해당 구장의 계약을 확인할 수 없습니다.", 409)
    return None


def validate_assignments(cursor, rows, operating_time, exclude_document=None):
    if not rows:
        fail("ASSIGN_REQUIRED", "매니저 배정이 필요합니다.")
    operating_start, operating_end = time_range(operating_time)
    windows = [(operating_start, operating_end)] if operating_start < operating_end else [(operating_start, 1440), (0, operating_end)]
    cursor.execute("SELECT a.m_code,m.m_content FROM approval a JOIN memorandum m ON m.m_code=a.m_code WHERE a.a_state='심사중' AND a.a_seq=(SELECT MAX(x.a_seq) FROM approval x WHERE x.m_code=a.m_code)")
    pending = []
    for row in cursor.fetchall():
        if row["m_code"] != exclude_document:
            document = parse_json(row["m_content"], {})
            if isinstance(document, dict):
                pending.extend(document.get("내용", {}).get("assignments", []))
    for row in rows:
        start, end = time_range(row["a_time"])
        if not any(a <= start < end <= b for a, b in windows):
            fail("ASSIGN_OUTSIDE_OPERATION", "배정 시간이 구장 운영 시간을 벗어났습니다.")
        cursor.execute("SELECT m_id,m_name FROM match_manager WHERE m_id=%s AND TRIM(m_department)='매니저' AND (m_resignationdate IS NULL OR m_resignationdate>CURRENT_DATE)", (row["m_id"],))
        manager = cursor.fetchone()
        if manager is None:
            fail("ASSIGN_MANAGER_INVALID", "재직 중인 매니저를 선택해 주세요.", 404)
        cursor.execute("SELECT g_code,a_day,a_time FROM assign WHERE m_id=%s", (row["m_id"],))
        existing = cursor.fetchall()
        for other in existing:
            # 해지된 계약의 관계 행은 삭제하지 않고 근무 충돌 검사에서만 제외합니다.
            cursor.execute("SELECT c.m_code,m.m_content FROM contract c JOIN memorandum m ON m.m_code=c.m_code ORDER BY c.c_seq DESC")
            ended = False
            for contract in cursor.fetchall():
                document = parse_json(contract["m_content"], {})
                if isinstance(document, dict) and document.get("내용", {}).get("g_code") == other["g_code"]:
                    ended = document.get("유형") == "해지"
                    break
            if not ended and overlaps(row, other):
                fail("ASSIGN_CONFLICT", "매니저의 기존 근무와 시간이 겹칩니다.", 409)
        if any(other["m_id"] == row["m_id"] and overlaps(row, other) for other in pending):
            fail("ASSIGN_CONFLICT", "매니저의 심사 중 근무와 시간이 겹칩니다.", 409)


def finalize_ground(cursor, m_code, document, history, actor_id):
    content = document["내용"]
    author = document["작성자"]
    kind = document["유형"]
    signers = [row["h_id"] for row in history if row["a_step"] > 0] + [actor_id]
    record = json.dumps(signers, ensure_ascii=False, separators=(",", ":"))
    if len(record) > 255:
        fail("SIGNATURE_TOO_LONG", "계약 서명 기록이 기존 컬럼 길이를 초과합니다.")
    if kind == "신규 계약":
        from .groundshoot import UPLOAD_ROOT
        ground = content["new_ground"]
        cursor.execute("SELECT g_code FROM ground WHERE g_name=%s AND g_address=%s FOR UPDATE", (ground["g_name"], ground["g_address"]))
        if cursor.fetchone():
            fail("GROUND_EXISTS", "같은 구장이 이미 등록되어 있습니다.", 409)
        validate_assignments(cursor, content["assignments"], ground["g_time"], exclude_document=m_code)
        for filename in content["s_image"]:
            path = (UPLOAD_ROOT / filename).resolve()
            if path.parent != UPLOAD_ROOT or not path.is_file():
                fail("PHOTO_NOT_FOUND", "품의에 첨부한 사진 파일이 없습니다.", 409)
        if "new_owner" in content:
            owner = content["new_owner"]
            cursor.execute("INSERT INTO owner (o_name,o_phone) VALUES (%s,%s)", (owner["o_name"], owner["o_phone"]))
            owner_id = cursor.lastrowid
        else:
            owner_id = content["o_seq"]
            cursor.execute("SELECT o_seq FROM owner WHERE o_seq=%s", (owner_id,))
            if cursor.fetchone() is None:
                fail("OWNER_NOT_FOUND", "선택한 소유주가 없습니다.", 404)
        cursor.execute("INSERT INTO ground (g_name,e_code,g_address,g_lat,g_lng,g_num,g_information,g_time,g_price) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                       (ground["g_name"], ground["e_code"], ground["g_address"], ground["g_lat"], ground["g_lng"], ground["g_num"], ground["g_information"], ground["g_time"], ground["g_price"]))
        ground_id = cursor.lastrowid
        # 기존 소유주·구장 관계 테이블에 연결을 남깁니다. contract에 임의 g_code를 추가하지 않습니다.
        cursor.execute("INSERT INTO maintain (g_code,o_seq,m_date,m_content,m_name,m_department) VALUES (%s,%s,%s,%s,%s,%s)",
                       (ground_id, owner_id, now().date(), f"품의서 {m_code} 계약", author["h_name"], "영업팀"))
        for filename in content["s_image"]:
            cursor.execute("INSERT INTO shoot (h_id,g_code,s_date,s_image) VALUES (%s,%s,%s,%s)", (author["h_id"], ground_id, now().date(), filename))
        for assignment in content["assignments"]:
            cursor.execute("INSERT INTO assign (h_id,m_id,g_code,a_day,a_time) VALUES (%s,%s,%s,%s,%s)",
                           (author["h_id"], assignment["m_id"], ground_id, assignment["a_day"], assignment["a_time"]))
        content["g_code"], content["o_seq"] = ground_id, owner_id
    else:
        current = contract_for_ground(cursor, content["g_code"])
        if current["c_seq"] != content["c_seq"]:
            fail("CONTRACT_CHANGED", "상신 후 계약이 변경되어 재상신이 필요합니다.", 409)
        owner_id = current["o_seq"]
    treaty = content["c_treaty"]
    if kind == "해지":
        treaty = "계약 해지\n" + (history[0]["a_reason"] or "") + "\n" + (treaty or "")
    # 계약·연장·해지도 기존 관계에 행을 추가합니다. 상태/만료일 같은 새 속성은 사용하지 않습니다.
    cursor.execute("INSERT INTO contract (h_id,o_seq,m_code,c_date,c_record,c_treaty,c_rentalfee) VALUES (%s,%s,%s,%s,%s,%s,%s)",
                   (author["h_id"], owner_id, m_code, now().date(), record, treaty, history[-1]["a_price"]))


@router.get("", summary="기존 계약 관계 이력 조회")
def contracts():
    with database() as cursor:
        cursor.execute("SELECT c.*,o.o_name,h.h_name FROM contract c JOIN owner o ON o.o_seq=c.o_seq JOIN headquarter h ON h.h_id=c.h_id ORDER BY c.c_seq DESC")
        return {"results": cursor.fetchall()}


@router.get("/{c_seq}", summary="기존 계약 관계 상세 조회")
def contract(c_seq: int = Path(..., ge=1, description="계약 관계 번호")):
    with database() as cursor:
        cursor.execute("SELECT c.*,o.o_name,h.h_name FROM contract c JOIN owner o ON o.o_seq=c.o_seq JOIN headquarter h ON h.h_id=c.h_id WHERE c.c_seq=%s", (c_seq,))
        row = cursor.fetchone()
        if row is None:
            fail("CONTRACT_NOT_FOUND", "계약이 없습니다.", 404)
        return row

# 최종 수정일 : 2026-10-27
