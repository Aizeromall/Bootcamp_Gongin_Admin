## 문의 답변 및 관리
## 최초작업일 2026-10-23 김병재

from fastapi import APIRouter
import pymysql

from database import connect
from .list_inquiry import SELECT_INQUIRY, attach_follow_ups

router = APIRouter()


# 문의 상세 조회: 원글(level 0) 1건과 추가 문의(follow_ups)를 함께 반환
@router.get("/{i_seq}")
async def detail_inquiry(i_seq: int):

    conn = None

    try:
        conn = connect()
        curs = conn.cursor(pymysql.cursors.DictCursor)

        # 목록과 동일한 SELECT에 i_seq 조건만 추가
        curs.execute(SELECT_INQUIRY + " AND q.i_seq = %s", (i_seq,))
        rows = attach_follow_ups(curs, curs.fetchall())
        if not rows:
            return {"result": "Error", "message": "inquiry not found"}
        return rows[0]

    except Exception as e:
        print("Error:", e)
        return {'result': 'Error'}

    finally:
        if conn is not None:
            conn.close()
