# 작업자 : 양태건
# 작업 일 : 2026-10-23
# 경기 매니저 예약 경기 조회 API

from fastapi import APIRouter, HTTPException
from database import connect
import pymysql
import traceback


router = APIRouter(
    prefix="/match",
    tags=["경기 목록 조회"]
)


# 담당 매니저가 배정된 구장의 예약 조회
@router.get("/list/{m_id}")
def get_match_list(m_id: str):

    conn = None

    try:
        conn = connect()

        with conn.cursor(pymysql.cursors.DictCursor) as cursor:

            # 매니저 존재 여부와 이름 확인
            cursor.execute(
                """
                SELECT m_id, m_name
                FROM match_manager
                WHERE m_id = %s
                """,
                (m_id,)
            )

            manager = cursor.fetchone()

            if manager is None:
                raise HTTPException(
                    status_code=404,
                    detail="매니저 ID가 존재하지 않습니다."
                )

            # 담당 구장의 예약 조회: 배정 기록이 여러 개여도 예약 중복 방지
            sql = """
                SELECT
                    r.r_seq,
                    r.r_date,
                    TIME_FORMAT(r.rs_time, '%%H:%%i:%%s') AS rs_time,
                    TIME_FORMAT(r.re_time, '%%H:%%i:%%s') AS re_time,
                    r.g_code,
                    g.g_name,
                    g.g_num,
                    c.c_id_seq,
                    c.c_name,
                    c.c_rating,
                    c.c_position,
                    r.r_check
                FROM reservation AS r
                JOIN ground AS g
                    ON r.g_code = g.g_code
                JOIN customer AS c
                    ON r.c_id_seq = c.c_id_seq
                WHERE EXISTS (
                    SELECT 1
                    FROM assign AS a
                    WHERE a.g_code = r.g_code
                        AND a.m_id = %s
                )
                ORDER BY
                    r.r_date ASC,
                    r.rs_time ASC,
                    r.r_seq ASC
            """

            cursor.execute(sql, (m_id,))
            result = cursor.fetchall()

        return {
            "m_id": manager["m_id"],
            "m_name": manager["m_name"],
            "reservation_count": len(result),
            "reservations": result
        }

    except HTTPException:
        raise

    except Exception as e:
        traceback.print_exc()
        print("조회 오류:", repr(e))

        raise HTTPException(
            status_code=500,
            detail="조회 중 서버 오류가 발생했습니다."
        )

    finally:
        if conn is not None:
            conn.close()
