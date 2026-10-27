# 작업자 : 최현준
# 작업 일 : 2026-10-27
"""품의 양식 조회·상신·조회·3단계 결재. 기존 memorandum·approval 컬럼만 사용합니다."""
import json
import logging
import math
from contextlib import contextmanager
from datetime import date, datetime
from zoneinfo import ZoneInfo

import pymysql
from fastapi import APIRouter, Body, HTTPException, Path, Query
from FastAPI.login.admin_login import connect

logger = logging.getLogger(__name__)
API_RESPONSES = {
    400: {"description": "입력 내용 또는 업무 규칙 오류"},
    404: {"description": "데이터 없음"},
    409: {"description": "일정 중복 또는 이미 처리된 품의"},
    422: {"description": "필수 입력값 또는 형식 오류"},
    503: {"description": "DB 연결 또는 품의 테이블 설정 확인 필요"},
}
KINDS = ("휴가", "신규 계약", "재계약", "해지")
POSITIONS = ("사원", "팀장", "임원")
router = APIRouter(prefix="/approval", tags=["품의"], responses=API_RESPONSES)


def fail(code, message, status=400):
    raise HTTPException(status, detail={"code": code, "message": message})


def now():
    return datetime.now(ZoneInfo("Asia/Seoul")).replace(tzinfo=None, microsecond=0)


@contextmanager
def database(write=False):
    """연결·커밋·롤백만 관리합니다. 업무 SQL은 해당 기능 함수에 직접 작성합니다."""
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            yield cursor
        if write:
            connection.commit()
    except pymysql.MySQLError as error:
        if connection is not None:
            connection.rollback()
        logger.error("품의 DB 처리 실패 (%s)", type(error).__name__)
        fail("APPROVAL_DB_ERROR", "DB 연결과 기존 테이블 구조를 확인해 주세요.", 503)
    except Exception:
        if connection is not None:
            connection.rollback()
        raise
    finally:
        if connection is not None:
            connection.close()


def text(value, label):
    value = value.strip()
    if not value:
        fail("EMPTY_VALUE", f"{label}을 입력해 주세요.")
    return value


def string_value(data, key, maximum, optional=False):
    value = data.get(key)
    if optional and value is None:
        return None
    if not isinstance(value,str) or len(value)>maximum or (not optional and not value.strip()):
        fail("APPROVAL_INPUT_INVALID",f"{key}의 입력 내용과 길이를 확인해 주세요.")
    return value.strip() or None


def integer_value(data, key, minimum):
    value = data.get(key)
    if type(value) is not int or not minimum <= value <= 2147483647:
        fail("APPROVAL_INPUT_INVALID",f"{key}에 {minimum} 이상의 정수를 입력해 주세요.")
    return value


def number_value(data, key, minimum, maximum):
    value = data.get(key)
    if type(value) not in (int,float) or not math.isfinite(value) or not minimum <= value <= maximum:
        fail("APPROVAL_INPUT_INVALID",f"{key}의 숫자 범위를 확인해 주세요.")
    return value


def date_value(data, key, optional=False):
    value=data.get(key)
    if optional and value is None:
        return None
    try:
        return date.fromisoformat(value)
    except (TypeError,ValueError):
        fail("APPROVAL_DATE_INVALID",f"{key}는 연-월-일 형식으로 입력해 주세요.")


def parse_json(value, default):
    if value is None:
        return default
    if not isinstance(value, str):
        return value
    try:
        return json.loads(value)
    except (ValueError, TypeError):
        return default


