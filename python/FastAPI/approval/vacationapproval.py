# 작업자 : 최현준
# 작업 일 : 2026-10-27
"""휴가 품의의 입력 검증·최종 승인 처리. 상신·결재 진입점은 groundapproval의 단일 품의 API를 사용합니다."""
from datetime import date
from .groundapproval import date_value, string_value, fail, now, parse_json


def validate_vacation(cursor, employee_id, deputy_id, start, end, exclude=None):
    """승인 휴가와 심사중 신청을 함께 검사해 대리 업무 충돌을 상신 때 차단합니다."""
    if end < start or start < now().date():
        fail("VACATION_DATE_INVALID", "휴가는 오늘 이후 시작하며 종료일은 시작일 이후여야 합니다.")
    if employee_id == deputy_id:
        fail("VACATION_SELF_DEPUTY", "본인을 대리인으로 지정할 수 없습니다.")
    cursor.execute("SELECT h_id,h_department,h_resignationdate FROM headquarter WHERE h_id IN (%s,%s)", (employee_id, deputy_id))
    people = {row["h_id"]: row for row in cursor.fetchall()}
    employee, deputy = people.get(employee_id), people.get(deputy_id)
    if any(person is None or (person["h_resignationdate"] and person["h_resignationdate"] <= now().date()) for person in (employee, deputy)):
        fail("STAFF_NOT_FOUND", "재직 중인 신청자와 대리인을 선택해 주세요.", 404)
    if (employee["h_department"] or "").strip() != (deputy["h_department"] or "").strip():
        fail("DEPUTY_DEPARTMENT_INVALID", "같은 부서의 직원을 대리인으로 선택해 주세요.")
    cursor.execute("SELECT h_id,h_deputy,h_start,h_end FROM h_vacation WHERE h_start<=%s AND h_end>=%s", (end, start))
    periods = list(cursor.fetchall())
    cursor.execute("SELECT a.m_code,m.m_content FROM approval a JOIN memorandum m ON m.m_code=a.m_code WHERE a.a_state='심사중' AND a.a_seq=(SELECT MAX(x.a_seq) FROM approval x WHERE x.m_code=a.m_code)")
    for row in cursor.fetchall():
        if row["m_code"] == exclude:
            continue
        document = parse_json(row["m_content"], {})
        if not isinstance(document, dict) or document.get("유형") != "휴가":
            continue
        content = document["내용"]
        a, b = date.fromisoformat(content["h_start"]), date.fromisoformat(content["h_end"])
        if a <= end and b >= start:
            periods.append({"h_id": document["작성자"]["h_id"], "h_deputy": content["h_deputy"]})
    for period in periods:
        if period["h_id"] == employee_id:
            fail("VACATION_OVERLAP", "같은 기간의 휴가 신청 또는 승인 내역이 있습니다.", 409)
        if period["h_deputy"] == employee_id:
            fail("VACATION_DEPUTY_BUSY", "해당 기간 다른 직원의 대리인으로 지정되어 휴가를 신청할 수 없습니다.", 409)
        if period["h_id"] == deputy_id:
            fail("VACATION_DEPUTY_ABSENT", "대리인이 해당 기간 휴가 중이거나 휴가 심사 중입니다.", 409)

def prepare_vacation(cursor, employee, data):
    if set(data) - {"h_start","h_end","h_deputy"}:
        fail("APPROVAL_FIELDS_INVALID","휴가 양식에 맞지 않는 입력 항목이 있습니다.")
    start,end = date_value(data,"h_start"),date_value(data,"h_end")
    deputy = string_value(data,"h_deputy",50)
    validate_vacation(cursor,employee["h_id"],deputy,start,end)
    return {"h_start":start.isoformat(),"h_end":end.isoformat(),"h_deputy":deputy},None


def finalize_vacation(cursor, m_code, document, history, actor_id):
    content = document["내용"]
    employee_id = document["작성자"]["h_id"]
    start, end = date.fromisoformat(content["h_start"]), date.fromisoformat(content["h_end"])
    validate_vacation(cursor, employee_id, content["h_deputy"], start, end, exclude=m_code)
    cursor.execute("INSERT INTO h_vacation (h_id,h_deputy,h_start,h_end) VALUES (%s,%s,%s,%s)",
                   (employee_id, content["h_deputy"], start, end))

# 최종 수정일 : 2026-10-27
