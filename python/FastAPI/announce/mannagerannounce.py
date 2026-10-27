# 작업자 : 최현준
# 작업 일 : 2026-10-27
"""토큰 인증 없이 매니저 대상 공지를 조회합니다."""
import pymysql
from fastapi import APIRouter, HTTPException, Path, Query
from .announce_common import Classification, TARGETS, connect, database_error

router = APIRouter(prefix="/announce/manager", tags=["매니저 공지 조회"])


def _read_manager_announcements(sequence=None, classify=None, keyword="", limit=50, offset=0):
    # 목록과 상세 모두 매니저 대상 조건을 강제하며 요청값으로 변경할 수 없습니다.
    conditions = ["FIND_IN_SET(%s, a.a_target) > 0"]
    params = ["매니저"]
    if sequence is not None:
        conditions.append("a.a_seq = %s")
        params.append(sequence)
    if classify is not None:
        conditions.append("a.a_classify = %s")
        params.append(classify)
    if keyword:
        conditions.append("(a.a_title LIKE %s OR a.a_detail LIKE %s)")
        params.extend([f"%{keyword}%"] * 2)
    where = " WHERE " + " AND ".join(conditions)
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute("SELECT COUNT(*) AS total FROM announcement a" + where, params)
            total = cursor.fetchone()["total"]
            # 작성자 ID와 함께 직원 이름을 반환해 화면에는 h_name을 표시합니다.
            cursor.execute(
                "SELECT a.a_seq, a.h_id, h.h_name, a.a_classify, a.a_title, "
                "a.a_detail, a.a_date, a.a_target FROM announcement a "
                "JOIN headquarter h ON h.h_id = a.h_id" + where +
                " ORDER BY a.a_date DESC, a.a_seq DESC LIMIT %s OFFSET %s",
                [*params, limit, offset],
            )
            rows = cursor.fetchall()
        for row in rows:
            row["a_target"] = [part for part in (row["a_target"] or "").split(",") if part in TARGETS]
        if sequence is not None:
            if not rows:
                raise HTTPException(404, detail={"code": "ANNOUNCE_NOT_FOUND", "message": "공지를 찾을 수 없습니다."})
            return rows[0]
        return {"total": total, "results": rows, "limit": limit, "offset": offset}
    except pymysql.MySQLError as error:
        raise database_error(error) from error
    finally:
        if connection is not None:
            connection.close()


@router.get("")
def manager_announcements(
    a_classify: Classification | None = None, keyword: str = Query("", max_length=200),
    limit: int = Query(50, ge=1, le=100), offset: int = Query(0, ge=0),
):
    return _read_manager_announcements(classify=a_classify, keyword=keyword.strip(), limit=limit, offset=offset)


@router.get("/{a_seq}")
def manager_announcement(a_seq: int = Path(..., ge=1)):
    return _read_manager_announcements(sequence=a_seq)

# 최종 수정일 : 2026-10-27
