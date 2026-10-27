# 작업자 : 최현준
# 작업 일 : 2026-10-27
"""신규 구장 품의 사진 업로드·조회. 승인 시 shoot에 구장과 연결합니다."""
import io
import hashlib
import os
from pathlib import Path
from uuid import uuid4
import warnings

from PIL import Image, UnidentifiedImageError
from fastapi import APIRouter, File, Form, Path as ApiPath, Query, UploadFile
from fastapi.responses import FileResponse
from .groundapproval import API_RESPONSES, database, fail, now

router = APIRouter(prefix="/approval/ground-photos", tags=["구장 사진 첨부"], responses=API_RESPONSES)
UPLOAD_ROOT = Path(os.getenv("GROUND_UPLOAD_DIR", Path(__file__).resolve().parents[3] / "uploads" / "grounds")).resolve()
MAX_BYTES = 10 * 1024 * 1024
FORMATS = {"JPEG": (".jpg", "image/jpeg"), "PNG": (".png", "image/png"), "WEBP": (".webp", "image/webp")}


def validate_image(content):
    # 파일명/Content-Type만 믿지 않고 이미지 디코더로 실제 형식과 크기를 검사합니다.
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(content)) as image:
                fmt = image.format
                if fmt not in FORMATS or image.width * image.height > 25_000_000:
                    fail("PHOTO_FORMAT_INVALID", "25MP 이하 JPEG/PNG/WebP 이미지를 첨부해 주세요.")
                image.verify()
        return FORMATS[fmt]
    except (UnidentifiedImageError, OSError, Image.DecompressionBombWarning, Image.DecompressionBombError):
        fail("PHOTO_INVALID", "올바른 이미지 파일을 첨부해 주세요.")


def file_prefix(h_id):
    # 파일명을 직원별로 구분하되 별도 임시 테이블이나 메타데이터 컬럼은 만들지 않습니다.
    return hashlib.sha256(h_id.encode("utf-8")).hexdigest()[:16] + "_"


@router.post("/draft", status_code=201, summary="품의 첨부 사진 업로드",
             description="파일만 임시 저장합니다. 반환된 s_image를 품의 내용에 첨부하고 최종 승인 후 기존 shoot 관계에 저장합니다.")
def upload_draft_photo(
    file: UploadFile = File(..., description="10MB·25MP 이하 JPEG·PNG·WebP"),
    h_id: str = Form(..., min_length=1, max_length=50, description="첨부 직원 아이디"),
):
    saved = None
    try:
        content = file.file.read(MAX_BYTES + 1)
        if not content or len(content) > MAX_BYTES:
            fail("PHOTO_SIZE_INVALID", "사진은 0바이트 초과, 10MB 이하로 첨부해 주세요.")
        extension, _ = validate_image(content)
        with database() as cursor:
            cursor.execute("SELECT h_id FROM headquarter WHERE h_id=%s AND TRIM(h_department)='영업팀' AND (h_resignationdate IS NULL OR h_resignationdate>CURRENT_DATE)", (h_id.strip(),))
            employee = cursor.fetchone()
            if employee is None:
                fail("DEPARTMENT_FORBIDDEN", "영업팀 재직자만 사진을 첨부합니다.", 403)
        filename = file_prefix(employee["h_id"]) + uuid4().hex + extension
        UPLOAD_ROOT.mkdir(parents=True, exist_ok=True)
        saved = UPLOAD_ROOT / filename
        with saved.open("xb") as output:
            output.write(content)
        return {"s_image": filename}
    except Exception:
        if saved is not None:
            saved.unlink(missing_ok=True)
        raise
    finally:
        file.file.close()


@router.get("", summary="기존 구장 사진 조회", description="기존 shoot 테이블만 조회합니다.")
def photos(g_code: int | None = Query(None, ge=1, description="구장 번호")):
    with database() as cursor:
        sql = "SELECT shoot_seq,h_id,g_code,s_date,s_image FROM shoot"
        params = []
        if g_code is not None:
            sql += " WHERE g_code=%s"
            params.append(g_code)
        cursor.execute(sql + " ORDER BY shoot_seq DESC", params)
        return {"results": cursor.fetchall()}


@router.get("/files/{s_image}", summary="첨부 사진 파일 보기")
def photo_file(s_image: str = ApiPath(..., max_length=255, description="업로드한 사진 파일명")):
    import re
    if re.fullmatch(r"[0-9a-f]{16}_[0-9a-f]{32}[.](jpg|png|webp)", s_image) is None:
        fail("PHOTO_NOT_FOUND", "사진 파일명을 확인해 주세요.", 404)
    path = (UPLOAD_ROOT / s_image).resolve()
    if path.parent != UPLOAD_ROOT or not path.is_file():
        fail("PHOTO_NOT_FOUND", "사진 파일이 없습니다.", 404)
    return FileResponse(path, headers={"X-Content-Type-Options": "nosniff"})

# 최종 수정일 : 2026-10-27
