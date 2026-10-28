# 배너 이미지 등록 라우터 (banner_image 테이블에 사진을 넣는 기능)
# 작업 일 : 2026-10-28
#
# [기능]
#   POST   /images/banner              사진 업로드 → 서버 폴더에 저장 + banner_image에 파일명 저장 (홍보팀만)
#   GET    /images/banner              banner_image에 저장된 이미지 목록 조회
#   GET    /images/banner/files/{name} 저장된 이미지 파일 보기
#   DELETE /images/banner/{b_seq}      배너 이미지 삭제 (홍보팀만, 현재 노출 중이면 삭제 불가)
#
# [사용 테이블]
#   banner_image : b_seq(PK), b_image(파일명)
#   choice       : 삭제할 때만 사용 (이 이미지를 가리키는 선택 이력 정리)
#   headquarter  : 홍보팀 재직자 확인
import re

from fastapi import APIRouter, File, Form, Path as ApiPath, Query, UploadFile
from fastapi.responses import FileResponse
from uuid import uuid4

from .images import (
    API_RESPONSES, BANNER_DEPARTMENT, FILENAME_PATTERN, MAX_BYTES, UPLOAD_ROOT,
    check_staff, database, expire_choices, fail, image_url, now, validate_image,
)

router = APIRouter(prefix="/images/banner", tags=["배너 이미지 등록"], responses=API_RESPONSES)


@router.post("", status_code=201, summary="배너 이미지 등록",
             description=f"{BANNER_DEPARTMENT} 재직자가 사진을 업로드하면 서버 폴더에 저장하고 banner_image에 파일명을 저장합니다.")
def insert_banner_image(
    file: UploadFile = File(..., description="10MB·25MP 이하 JPEG·PNG·WebP"),
    h_id: str = Form(..., min_length=1, max_length=50, description="등록하는 직원 아이디(홍보팀)"),
):
    saved = None  # 저장한 파일 경로. DB 저장이 실패하면 이 파일을 지워 고아 파일이 남지 않게 합니다.
    try:
        # 1) 용량 검사: 제한보다 1바이트만 더 읽어 보고, 비었거나 넘으면 거절합니다.
        content = file.file.read(MAX_BYTES + 1)
        if not content or len(content) > MAX_BYTES:
            fail("BANNER_SIZE_INVALID", "사진은 0바이트 초과, 10MB 이하로 첨부해 주세요.")

        # 2) 형식 검사: 파일명이나 Content-Type이 아니라 실제 이미지 내용으로 JPEG/PNG/WebP인지 확인합니다.
        extension, _ = validate_image(content)

        with database(write=True) as cursor:
            # 3) 권한 검사: 홍보팀 재직자만 등록할 수 있습니다.
            check_staff(cursor, h_id)

            # 4) 파일 저장: 원본 파일명은 쓰지 않고 uuid로 새 이름을 만들어 중복·경로 조작을 막습니다.
            filename = uuid4().hex + extension
            UPLOAD_ROOT.mkdir(parents=True, exist_ok=True)
            saved = UPLOAD_ROOT / filename
            with saved.open("xb") as output:  # "xb": 같은 이름이 이미 있으면 덮어쓰지 않고 오류
                output.write(content)

            # 5) DB 저장: banner_image에는 파일명만 넣습니다. b_seq는 자동증가라 직접 넣지 않습니다.
            cursor.execute("INSERT INTO banner_image (b_image) VALUES (%s)", (filename,))
            b_seq = cursor.lastrowid

        return {"b_seq": b_seq, "b_image": filename, "image_url": image_url(filename)}
    except Exception:
        # 어느 단계에서든 실패하면 이미 저장한 파일을 지웁니다. (DB는 database()가 롤백)
        if saved is not None:
            saved.unlink(missing_ok=True)
        raise
    finally:
        file.file.close()


@router.get("", summary="배너 이미지 목록 조회",
            description="banner_image에 저장된 이미지를 최신순으로 반환합니다. is_chosen은 지금 배너로 노출 중인지 여부입니다.")
