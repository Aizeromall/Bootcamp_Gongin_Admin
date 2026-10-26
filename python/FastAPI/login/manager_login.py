# 작업자 : 최현준
# 최초 작업 일 : 2026-10-22
# 매니저 match_manager 계정 로그인 API
# 처리 순서: JSON 요청 수신 → 공백 제거 → DB 설정 확인 → match_manager 조회 → 결과/오류 응답
import logging
import os
from pathlib import Path

import pymysql
from dotenv import load_dotenv
from fastapi import APIRouter, Body, HTTPException, status

# 작업자 : 양태건
# 수정일 : 2026-10-26
# [추가 시작] 경기 진행 API에서 담당 매니저를 검증할 로그인 토큰 발급
from ..match.manager_session import issue_manager_session
# [추가 끝]


# 현재 파일(login/manager_login.py)을 기준으로 세 단계 상위인 프로젝트 루트의
# .env 파일을 읽습니다. DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME을 사용합니다.
load_dotenv(Path(__file__).resolve().parents[3] / ".env")

# main.py에서 include_router()로 연결할 매니저 로그인 라우터입니다.
# prefix와 아래의 "/login"이 합쳐져 최종 주소는 POST /manager/login이 됩니다.
router = APIRouter(prefix="/manager", tags=["Manager Login"])
logger = logging.getLogger(__name__)


def connect() -> pymysql.connections.Connection:
    """환경변수 DB 설정을 검사한 뒤 MySQL 연결을 생성합니다."""

    # DB 접속에 필요한 값이 비어 있으면 접속 전에 설정 오류를 반환합니다.
    required_keys = ("DB_HOST", "DB_USER", "DB_PASSWORD", "DB_NAME")
    if any(not os.getenv(key) for key in required_keys):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "code": "MANAGER_LOGIN_DB_CONFIG_ERROR",
                "message": "데이터베이스 설정이 완료되지 않았습니다.",
            },
        )

    try:
        # 환경변수 문자열 DB_PORT를 MySQL 연결에 필요한 정수로 변환합니다.
        db_port = int(os.getenv("DB_PORT", "3306"))
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "code": "MANAGER_LOGIN_DB_CONFIG_ERROR",
                "message": "데이터베이스 포트 설정이 올바르지 않습니다.",
            },
        ) from error

    return pymysql.connect(
        host=os.environ["DB_HOST"],
        port=db_port,
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"],
        charset="utf8mb4",
        connect_timeout=5,
    )


# POST /manager/login
# 1. JSON 본문에서 m_id와 m_pw를 받습니다.
# 2. 두 값의 모든 공백을 제거합니다.
# 3. match_manager 테이블에서 일치하는 계정을 SELECT로 조회합니다.
# 4. 조회 결과에 따라 성공 또는 오류 코드를 반환합니다.
@router.post("/login")
def login_manager(
    m_id: str = Body(..., max_length=45),
    m_pw: str = Body(..., max_length=128),
) -> dict[str, str]:
    """match_manager 테이블의 m_id와 m_pw가 일치하는 매니저를 로그인합니다."""

    # 요청값에서 띄어쓰기·탭·줄바꿈을 모두 제거해 같은 입력으로 인식합니다.
    manager_id = "".join(m_id.split())
    password = "".join(m_pw.split())
    if not manager_id or not password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "MANAGER_LOGIN_INVALID_INPUT",
                "message": "아이디와 비밀번호를 입력해 주세요.",
            },
        )

    # finally에서 안전하게 close하기 위해 연결 객체를 먼저 초기화합니다.
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:

            # 작업자 : 양태건
            # 수정일 : 2026-10-26
            # [수정 1 시작] 아이디·비밀번호와 새 부서명(m_department)을 함께 확인합니다.
            # 매니저 부서가 아닌 계정은 매니저 로그인에 사용할 수 없습니다.
            # 아이디·비밀번호 비교는 기존 파라미터 바인딩을 유지합니다.
            cursor.execute(
                "SELECT m_id, m_name, m_department FROM `match_manager` "
                "WHERE m_id = %s AND m_pw = %s AND TRIM(m_department) = %s LIMIT 1",
                (manager_id, password, "매니저"),
            )
            manager = cursor.fetchone()
            # [수정 1 끝]

        # 계정 미존재와 비밀번호 불일치에는 같은 401을 반환해 계정 존재 여부를 숨깁니다.
        if manager is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail={
                    "code": "MANAGER_LOGIN_INVALID_CREDENTIALS",
                    "message": "아이디 또는 비밀번호가 올바르지 않습니다.",
                },
            )

        # 작업자 : 양태건
        # 수정일 : 2026-10-26
        # [수정 2 시작] 기존 m_id에 담당자 이름과 인증된 역할을 추가합니다.
        # 프론트는 m_name을 표시하고 role="manager"로 경기매니저 화면을 결정합니다.
        # 비밀번호는 응답에 포함하지 않습니다.
        return {
            "result": "OK",
            "m_id": manager[0],
            "m_name": manager[1],
            # 작업자 : 양태건
            # 수정일 : 2026-10-26
            # [추가 시작] 프론트에서도 인증된 부서 정보를 확인합니다.
            "m_department": manager[2].strip(),
            # [추가 끝]
            "role": "manager",
            # 작업자 : 양태건
            # 수정일 : 2026-10-26
            # [추가 시작] DB 세션 테이블 없이 12시간 유효한 서명 토큰 전달
            "access_token": issue_manager_session(manager[0]),
            # [추가 끝]
        }
        # [수정 2 끝]

    except HTTPException:
        # 의도적으로 만든 오류 코드는 상태를 변경하지 않고 그대로 전달합니다.
        raise
    except pymysql.err.OperationalError as error:
        logger.exception("매니저 로그인 DB 연결 실패")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "MANAGER_LOGIN_DB_CONNECTION_ERROR",
                "message": "데이터베이스에 연결할 수 없습니다.",
            },
        ) from error
    except pymysql.MySQLError as error:
        logger.exception("매니저 로그인 DB 조회 실패")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "code": "MANAGER_LOGIN_DB_QUERY_ERROR",
                "message": "로그인 정보 조회에 실패했습니다.",
            },
        ) from error
    except Exception as error:
        logger.exception("매니저 로그인 처리 실패")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "code": "MANAGER_LOGIN_SERVER_ERROR",
                "message": "로그인 처리에 실패했습니다.",
            },
        ) from error
    finally:
        # 성공·실패·예외와 관계없이 DB 연결을 닫아 연결 누수를 방지합니다.
        if connection is not None:
            connection.close()

# 최종 수정 일 : 2026-10-26
