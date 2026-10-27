# 작업자 : 최현준
# 작업 일 : 2026-10-27
"""휴가 작성에 필요한 대리인 후보와 확정 휴가 조회."""
from fastapi import APIRouter, Query
from .groundapproval import API_RESPONSES, database, fail

router = APIRouter(prefix="/approval/vacation", tags=["휴가 작성"], responses=API_RESPONSES)


@router.get("/deputies", summary="휴가 대리인 후보 조회", description="신청자와 같은 부서의 재직 중인 직원을 조회합니다. 날짜 중복은 상신·최종 승인 시 검사합니다.")
def deputies(h_id: str = Query(..., min_length=1, max_length=50, description="휴가 신청 직원 아이디")):
    with database() as cursor:
        cursor.execute("SELECT h_department FROM headquarter WHERE h_id=%s AND (h_resignationdate IS NULL OR h_resignationdate>CURRENT_DATE)", (h_id.strip(),))
        employee = cursor.fetchone()
        if employee is None:
            fail("STAFF_NOT_FOUND", "재직 중인 직원을 찾을 수 없습니다.", 404)
        cursor.execute("SELECT h_id,h_name,h_position,h_department FROM headquarter WHERE h_id<>%s AND TRIM(h_department)=%s AND (h_resignationdate IS NULL OR h_resignationdate>CURRENT_DATE) ORDER BY h_name", (h_id.strip(), (employee["h_department"] or "").strip()))
        return {"results": cursor.fetchall()}


@router.get("", summary="확정 휴가·대리 업무 조회", description="인증 없이 승인된 휴가를 조회합니다. 직원 아이디를 지정하면 해당 직원의 휴가와 대리 업무로 필터링합니다.")
def vacations(h_id: str | None = Query(None, min_length=1, max_length=50, description="직원 아이디 필터")):
    with database() as cursor:
        sql = "SELECT v.*,h.h_name,d.h_name AS deputy_name FROM h_vacation v JOIN headquarter h ON h.h_id=v.h_id LEFT JOIN headquarter d ON d.h_id=v.h_deputy"
        params = []
        if h_id is not None:
            sql += " WHERE v.h_id=%s OR v.h_deputy=%s"
            params = [h_id.strip(), h_id.strip()]
        cursor.execute(sql + " ORDER BY v.h_start DESC,v.v_seq DESC", params)
        return {"results": cursor.fetchall()}

# 최종 수정일 : 2026-10-27