def list_banner_images():
    with database(write=True) as cursor:
        # 종료일이 지난 선택은 먼저 c_boolean=0으로 정리해, is_chosen이 실제 노출 상태와 맞게 합니다.
        expire_choices(cursor)
        # 오늘이 시작일~종료일 안에 있고 c_boolean=1인 선택이 하나라도 있으면 노출 중(is_chosen=1)입니다.
        cursor.execute(
            "SELECT b.b_seq, b.b_image, "
            "EXISTS(SELECT 1 FROM choice c WHERE c.b_seq=b.b_seq AND c.c_boolean=1 "
            "       AND c.c_start<=%s AND c.c_end>=%s) AS is_chosen "
            "FROM banner_image b ORDER BY b.b_seq DESC",
            (now().date(), now().date()),
        )
        rows = cursor.fetchall()
    for row in rows:
        row["is_chosen"] = bool(row["is_chosen"])
        row["image_url"] = image_url(row["b_image"])
    return {"results": rows}


@router.get("/files/{b_image}", summary="배너 이미지 파일 보기")
def banner_file(b_image: str = ApiPath(..., max_length=255, description="저장된 이미지 파일명")):
    # 정해진 파일명 형식만 허용해 '../' 같은 경로 조작을 막습니다.
    if re.fullmatch(FILENAME_PATTERN, b_image) is None:
        fail("BANNER_NOT_FOUND", "이미지 파일명을 확인해 주세요.", 404)
    path = (UPLOAD_ROOT / b_image).resolve()
    # 해석한 경로가 업로드 폴더 바로 아래의 실제 파일인지 한 번 더 확인합니다.
    if path.parent != UPLOAD_ROOT or not path.is_file():
        fail("BANNER_NOT_FOUND", "이미지 파일이 없습니다.", 404)
    return FileResponse(path, headers={"X-Content-Type-Options": "nosniff"})


@router.delete("/{b_seq}", summary="배너 이미지 삭제",
               description="현재 배너로 노출 중인 이미지는 삭제할 수 없습니다. 노출 중이 아니면 선택 이력(choice)과 파일까지 함께 삭제합니다.")
def delete_banner_image(
    b_seq: int = ApiPath(..., ge=1, description="삭제할 배너 이미지 번호"),
    h_id: str = Query(..., min_length=1, max_length=50, description="삭제하는 직원 아이디(홍보팀)"),
):
    with database(write=True) as cursor:
        check_staff(cursor, h_id)

        # 1) 삭제 대상 확인
        cursor.execute("SELECT b_image FROM banner_image WHERE b_seq=%s", (b_seq,))
        banner = cursor.fetchone()
        if banner is None:
            fail("BANNER_NOT_FOUND", "배너 이미지를 찾을 수 없습니다.", 404)

        # 2) 노출 중인지 확인: 종료일이 지난 선택을 먼저 정리한 뒤, 아직 선택 상태인 행이 있으면 삭제를 막습니다.
        expire_choices(cursor)
        cursor.execute("SELECT 1 FROM choice WHERE b_seq=%s AND c_boolean=1 LIMIT 1", (b_seq,))
        if cursor.fetchone() is not None:
            fail("BANNER_IN_USE", "현재 배너로 선택된 이미지입니다. 선택을 해제한 뒤 삭제해 주세요.", 409)

        # 3) choice.b_seq가 banner_image를 참조(FK)하므로, 지난 선택 이력을 먼저 지워야 이미지를 삭제할 수 있습니다.
        cursor.execute("DELETE FROM choice WHERE b_seq=%s", (b_seq,))
        cursor.execute("DELETE FROM banner_image WHERE b_seq=%s", (b_seq,))

    # 4) DB 삭제가 커밋된 뒤에 파일을 지웁니다. (DB가 실패했는데 파일만 없어지는 일을 막기 위해)
    (UPLOAD_ROOT / banner["b_image"]).unlink(missing_ok=True)
    return {"b_seq": b_seq, "deleted": True}