def document_kind(content):
    """유형은 새 컬럼이 아니라 기존 작성 내용에서 읽습니다."""
    document = parse_json(content, {})
    if isinstance(document, dict) and document.get("유형") in KINDS:
        return document["유형"]
    # 기존 문자열 양식도 읽습니다. 여러 유형이 섞인 양식은 임의 판단하지 않습니다.
    title = str(content or "").split("\\n", 1)[0].splitlines()[0] if content else ""
    found = []
    if "휴가" in title:
        found.append("휴가")
    if "해지" in title or "취소" in title:
        found.append("해지")
    elif "재계약" in title or "갱신" in title or "연장" in title:
        found.append("재계약")
    elif "계약" in title:
        found.append("신규 계약")
    if len(found) == 1:
        return found[0]
    fail("MEMORANDUM_CONTENT_INVALID", "작성 내용에서 휴가·신규 계약·재계약·해지 양식을 구분할 수 없습니다.", 409)


def read_document(content):
    document = parse_json(content, {})
    if (not isinstance(document, dict) or document.get("유형") not in KINDS
            or not isinstance(document.get("내용"), dict) or not isinstance(document.get("결재선"), list)
            or len(document["결재선"]) != 3
            or any(not isinstance(row, dict) or not isinstance(row.get("h_id"), str) for row in document["결재선"])
            or not isinstance(document.get("작성자"), dict)
            or not all(isinstance(document["작성자"].get(key), str) for key in ("h_id", "h_name"))):
        fail("MEMORANDUM_CONTENT_INVALID", "기존 품의서 작성 내용의 형식을 확인해 주세요.", 409)
    return document


@router.get("/templates", summary="기존 품의 양식 조회", description="결재 기록이 없는 memorandum의 기존 작성 내용을 조회합니다.")
def templates():
    with database() as cursor:
        cursor.execute("SELECT m.m_code,m.m_content FROM memorandum m WHERE NOT EXISTS (SELECT 1 FROM approval a WHERE a.m_code=m.m_code) ORDER BY m.m_code")
        return {"results": cursor.fetchall()}


@router.get("/approvers", summary="품의 양식별 결재자 후보 조회")
def approvers(m_code: int = Query(..., ge=1, description="기존 품의 양식 번호")):
    with database() as cursor:
        cursor.execute("SELECT m_content FROM memorandum WHERE m_code=%s", (m_code,))
        memo = cursor.fetchone()
        if memo is None:
            fail("MEMORANDUM_NOT_FOUND", "품의서를 찾을 수 없습니다.", 404)
        department = "인사팀" if document_kind(memo["m_content"]) == "휴가" else "영업팀"
        cursor.execute("SELECT h_id,h_name,h_position,h_department FROM headquarter WHERE TRIM(h_department)=%s AND TRIM(h_position) IN ('사원','팀장','임원') AND (h_resignationdate IS NULL OR h_resignationdate>CURRENT_DATE) ORDER BY h_name", (department,))
        return {"results": cursor.fetchall()}


