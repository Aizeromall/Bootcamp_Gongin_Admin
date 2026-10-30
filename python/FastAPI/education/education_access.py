# 수정 일 : 2026-10-27 / 작업자 : 양태건
# 서명 토큰의 본사 역할과 현재 재직 여부를 함께 확인합니다.
import pymysql
from fastapi import Header, HTTPException
from database import connect
from ..match.manager_session import verify_headquarters_token


def require_headquarters(authorization: str = Header(default="")) -> str:
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "본사 계정으로 다시 로그인해 주세요.")
    staff_id = verify_headquarters_token(authorization[7:])
    conn = connect()
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute(
                "SELECT h_id FROM headquarter WHERE h_id=%s AND h_resignationdate IS NULL",
                (staff_id,),
            )
            if cursor.fetchone() is None:
                raise HTTPException(403, "재직 중인 본사 직원만 사용할 수 있습니다.")
        return staff_id
    finally:
        conn.close()


# 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
