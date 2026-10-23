# 작업자 : 양태건
# 작업 일 : 2026-10-23
# 담당 매니저의 회원 경기 결과기록 등록 API

from fastapi import APIRouter, Body, HTTPException
from database import connect
import pymysql
import traceback


router = APIRouter(prefix="/match", tags=["경기 결과기록"])


# 예약번호로 회원을 확인하고 출석 완료된 회원의 경기 결과를 INSERT
@router.post("/score/{m_id}/{r_seq}")
def match_score(
    m_id: str,
    r_seq: int,
    c_r_r_team: str = Body(..., min_length=1, max_length=50),
    e_code: str = Body(..., min_length=1, max_length=20, examples=["SOCCER"]),
    c_r_r_statcode: str = Body(..., min_length=1, max_length=50),
    c_r_r_score: str = Body(..., min_length=1, max_length=20)
):
    c_r_r_team = c_r_r_team.strip()
    e_code = e_code.strip()
    c_r_r_statcode = c_r_r_statcode.strip()
    c_r_r_score = c_r_r_score.strip()
    if not all((c_r_r_team, e_code, c_r_r_statcode, c_r_r_score)):
        raise HTTPException(status_code=400, detail="팀, 종목코드, 스탯코드, 최종 스코어를 입력해 주세요.")

    conn = None

    try:
        conn = connect()

        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            # 출석 API와 같은 예약 잠금을 사용하여 동시 중복 등록 방지
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

            cursor.execute(
                "SELECT assign_seq FROM assign WHERE m_id = %s AND g_code = %s LIMIT 1",
                (m_id, reservation["g_code"])
            )
            if cursor.fetchone() is None:
                raise HTTPException(status_code=403, detail="담당 구장의 회원만 경기기록을 등록할 수 있습니다.")

            # 기존 출석 기록과 경기 결과기록을 확인
            cursor.execute(
                """
                SELECT c_r_r_attendance, c_r_r_score
                FROM c_result_record
                WHERE c_id_seq = %s AND g_code = %s AND c_r_r_code = %s
                FOR UPDATE
                """,
                (reservation["c_id_seq"], reservation["g_code"], reservation["c_r_r_code"])
            )
            records = cursor.fetchall()
            if any(record["c_r_r_score"] is not None for record in records):
                raise HTTPException(status_code=409, detail="이미 경기 결과가 등록된 예약입니다.")
            if not any(record["c_r_r_attendance"] == 1 for record in records):
                raise HTTPException(status_code=409, detail="회원의 출석 처리를 먼저 완료해 주세요.")

            # 기존 출석 행은 유지하고 경기 결과를 별도 행으로 등록
            cursor.execute(
                """
                INSERT INTO c_result_record
                    (m_id, g_code, c_id_seq, c_r_r_team, c_r_r_code,
                     e_code, c_r_r_statcode, c_r_r_attendance, c_r_r_score)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (m_id, reservation["g_code"], reservation["c_id_seq"],
                 c_r_r_team, reservation["c_r_r_code"], e_code,
                 c_r_r_statcode, True, c_r_r_score)
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
            "c_r_r_team": c_r_r_team,
            "c_r_r_code": reservation["c_r_r_code"],
            "e_code": e_code,
            "c_r_r_statcode": c_r_r_statcode,
            "c_r_r_attendance": True,
            "c_r_r_score": c_r_r_score
        }

    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise

    except Exception as e:
        if conn is not None:
            conn.rollback()
        traceback.print_exc()
        print("경기기록 등록 오류:", repr(e))
        raise HTTPException(status_code=500, detail="경기기록 등록 중 서버 오류가 발생했습니다.")

    finally:
        if conn is not None:
            conn.close()
