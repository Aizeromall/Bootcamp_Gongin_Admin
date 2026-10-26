# 작업자 : 최현준
# 작업 일 : 2026-10-22
# 관리자 Headquarter 계정 로그인 API
# 2026-10-26: 담당자 정보와 본사 역할 응답을 원본에 통합


# 처리 순서: JSON 요청 수신 → 공백 제거 → DB 설정 확인 → Headquarter 조회 → 결과/오류 응답
import logging
import os
from pathlib import Path

# MySQL 연결 및 .env 파일 로드에 사용하는 모듈
import pymysql
from dotenv import load_dotenv
# APIRouter는 로그인 주소를 등록하고, Body는 JSON 본문 값을 받아옴
from fastapi import APIRouter, Body, HTTPException, status


# 작업자 : 양태건
# 수정일 : 2026-10-26
# 현재 파일을 기준으로 프로젝트 루트의 .env 파일을 읽습니다.
# DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME을 사용
# [수정 1 시작] 프로젝트 루트의 .env 경로로 수정 (parents[2] → parents[3])
load_dotenv(Path(__file__).resolve().parents[3] / ".env")
# [수정 1 끝]

# main.py에서 include_router()로 연결할 관리자 API 라우터
# prefix와 아래의 "/login" 경로가 합쳐져 최종 주소는 POST /admin/login이 진행
# 관리자 로그인 라우터는 한 번만 정의합니다.
router = APIRouter(prefix="/admin", tags=["Admin Login"])
# DB 오류의 상세 원인은 서버 로그에만 남기고 클라이언트에는 오류 코드만 전달
logger = logging.getLogger(__name__)


def connect() -> pymysql.connections.Connection:
    """로그인 조회에 사용할 MySQL 연결을 생성합니다.

    연결 전에 필수 환경변수와 포트 값을 검사하여, 잘못된 .env 설정을
    DB 연결 오류와 구분된 ADMIN_LOGIN_DB_CONFIG_ERROR로 응답합니다.
    """

    # DB 접속에 반드시 필요한 값이 하나라도 비어 있으면 접속 불가
    required_keys = ("DB_HOST", "DB_USER", "DB_PASSWORD", "DB_NAME")
    if any(not os.getenv(key) for key in required_keys):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "code": "ADMIN_LOGIN_DB_CONFIG_ERROR",
                "message": "데이터베이스 설정이 완료되지 않았습니다.",
            },
        )

    # DB_PORT는 문자열 환경변수-> MySQL 연결 전에 정수로 변환
    try:
        db_port = int(os.getenv("DB_PORT", "3306"))
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "code": "ADMIN_LOGIN_DB_CONFIG_ERROR",
                "message": "데이터베이스 포트 설정이 올바르지 않습니다.",
            },
        ) from error

    # pymysql.connect()는 실제 DB 연결을 만들며, 성공한 연결은 login_admin()에서 Close
    return pymysql.connect(
        host=os.environ["DB_HOST"],
        port=db_port,
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"],
        charset="utf8mb4",
        connect_timeout=5,
    )


