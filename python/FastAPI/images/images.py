# 배너 이미지 공통 모듈 (insert_banner_image.py, select_banner_image.py가 함께 사용)
# 작업 일 : 2026-10-28
#
# [사용하는 테이블 - 실제 DB 구조 확인 결과]
#   banner_image : b_seq(PK, 자동증가), b_image(파일명, NOT NULL)
#   choice       : c_image_seq(PK, 자동증가), h_id(등록 직원 FK → headquarter), b_seq(FK → banner_image),
#                  c_boolean(선택 여부, 기본 0), c_start(시작일), c_end(종료일)
#
# 이 파일에는 라우터를 두지 않고, 두 라우터가 같이 쓰는 값과 함수만 모아 둡니다.
import logging
import os
from contextlib import contextmanager
from pathlib import Path

import pymysql

# 기존 구장 사진 작업(approval)의 공통 함수를 수정 없이 가져와 재사용합니다.
from FastAPI.approval.groundapproval import API_RESPONSES, fail, now
from FastAPI.approval.groundshoot import MAX_BYTES, validate_image
from FastAPI.login.admin_login import connect

logger = logging.getLogger(__name__)

# 배너 이미지를 등록·선택할 수 있는 부서 (headquarter.h_department 값)
BANNER_DEPARTMENT = "홍보팀"

# 배너 이미지 파일 저장 폴더. .env의 BANNER_UPLOAD_DIR로 바꿀 수 있고, 없으면 프로젝트의 uploads/banners를 씁니다.
# (이 파일 기준 parents[3]은 Bootcamp_Gongin_Admin 폴더입니다.)
UPLOAD_ROOT = Path(os.getenv("BANNER_UPLOAD_DIR", Path(__file__).resolve().parents[3] / "uploads" / "banners")).resolve()

# 저장된 파일명 형식 (uuid 32자리 + 확장자). 파일 조회·삭제 때 경로 조작을 막는 데 사용합니다.
FILENAME_PATTERN = r"[0-9a-f]{32}[.](jpg|png|webp)"

# 배너 이미지 파일을 내려주는 API 경로. 응답의 image_url을 만들 때 사용합니다.
FILE_URL_PREFIX = "/images/banner/files/"


@contextmanager
def database(write=False):
    """DB 연결·커밋·롤백만 관리합니다. 업무 SQL은 각 기능 함수에 직접 작성합니다.

    write=True  : 블록이 끝나면 커밋하고, 예외가 나면 롤백합니다.
    write=False : 조회 전용이라 커밋하지 않습니다.
    """
    connection = None
    try:
        connection = connect()
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            yield cursor
        if write:
            connection.commit()
    except pymysql.MySQLError as error:
        if connection is not None:
            connection.rollback()
        # 비밀번호 같은 정보가 로그에 남지 않도록 오류 종류만 기록합니다.
        logger.error("배너 이미지 DB 처리 실패 (%s)", type(error).__name__)
        fail("BANNER_DB_ERROR", "DB 연결과 banner_image·choice 테이블 구조를 확인해 주세요.", 503)
    except Exception:
        if connection is not None:
            connection.rollback()
        raise
    finally:
        if connection is not None:
            connection.close()


def check_staff(cursor, h_id):
    """홍보팀 재직자인지 확인하고 직원 아이디를 돌려줍니다. 아니면 403으로 막습니다.

    재직 조건: 퇴사일(h_resignationdate)이 없거나 오늘보다 뒤인 직원.
    """
    cursor.execute(
        "SELECT h_id FROM headquarter WHERE h_id=%s AND TRIM(h_department)=%s "
        "AND (h_resignationdate IS NULL OR h_resignationdate>CURRENT_DATE)",
        (h_id.strip(), BANNER_DEPARTMENT),
    )
    staff = cursor.fetchone()
    if staff is None:
        fail("DEPARTMENT_FORBIDDEN", f"{BANNER_DEPARTMENT} 재직자만 사용할 수 있습니다.", 403)
    return staff["h_id"]


def expire_choices(cursor):
    """종료일이 지난 선택(choice)의 c_boolean을 0(False)으로 바꿉니다.

    별도 스케줄러 없이, 선택/배너 목록을 조회하는 시점에 호출해 '종료일이 지나면 자동 False'를 구현합니다.
    오늘 날짜는 DB 서버 시간이 아니라 한국 시간(now())을 기준으로 합니다.
    호출하는 쪽은 database(write=True)로 열어야 변경이 저장됩니다.
    """
    cursor.execute("UPDATE choice SET c_boolean=0 WHERE c_boolean=1 AND c_end<%s", (now().date(),))


def image_url(b_image):
    """파일명을 앱에서 바로 쓸 수 있는 조회 경로로 바꿉니다."""
    return FILE_URL_PREFIX + b_image
