## 회원 및 매니저 관리
## 최초작업일 2026-10-22 김병재

from fastapi import APIRouter, HTTPException
import pymysql

from database import connect

router = APIRouter(prefix="/management", tags=["management"])

# 유효 경고 수 = 제재 건수 - 처리된(h_id 있음) 이의신청 건수 (0 미만 방지)
_WARN_SQL = """
    GREATEST(
        (SELECT COUNT(*) FROM c_sanction s WHERE s.c_id_seq = c.c_id_seq)
        - (SELECT COUNT(*) FROM appeal a WHERE a.c_id_seq = c.c_id_seq AND a.h_id IS NOT NULL),
        0
    )
"""


def _like(keyword):
    return f"%{keyword}%"


def _sanction_history(curs, c_id_seq):
    """회원 제재 이력. 처리된 이의신청이 이의신청일 이전의 가장 오래된 제재부터 하나씩 철회한다."""
    curs.execute(
        "SELECT cs_seq, cs_date, cs_detail FROM c_sanction WHERE c_id_seq = %s ORDER BY cs_date",
        (c_id_seq,),
    )
    sanctions = curs.fetchall()
    curs.execute(
        "SELECT a_date FROM appeal WHERE c_id_seq = %s AND h_id IS NOT NULL ORDER BY a_date",
        (c_id_seq,),
    )
    for appeal in curs.fetchall():
        for s in sanctions:
            if "status" not in s and s["cs_date"] <= appeal["a_date"]:
                s["status"] = "철회"
                break
    for s in sanctions:
        s.setdefault("status", "유효")
    return sorted(sanctions, key=lambda s: s["cs_date"], reverse=True)


@router.get("/members")
async def list_members(keyword: str = ""):
    conn = None
    try:
        conn = connect()
        curs = conn.cursor(pymysql.cursors.DictCursor)

        sql = f"""
            SELECT c.c_id_seq, c.c_name, c.c_prefer_stock, c.c_signupdate, c.c_deletdate,
                   (SELECT COUNT(*) FROM c_result_record r WHERE r.c_id_seq = c.c_id_seq) AS match_count,
                   {_WARN_SQL} AS warning_count
            FROM customer c
        """
        params = []
        if keyword:
            sql += " WHERE c.c_name LIKE %s OR c.c_id_seq LIKE %s OR c.c_phone LIKE %s"
            params = [_like(keyword)] * 3
        sql += " ORDER BY c.c_signupdate DESC"

        curs.execute(sql, params)
        rows = curs.fetchall()
        return {"total": len(rows), "results": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if conn:
            conn.close()


@router.get("/members/{c_id_seq}")
async def get_member(c_id_seq: str):
    conn = None
    try:
        conn = connect()
        curs = conn.cursor(pymysql.cursors.DictCursor)

        curs.execute(
            f"""
            SELECT c.c_id_seq, c.c_name, c.c_phone, c.c_gender, c.c_birthday, c.c_address,
                   c.c_prefer_stock, c.c_position, c.c_team, c.c_signupdate, c.c_deletdate,
                   (SELECT COUNT(*) FROM c_result_record r WHERE r.c_id_seq = c.c_id_seq) AS match_count,
                   (SELECT COUNT(*) FROM report rp WHERE rp.r_person = c.c_name) AS received_report_count,
                   (SELECT COUNT(*) FROM report rp WHERE rp.c_id_seq = c.c_id_seq) AS sent_report_count,
                   {_WARN_SQL} AS warning_count
            FROM customer c
            WHERE c.c_id_seq = %s
            """,
            (c_id_seq,),
        )
        member = curs.fetchone()
        if not member:
            raise HTTPException(status_code=404, detail="회원을 찾을 수 없습니다.")

        # 받은 신고: r_person 이 회원 이름과 같은 신고
        curs.execute(
            """
            SELECT r_seq, r_date, r_reason,
                   IF(h_id IS NULL, '미처리', '처리완료') AS state
            FROM report WHERE r_person = %s ORDER BY r_date DESC
            """,
            (member["c_name"],),
        )
        member["received_reports"] = curs.fetchall()
        member["sanctions"] = _sanction_history(curs, c_id_seq)
        return member
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if conn:
            conn.close()


@router.get("/managers")
async def list_managers(keyword: str = ""):
    conn = None
    try:
        conn = connect()
        curs = conn.cursor(pymysql.cursors.DictCursor)

        sql = """
            SELECT m.m_id, m.m_name, m.m_phone, m.m_gender, m.m_workplace,
                   (SELECT COUNT(*) FROM sanction s WHERE s.m_id = m.m_id) AS sanction_count
            FROM match_manager m
        """
        params = []
        if keyword:
            sql += " WHERE m.m_name LIKE %s OR m.m_id LIKE %s OR m.m_phone LIKE %s"
            params = [_like(keyword)] * 3
        sql += " ORDER BY m.m_id"

        curs.execute(sql, params)
        rows = curs.fetchall()
        return {"total": len(rows), "results": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if conn:
            conn.close()


@router.get("/managers/{m_id}")
async def get_manager(m_id: str):
    conn = None
    try:
        conn = connect()
        curs = conn.cursor(pymysql.cursors.DictCursor)

        curs.execute(
            "SELECT m_id, m_name, m_phone, m_gender, m_workplace FROM match_manager WHERE m_id = %s",
            (m_id,),
        )
        manager = curs.fetchone()
        if not manager:
            raise HTTPException(status_code=404, detail="매니저를 찾을 수 없습니다.")

        curs.execute(
            """
            SELECT a.assign_seq, a.g_code, g.g_name, a.a_day, a.a_time
            FROM assign a JOIN ground g ON g.g_code = a.g_code
            WHERE a.m_id = %s ORDER BY a.a_day, a.a_time
            """,
            (m_id,),
        )
        # 2026-10-26 수정 / 작업자 : 양태건 / 실제 assign 테이블의 a_day(요일), a_time(시간)을 조회합니다.
        manager["assigns"] = curs.fetchall()

        curs.execute(
            "SELECT evaluate_seq, e_date, e_detail FROM evaluate WHERE m_id = %s ORDER BY e_date DESC",
            (m_id,),
        )
        manager["evaluates"] = curs.fetchall()

        curs.execute(
            "SELECT s_seq, s_date, s_detail FROM sanction WHERE m_id = %s ORDER BY s_date DESC",
            (m_id,),
        )
        manager["sanctions"] = curs.fetchall()

        curs.execute(
            "SELECT hire_seq, h_date FROM hire WHERE m_id = %s ORDER BY h_date DESC",
            (m_id,),
        )
        manager["hires"] = curs.fetchall()
        return manager
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if conn:
            conn.close()