CONTRACT_DATA = {
    "owner_mode":"신규","o_name":"홍길동","o_phone":"010-1234-5678",
    "g_name":"신규 풋살장","e_code":"축구","g_address":"서울시 구장 주소","g_lat":37.5665,"g_lng":126.978,
    "g_num":20,"g_price":15000,"g_information":"구장 안내","g_time":"09:00~22:00",
    "c_treaty":"구두 협의 조건","c_rentalfee":100000,"s_image":["업로드한_사진.jpg"],
    "assignments":[{"m_id":"매니저_ID","a_day":["월","수","금"],"a_period":"오전","a_start":"09:00","a_end":"12:00"}],
}
COMMON_EXAMPLE = {"h_id":"작성자_ID","a_reason":"품의 사유","approver_ids":["담당부서_사원_ID","담당부서_팀장_ID","담당부서_임원_ID"]}
# 요청 모델 클래스 없이도 Swagger의 Schema에서 구장 입력 항목을 확인하도록 명시합니다.
# 양식별 필수값과 실제 유효성 검사는 아래 처리 함수가 수행합니다.
CONTRACT_INPUT_SCHEMA = {
    "title": "신규 계약 · 구장 정보 전체 입력",
    "type": "object",
    "additionalProperties": False,
    "required": ["g_name", "e_code", "g_address", "g_lat", "g_lng", "g_num",
                 "g_information", "g_time", "g_price", "c_treaty", "c_rentalfee", "s_image", "assignments"],
    "properties": {
        "owner_mode": {"type": "string", "enum": ["신규", "기존"], "default": "신규", "description": "소유주 직접 입력 또는 기존 소유주 선택"},
        "o_seq": {"type": "integer", "minimum": 1, "description": "기존 소유주 선택 시에만 전달"},
        "o_name": {"type": "string", "maxLength": 100, "description": "신규 소유주 이름"},
        "o_phone": {"type": "string", "maxLength": 20, "description": "신규 소유주 연락처 (선택)"},
        "g_name": {"type": "string", "maxLength": 100, "description": "구장명"},
        "e_code": {"type": "string", "maxLength": 50, "examples": ["축구"], "description": "종목코드 문자열 입력: 축구/농구/배구/야구 중 한 가지 (프런트는 단일 선택)"},
        "g_address": {"type": "string", "maxLength": 255, "description": "구장 전체 주소"},
        "g_lat": {"type": "number", "minimum": -90, "maximum": 90, "description": "위도"},
        "g_lng": {"type": "number", "minimum": -180, "maximum": 180, "description": "경도"},
        "g_num": {"type": "integer", "minimum": 1, "description": "수용 인원"},
        "g_information": {"type": "string", "maxLength": 10000, "description": "구장 이용 정보"},
        "g_time": {"type": "string", "description": "운영 시간 (예: 09:00~22:00)"},
        "g_price": {"type": "integer", "minimum": 0, "description": "구장 이용 금액 (원)"},
        "c_treaty": {"type": "string", "maxLength": 10000, "description": "구두 합의한 계약 조건"},
        "c_rentalfee": {"type": "integer", "minimum": 0, "description": "계약 대관료 (원)"},
        "s_image": {"type": "array", "minItems": 1, "maxItems": 20, "items": {"type": "string"}, "description": "먼저 업로드한 사진 파일명"},
        "assignments": {"type": "array", "minItems": 1, "maxItems": 50, "description": "매니저별 근무 요일과 오전·오후 시간", "items": {
            "type": "object", "additionalProperties": False,
            "required": ["m_id", "a_day", "a_period", "a_start", "a_end"],
            "properties": {
                "m_id": {"type": "string", "description": "배정 매니저 아이디"},
                "a_day": {"type": "array", "minItems": 1, "items": {"type": "string", "enum": list("월화수목금토일")}, "description": "근무 요일"},
                "a_period": {"type": "string", "enum": ["오전", "오후"], "description": "근무 구분"},
                "a_start": {"type": "string", "description": "시작 시간 HH:mm"},
                "a_end": {"type": "string", "description": "종료 시간 HH:mm"},
            },
        }},
    },
}
REQUEST_DATA_SCHEMA = {"oneOf": [
    CONTRACT_INPUT_SCHEMA,
    {"title": "휴가", "type": "object", "additionalProperties": False,
     "required": ["h_start", "h_end", "h_deputy"], "properties": {
         "h_start": {"type": "string", "format": "date", "description": "휴가 시작일"},
         "h_end": {"type": "string", "format": "date", "description": "휴가 종료일"},
         "h_deputy": {"type": "string", "description": "대리 직원 아이디"}}},
    {"title": "재계약 · 기존 구장 선택", "type": "object", "additionalProperties": False,
     "required": ["g_code", "c_treaty", "c_rentalfee"], "properties": {
         "g_code": {"type": "integer", "minimum": 1, "description": "선택한 기존 구장 번호"},
         **{key: CONTRACT_INPUT_SCHEMA["properties"][key] for key in ("c_treaty", "c_rentalfee")}}},
    {"title": "계약 해지", "type": "object", "additionalProperties": False,
     "required": ["c_seq"], "properties": {"c_seq": {"type": "integer", "minimum": 1, "description": "해지할 계약 번호"}}},
]}
REQUEST_EXAMPLES = {
    "vacation":{"summary":"휴가 양식","value":{**COMMON_EXAMPLE,"m_code":3,"data":{"h_start":"2027-01-04","h_end":"2027-01-05","h_deputy":"대리인_ID"}}},
    "new_owner":{"summary":"신규 계약 · 소유주 직접 입력","value":{**COMMON_EXAMPLE,"m_code":1,"data":CONTRACT_DATA}},
    "existing_owner":{"summary":"신규 계약 · 기존 소유주 선택","value":{**COMMON_EXAMPLE,"m_code":1,"data":{**{k:v for k,v in CONTRACT_DATA.items() if k not in ("o_name","o_phone")},"owner_mode":"기존","o_seq":1}}},
    "renewal":{"summary":"재계약 · 기존 구장 선택 및 기간 연장","value":{**COMMON_EXAMPLE,"m_code":4,"data":{"g_code":1,"c_treaty":"연장 합의 조건","c_rentalfee":120000}}},
    "termination":{"summary":"계약 해지 양식","value":{**COMMON_EXAMPLE,"m_code":2,"data":{"c_seq":1}}},
}


