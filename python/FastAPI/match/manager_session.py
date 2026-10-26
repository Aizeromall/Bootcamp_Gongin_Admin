# 작업자 : 양태건
# 수정일 : 2026-10-26
# [수정 시작] 삭제된 세션 테이블 대신 서버 서명 토큰과 실제 매니저 부서를 확인합니다.
import base64
import hashlib
import hmac
import json
import os
import secrets
import time

import pymysql
from fastapi import Header, HTTPException
from database import connect

# 개발 서버는 재시작하면 기존 토큰이 만료됩니다. 여러 프로세스 운영 시 같은 환경값을 설정합니다.
_SIGNING_KEY = (os.getenv("MANAGER_TOKEN_SECRET") or secrets.token_urlsafe(48)).encode()


def issue_manager_session(manager_id: str) -> str:
    payload = dict(
        m_id=manager_id,
        role="manager",
        exp=int(time.time()) + 43200,
        nonce=secrets.token_hex(16),
    )
    encoded = (
        base64.urlsafe_b64encode(json.dumps(payload, separators=(",", ":")).encode())
        .decode()
        .rstrip("=")
    )
    signature = hmac.new(_SIGNING_KEY, encoded.encode(), hashlib.sha256).hexdigest()
    return encoded + "." + signature


def verify_manager_token(token: str) -> str:
    try:
        encoded, signature = token.split(".")
        expected = hmac.new(_SIGNING_KEY, encoded.encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(signature, expected):
            raise ValueError("signature")
        payload = json.loads(
            base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
        )
        if (
            payload["role"] != "manager"
            or payload["exp"] <= time.time()
            or not isinstance(payload["m_id"], str)
            or not payload["m_id"]
        ):
            raise ValueError("payload")
        return payload["m_id"]
    except (ValueError, KeyError, TypeError, UnicodeError):
        raise HTTPException(
            401, "로그인이 만료되었거나 올바르지 않습니다. 다시 로그인해 주세요."
        ) from None


def require_manager(authorization: str = Header(default="")) -> str:
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "다시 로그인해 주세요.")
    manager_id = verify_manager_token(authorization[7:])
    conn = connect()
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute(
                "SELECT m_id FROM match_manager WHERE m_id=%s AND TRIM(m_department)=%s",
                (manager_id, "매니저"),
            )
            if cursor.fetchone() is None:
                raise HTTPException(
                    403, "매니저 부서에 등록된 담당자만 접근할 수 있습니다."
                )
        return manager_id
    finally:
        conn.close()


# [수정 끝]