# POST /admin/login
# 1. JSON 본문에서 h_id와 h_pw를 받아옴
# 2. 두 값의 공백을 제거
# 3. Headquarter 테이블에서 일치하는 계정을 SELECT로 조회
# 4. 조회 결과에 따라 성공 또는 오류 코드를 반환
@router.post("/login")
def login_admin(
    # Body(...)는 필수 JSON 필드라는 뜻이며, max_length는 과도하게 긴 입력을 제한
    h_id: str = Body(..., max_length=45),
    h_pw: str = Body(..., max_length=128),
) -> dict[str, str | None]:
    """Headquarter 테이블의 h_id와 h_pw가 일치하는 관리자를 로그인합니다."""

    # 아이디·비밀번호의 모든 공백을 제거하여 입력 형식을 통일
    admin_id = "".join(h_id.split())
    password = "".join(h_pw.split())
    # 공백 제거 후 값이 없으면 DB 조회 전에 요청 오류(400)로 종료
    if not admin_id or not password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "ADMIN_LOGIN_INVALID_INPUT",
                "message": "아이디와 비밀번호를 입력해 주세요.",
            },
        )

    # finally에서 안전하게 close하기 위해 연결 객체를 먼저 None으로 초기화
    connection = None
    try:
        # 1) .env DB 설정을 사용해 연결
        connection = connect()
        with connection.cursor() as cursor:
            # 2) 파라미터 바인딩으로 SQL 삽입 공격을 방지하며 계정 존재 여부만 조회
            #    로그인 성공 여부만 필요하므로 비밀번호는 응답·로그에 포함하지 않음
            cursor.execute(

# 작업자 : 양태건
# # 수정일 : 2026-10-26
                # [수정 2 시작] 본사 테이블에서 인증된 담당자의 표시 정보를 함께 조회
                # 매니저 테이블을 대신 조회하거나 본사 권한으로 승격하지 않습니다.
                "SELECT h_id, h_name, h_position, h_department FROM `Headquarter` "
                "WHERE h_id = %s AND h_pw = %s LIMIT 1",
                (admin_id, password),
            )
            headquarter = cursor.fetchone()
            # [수정 2 끝]

        # 3) 없는 아이디와 비밀번호 불일치에는 같은 401 응답을 반환해 계정 존재 여부를 숨김
        if headquarter is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail={
                    "code": "ADMIN_LOGIN_INVALID_CREDENTIALS",
                    "message": "아이디 또는 비밀번호가 올바르지 않습니다.",
                },
            )

# 작업자 : 양태건
# 수정일 : 2026-10-26
        # [수정 3 시작] 기존 h_id 응답을 유지하고 담당자 정보와 서버에서 정한 역할 반환
        # role은 프론트의 화면 선택값이 아닌 인증에 사용한 본사 테이블 기준입니다.
        # 비밀번호는 반환하지 않습니다.
        # 주의: 이 응답은 인증 토큰이 아닙니다. 본사 전용 API는 별도 인증·권한 검사가 필요합니다.
        return {
            "result": "OK",
            "h_id": headquarter[0],
            "h_name": headquarter[1],
            "h_position": headquarter[2],
            "h_department": headquarter[3],
            "role": "headquarters",
        }
        # [수정 3 끝]

    except HTTPException:
        # 위에서 의도적으로 만든 400·401·500 오류 코드는 그대로 클라이언트에 전달
        raise
    except pymysql.err.OperationalError as error:
        # DB 서버 미실행, 네트워크 단절 등 연결 단계 오류는 503으로 구분
        logger.exception("관리자 로그인 DB 연결 실패")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "ADMIN_LOGIN_DB_CONNECTION_ERROR",
                "message": "데이터베이스에 연결할 수 없습니다.",
            },
        ) from error
    except pymysql.MySQLError as error:
        # SQL 문법, 테이블/컬럼 문제 등 MySQL 조회 오류는 500으로 구분
        logger.exception("관리자 로그인 DB 조회 실패")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "code": "ADMIN_LOGIN_DB_QUERY_ERROR",
                "message": "로그인 정보 조회에 실패했습니다.",
            },
        ) from error
    except Exception as error:
        # 예상하지 못한 오류도 서버 로그에 원인을 남기고 공통 500 코드로 응답
        logger.exception("관리자 로그인 처리 실패")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={
                "code": "ADMIN_LOGIN_SERVER_ERROR",
                "message": "로그인 처리에 실패했습니다.",
            },
        ) from error
    finally:
        # 성공·실패·예외와 관계없이 만든 DB 연결을 닫아 연결 누수를 방지
        if connection is not None:
            connection.close()


# 최종 수정일 : 2026-10-26
# 작업자 : 양태건