@router.post("/requests", status_code=201, summary="품의 작성·상신",
             description="선택한 기존 양식의 작성 내용으로 품의서를 작성합니다. 본문은 m_content에 저장하고 approval에는 기존 관계 컬럼만 기록합니다.",
             openapi_extra={"requestBody": {"content": {"application/json": {"examples": REQUEST_EXAMPLES}}}})
def submit_request(
    h_id: str = Body(..., min_length=1, max_length=50, description="작성 직원 아이디"),
    m_code: int = Body(..., gt=0, description="선택한 기존 양식 번호"),
    a_reason: str = Body(..., min_length=1, max_length=10000, description="품의 사유"),
    approver_ids: list[str] = Body(..., min_length=3, max_length=3, description="사원·팀장·임원 결재자 아이디"),
    data: dict = Body(..., description="양식별 작성 내용. DB 컬럼을 추가하지 않고 기존 m_content에 보관합니다.", json_schema_extra=REQUEST_DATA_SCHEMA),
):
    from .vacationapproval import prepare_vacation
    with database(write=True) as cursor:
        cursor.execute("SELECT m_code FROM memorandum ORDER BY m_code FOR UPDATE")
        cursor.fetchall()
        cursor.execute("SELECT m_content FROM memorandum WHERE m_code=%s", (m_code,))
        template = cursor.fetchone()
        if template is None:
            fail("MEMORANDUM_NOT_FOUND", "선택한 양식이 없습니다.", 404)
        kind = document_kind(template["m_content"])
        cursor.execute("SELECT h_id,h_name,h_department,h_resignationdate FROM headquarter WHERE h_id=%s", (h_id.strip(),))
        employee = cursor.fetchone()
        if employee is None or (employee["h_resignationdate"] and employee["h_resignationdate"] <= now().date()):
            fail("STAFF_NOT_FOUND", "재직 중인 작성 직원을 선택해 주세요.", 404)
        department = "인사팀" if kind == "휴가" else "영업팀"
        if kind != "휴가" and (employee["h_department"] or "").strip() != department:
            fail("DEPARTMENT_FORBIDDEN", "구장 계약 관련 품의는 영업팀에서 작성합니다.", 403)
        if len(set(approver_ids)) != 3:
            fail("APPROVAL_LINE_INVALID", "세 단계의 결재자는 서로 달라야 합니다.")
        line = []
        for employee_id, position in zip(approver_ids, POSITIONS):
            cursor.execute("SELECT h_id,h_name,h_department,h_position,h_resignationdate FROM headquarter WHERE h_id=%s", (employee_id,))
            person = cursor.fetchone()
            if (person is None or (person["h_department"] or "").strip() != department
                    or (person["h_position"] or "").strip() != position
                    or (person["h_resignationdate"] and person["h_resignationdate"] <= now().date())):
                fail("APPROVAL_LINE_INVALID", f"{department}의 재직 중인 {position} 결재자를 선택해 주세요.")
            line.append({"h_id": person["h_id"], "h_name": person["h_name"], "h_position": position})
        prepare = {"휴가": prepare_vacation, "신규 계약": prepare_contract,
                   "재계약": prepare_renewal, "해지": prepare_termination}[kind]
        content, price = prepare(cursor, employee, data)
        # 아래 키는 작성 내용의 문서 형식입니다. DB 속성이나 별도 테이블이 아닙니다.
        document = {"유형": kind, "양식": template["m_content"],
                    "작성자": {"h_id": employee["h_id"], "h_name": employee["h_name"]},
                    "결재선": line, "내용": content}
        content_text = json.dumps(document, ensure_ascii=False, default=str)
        if len(content_text.encode("utf-8")) > 65000:
            fail("MEMORANDUM_CONTENT_TOO_LONG", "기존 작성 내용(TEXT) 길이를 초과했습니다. 내용을 줄여 주세요.")
        cursor.execute("INSERT INTO memorandum (m_content) VALUES (%s)", (content_text,))
        document_code = cursor.lastrowid
        # 상신은 0단계. 실제 사원·팀장·임원 확인마다 같은 m_code의 관계 행을 추가합니다.
        cursor.execute("INSERT INTO approval (h_id,m_code,a_reason,a_state,a_step,a_date,a_signatures,a_price) VALUES (%s,%s,%s,'심사중',0,%s,NULL,%s)",
                       (employee["h_id"], document_code, text(a_reason, "품의 사유"), now(), price))
        return {"m_code": document_code, "a_state": "심사중", "a_step": 0}


