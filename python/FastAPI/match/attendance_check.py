# 작업자 : 양태건
# 작업 일 : 2026-10-23
# 담당 구장 예약 회원 출석 등록 API

from fastapi import APIRouter, Body, HTTPException
from pydantic import StrictBool
from database import connect
import pymysql
import traceback


router = APIRouter(prefix="/match", tags=["출석 체크 경기 입력"])


# 출석 체크 완료 시 회원별로 호출 (true: 출석, false: 결석)
@router.post("/attendance/{m_id}/{r_seq}")
def attendance_check(
    m_id: str,
    r_seq: int,
    c_r_r_attendance: StrictBool = Body(..., embed=True)
):
    conn = None

    try:
        conn = connect()

        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            # 같은 예약의 동시 요청을 순서대로 처리하여 중복 등록 방지
            cursor.execute(
                """
                SELECT c_id_seq, g_code,
                       CONCAT(g_code, '_', DATE_FORMAT(r_date, '%%Y%%m%%d'),
                              '_', TIME_FORMAT(rs_time, '%%H%%i%%s')) AS c_r_r_code
                FROM reservation
                WHERE r_seq = %s
                FOR UPDATE
                """,
                (r_seq,)
            )
            reservation = cursor.fetchone()

            if reservation is None:
                raise HTTPException(status_code=404, detail="예약을 찾을 수 없습니다.")

            # 요청한 매니저에게 해당 구장이 배정되어 있는지 확인
            cursor.execute(
                "SELECT assign_seq FROM assign WHERE m_id = %s AND g_code = %s LIMIT 1",
                (m_id, reservation["g_code"])
            )
            if cursor.fetchone() is None:
                raise HTTPException(status_code=403, detail="담당 구장의 예약만 출석 처리할 수 있습니다.")

            cursor.execute(
                """
                SELECT c_r_r_seq FROM c_result_record
                WHERE c_id_seq = %s AND g_code = %s AND c_r_r_code = %s
                LIMIT 1 FOR UPDATE
                """,
                (reservation["c_id_seq"], reservation["g_code"], reservation["c_r_r_code"])
            )
            if cursor.fetchone() is not None:
                raise HTTPException(status_code=409, detail="이미 출석 체크가 등록된 예약입니다.")

            # 작업자 : 양태건
            # 수정일 : 2026-10-26
            # 부상 없는 출석 기록도 NOT NULL 컬럼에 빈 문자열을 저장합니다.
            # 경기 전이므로 팀·스탯은 입력하지 않고 출석 여부만 결과기록에 등록
            cursor.execute(
                """
                INSERT INTO c_result_record
                    (m_id, g_code, c_id_seq, c_r_r_code, c_r_r_attendance, c_r_r_injury)
                VALUES (%s, %s, %s, %s, %s, '')
                """,
                (m_id, reservation["g_code"], reservation["c_id_seq"],
                 reservation["c_r_r_code"], c_r_r_attendance)
            )
            c_r_r_seq = cursor.lastrowid

        conn.commit()
        return {
            "result": "OK",
            "c_r_r_seq": c_r_r_seq,
            "r_seq": r_seq,
            "m_id": m_id,
            "c_id_seq": reservation["c_id_seq"],
            "g_code": reservation["g_code"],
            "c_r_r_code": reservation["c_r_r_code"],
            "c_r_r_attendance": c_r_r_attendance
        }

    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise

    except Exception as e:
        if conn is not None:
            conn.rollback()
        traceback.print_exc()
        print("출석 등록 오류:", repr(e))
        raise HTTPException(status_code=500, detail="출석 등록 중 서버 오류가 발생했습니다.")

    finally:
        if conn is not None:
            conn.close()