@router.post("/requests/{m_code}/sign", summary="품의 승인·반려 기록 추가",
             description="같은 품의서 m_code에 결재 관계 행을 추가합니다. 기존 상태·순서·서명 기록만 사용합니다.")
def sign_request(
    m_code: int = Path(..., ge=1, description="상신된 품의서 번호"),
    h_id: str = Body(..., min_length=1, max_length=50, description="실제 결재 직원 아이디"),
    approve: bool = Body(..., strict=True, description="승인 여부"),
    comment: str = Body("", max_length=100, description="반려 사유는 필수. 서명 기록은 기존 VARCHAR(255) 길이를 준수합니다."),
):
    from .vacationapproval import finalize_vacation
    from .groundcontract import finalize_ground
    with database(write=True) as cursor:
        cursor.execute("SELECT m_code FROM memorandum ORDER BY m_code FOR UPDATE")
        cursor.fetchall()
        cursor.execute("SELECT m_content FROM memorandum WHERE m_code=%s FOR UPDATE", (m_code,))
        memo = cursor.fetchone()
        if memo is None:
            fail("MEMORANDUM_NOT_FOUND", "품의서가 없습니다.", 404)
        document = read_document(memo["m_content"])
        cursor.execute("SELECT * FROM approval WHERE m_code=%s ORDER BY a_seq FOR UPDATE", (m_code,))
        history = cursor.fetchall()
        if not history:
            fail("APPROVAL_NOT_FOUND", "상신 기록이 없습니다.", 404)
        latest = history[-1]
        if latest["a_state"] != "심사중" or latest["a_step"] not in (0, 1, 2):
            fail("APPROVAL_FINISHED", "이미 처리되었거나 결재 순서를 확인할 수 없는 품의입니다.", 409)
        step = latest["a_step"] + 1
        entry = document["결재선"][step - 1]
        department = "인사팀" if document["유형"] == "휴가" else "영업팀"
        cursor.execute("SELECT h_id,h_department,h_position,h_resignationdate FROM headquarter WHERE h_id=%s", (entry["h_id"],))
        original = cursor.fetchone()
        if (original is None or (original["h_department"] or "").strip() != department
                or (original["h_position"] or "").strip() != POSITIONS[step - 1]
                or (original["h_resignationdate"] and original["h_resignationdate"] <= now().date())):
            fail("APPROVAL_LINE_CHANGED", "원결재자의 부서·직급·재직 상태를 확인해 주세요.", 409)
        today = now().date()
        cursor.execute("SELECT h_deputy FROM h_vacation WHERE h_id=%s AND h_start<=%s AND h_end>=%s", (entry["h_id"], today, today))
        leaves = cursor.fetchall()
        expected = entry["h_id"]
        if leaves:
            if len(leaves) != 1 or not leaves[0]["h_deputy"] or leaves[0]["h_deputy"] == expected:
                fail("DEPUTY_UNAVAILABLE", "담당자의 휴가 대리인을 확인해 주세요.", 409)
            expected = leaves[0]["h_deputy"]
        if h_id.strip() != expected:
            fail("NOT_YOUR_TURN", "현재 단계의 결재 담당자가 아닙니다.", 403)
        cursor.execute("SELECT h_id,h_department,h_resignationdate FROM headquarter WHERE h_id=%s", (expected,))
        actor = cursor.fetchone()
        if actor is None or (actor["h_department"] or "").strip() != department or (actor["h_resignationdate"] and actor["h_resignationdate"] <= today):
            fail("DEPARTMENT_FORBIDDEN", "담당 부서의 재직 중인 결재자가 아닙니다.", 403)
        cursor.execute("SELECT v_seq FROM h_vacation WHERE h_id=%s AND h_start<=%s AND h_end>=%s", (expected, today, today))
        if cursor.fetchone():
            fail("DEPUTY_ABSENT", "실제 결재자도 휴가 중입니다.", 409)
        if any(row["a_step"] > 0 and row["h_id"] == expected for row in history):
            fail("DUPLICATE_SIGNER", "한 직원은 한 품의의 한 단계만 결재합니다.", 409)
        if not approve:
            text(comment, "반려 사유")
        signature = json.dumps({"h_id": expected, "original_h_id": entry["h_id"], "comment": comment.strip()}, ensure_ascii=False, separators=(",", ":"))
        if len(signature) > 255:
            fail("SIGNATURE_TOO_LONG", "기존 서명 기록 길이(255자)를 초과했습니다. 의견을 줄여 주세요.")
        state = "반려" if not approve else "승인완료" if step == 3 else "심사중"
        if state == "승인완료":
            finalize = finalize_vacation if document["유형"] == "휴가" else finalize_ground
            finalize(cursor, m_code, document, history, expected)
            cursor.execute("UPDATE memorandum SET m_content=%s WHERE m_code=%s",
                           (json.dumps(document, ensure_ascii=False, default=str), m_code))
        cursor.execute("INSERT INTO approval (h_id,m_code,a_reason,a_state,a_step,a_date,a_signatures,a_price) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
                       (expected, m_code, history[0]["a_reason"], state, step, now(), signature, latest["a_price"]))
        return {"m_code": m_code, "a_state": state, "a_step": step}


@router.get("/requests", summary="품의 결재 기록 조회", description="인증 없이 기존 관계 행을 조회합니다. 같은 m_code의 결재가 순서대로 누적됩니다.")
def requests(m_code: int | None = Query(None, ge=1, description="품의서 번호"),
             limit: int = Query(50, ge=1, le=100), offset: int = Query(0, ge=0)):
    with database() as cursor:
        sql = "SELECT a.*,m.m_content,h.h_name FROM approval a JOIN memorandum m ON m.m_code=a.m_code JOIN headquarter h ON h.h_id=a.h_id"
        params = []
        if m_code is not None:
            sql += " WHERE a.m_code=%s"
            params.append(m_code)
        cursor.execute(sql + " ORDER BY a.a_seq DESC LIMIT %s OFFSET %s", [*params, limit, offset])
        return {"results": cursor.fetchall()}


@router.get("/requests/{m_code}", summary="품의서 및 전체 결재 기록 조회")
def request_detail(m_code: int = Path(..., ge=1, description="품의서 번호")):
    with database() as cursor:
        cursor.execute("SELECT m_code,m_content FROM memorandum WHERE m_code=%s", (m_code,))
        memo = cursor.fetchone()
        if memo is None:
            fail("MEMORANDUM_NOT_FOUND", "품의서가 없습니다.", 404)
        cursor.execute("SELECT a.*,h.h_name FROM approval a JOIN headquarter h ON h.h_id=a.h_id WHERE a.m_code=%s ORDER BY a.a_seq", (m_code,))
        return {**memo, "approval": cursor.fetchall()}


def prepare_contract(cursor, employee, data):
    """신규 구장·소유주·사진·배정을 검증하고 승인 전에는 품의에만 보관합니다."""
    from .groundcontract import normalize_assignments, validate_assignments
    allowed = {"owner_mode","o_seq","o_name","o_phone","g_name","e_code","g_address","g_lat","g_lng",
               "g_num","g_price","g_information","g_time","c_treaty","c_rentalfee","s_image","assignments"}
    reject_extra(data, allowed)
    mode = data.get("owner_mode", "신규")
    if mode == "기존":
        if data.get("o_name") is not None or data.get("o_phone") is not None:
            fail("OWNER_INPUT_INVALID", "기존 소유주는 번호만 선택하고 신규 입력은 생략해 주세요.")
        owner_data = {"o_seq": integer_value(data, "o_seq", 1)}
    elif mode == "신규":
        if data.get("o_seq") is not None:
            fail("OWNER_INPUT_INVALID", "신규 소유주는 번호를 입력하지 않습니다.")
        owner_data = {"new_owner": {"o_name": string_value(data,"o_name",100),
                                    "o_phone": string_value(data,"o_phone",20,optional=True)}}
    else:
        fail("OWNER_INPUT_INVALID", "소유주는 신규 또는 기존 중 선택해 주세요.")
    ground = {key: string_value(data,key,maximum) for key, maximum in (
        ("g_name",100),("g_address",255),("g_information",10000),("g_time",100))}
    # 종목도 구장 정보와 함께 품의에 보관하고 최종 승인 때 그대로 저장합니다.
    e_code = string_value(data, "e_code", 50)
    if e_code not in ("축구", "농구", "배구", "야구"):
        fail("GROUND_CATEGORY_INVALID", "종목은 축구·배구·농구·야구 중 하나만 선택해 주세요.")
    ground["e_code"] = e_code
    ground.update(g_lat=number_value(data,"g_lat",-90,90),g_lng=number_value(data,"g_lng",-180,180),
                  g_num=integer_value(data,"g_num",1),g_price=integer_value(data,"g_price",0))
    images = data.get("s_image")
    if not isinstance(images, list) or not 1 <= len(images) <= 20 or any(not isinstance(item, str) for item in images):
        fail("PHOTO_INVALID", "업로드한 사진 파일명을 1~20개 전달해 주세요.")
    from .groundshoot import UPLOAD_ROOT, file_prefix
    for image in images:
        path = (UPLOAD_ROOT / image).resolve()
        if path.parent != UPLOAD_ROOT or not image.startswith(file_prefix(employee["h_id"])) or not path.is_file():
            fail("PHOTO_INVALID", "본인이 업로드한 사진 파일을 첨부해 주세요.")
    content = {"new_ground": ground, **owner_data, "c_treaty": string_value(data, "c_treaty", 10000),
               "s_image": list(dict.fromkeys(images)), "assignments": normalize_assignments(data.get("assignments"))}
    cursor.execute("SELECT g_code FROM ground WHERE g_name=%s AND g_address=%s FOR UPDATE", (ground["g_name"], ground["g_address"]))
    if cursor.fetchone() is not None:
        fail("GROUND_EXISTS", "같은 이름과 주소의 구장이 이미 등록되어 있습니다.", 409)
    if "o_seq" in content:
        cursor.execute("SELECT o_seq,o_name,o_phone FROM owner WHERE o_seq=%s", (content["o_seq"],))
        owner = cursor.fetchone()
        if owner is None:
            fail("OWNER_NOT_FOUND", "소유주를 찾을 수 없습니다.", 404)
        content["selected_owner"] = owner
    validate_assignments(cursor,content["assignments"],ground["g_time"])
    return content, integer_value(data, "c_rentalfee", 0)


def reject_extra(data, allowed):
    if set(data) - allowed:
        fail("APPROVAL_FIELDS_INVALID", "선택한 양식에 맞지 않는 입력 항목이 있습니다.")


def prepare_renewal(cursor, employee, data):
    from .groundcontract import contract_for_ground
    reject_extra(data, {"g_code", "c_treaty", "c_rentalfee"})
    ground = integer_value(data, "g_code", 1)
    contract = contract_for_ground(cursor, ground)
    return {"g_code": ground, "c_seq": contract["c_seq"], "o_seq": contract["o_seq"],
            "c_treaty": string_value(data, "c_treaty", 10000)}, integer_value(data, "c_rentalfee", 0)


def prepare_termination(cursor, employee, data):
    from .groundcontract import contract_for_ground
    reject_extra(data, {"c_seq"})
    cursor.execute("SELECT c.*,m.m_content FROM contract c LEFT JOIN memorandum m ON m.m_code=c.m_code WHERE c.c_seq=%s", (integer_value(data, "c_seq", 1),))
    contract = cursor.fetchone()
    if contract is None:
        fail("CONTRACT_NOT_FOUND", "계약을 찾을 수 없습니다.", 404)
    document = parse_json(contract.get("m_content"), {})
    ground = document.get("내용", {}).get("g_code") if isinstance(document, dict) else None
    if ground is None:
        cursor.execute("SELECT DISTINCT g_code FROM maintain WHERE o_seq=%s", (contract["o_seq"],))
        grounds = cursor.fetchall()
        if len(grounds) != 1:
            fail("CONTRACT_GROUND_AMBIGUOUS", "기존 관계에서 계약 구장을 한 곳으로 확인할 수 없습니다.", 409)
        ground = grounds[0]["g_code"]
    current = contract_for_ground(cursor, ground)
    if current["c_seq"] != contract["c_seq"]:
        fail("CONTRACT_CHANGED", "현재 유효한 계약을 선택해 주세요.", 409)
    return {"c_seq": contract["c_seq"], "g_code": ground, "o_seq": contract["o_seq"],
            "c_treaty": contract["c_treaty"]}, contract["c_rentalfee"]


@router.get("/grounds/managers", summary="매니저와 기존 근무 일정 조회")
def manager_schedules():
    with database() as cursor:
        cursor.execute("SELECT m_id,m_name,m_workplace FROM match_manager WHERE TRIM(m_department)='매니저' AND (m_resignationdate IS NULL OR m_resignationdate>CURRENT_DATE) ORDER BY m_name")
        managers = cursor.fetchall()
        for manager in managers:
            cursor.execute("SELECT a.assign_seq,a.g_code,g.g_name,a.a_day,a.a_time FROM assign a JOIN ground g ON g.g_code=a.g_code WHERE a.m_id=%s ORDER BY a.assign_seq", (manager["m_id"],))
            manager["assign"] = cursor.fetchall()
        return {"results": managers}


@router.get("/grounds/owners", summary="기존 소유주 검색")
def owner_options(keyword: str = Query("", max_length=100)):
    with database() as cursor:
        pattern = f"%{keyword.strip()}%"
        cursor.execute("SELECT o_seq,o_name,o_phone FROM owner WHERE o_name LIKE %s OR o_phone LIKE %s ORDER BY o_name,o_seq", (pattern, pattern))
        return {"results": cursor.fetchall()}

# 최종 수정일 : 2026-10-27
