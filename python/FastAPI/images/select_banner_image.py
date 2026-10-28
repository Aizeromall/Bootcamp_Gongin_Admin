# 배너 이미지 선택 라우터 (banner_image에 저장된 이미지를 골라 배너로 띄우는 기능)
# 작업 일 : 2026-10-28
#
# [기능]
#   POST  /images/banner-select                  이미지를 골라 노출 기간과 함께 choice에 저장 (홍보팀만)
#   GET   /images/banner-select/current          지금 화면에 띄울 배너 목록 (회원 앱 배너용)
#   GET   /images/banner-select                  선택 내역(choice) 전체 조회
#   PATCH /images/banner-select/{c_image_seq}/cancel  선택 해제 (홍보팀만)
#
# [사용 테이블]
#   choice       : c_image_seq(PK), h_id(선택한 직원), b_seq(선택한 이미지), c_boolean(선택 여부), c_start, c_end
#   banner_image : b_seq, b_image (선택할 이미지 원본)
#   headquarter  : 홍보팀 재직자 확인
#
# [노출 규칙]
#   c_boolean=1(선택됨)이고, 오늘이 c_start ~ c_end 사이인 이미지만 배너로 보여줍니다.
#   종료일(c_end)이 지나면 목록을 조회하는 시점에 c_boolean이 0(False)으로 자동 변경됩니다.
from datetime import date

from fastapi import APIRouter, Path as ApiPath, Query
from pydantic import BaseModel, Field

from .images import (
    API_RESPONSES, BANNER_DEPARTMENT, check_staff, database, expire_choices, fail, image_url, now,
)

router = APIRouter(prefix="/images/banner-select", tags=["배너 이미지 선택"], responses=API_RESPONSES)


class BannerChoice(BaseModel):
    """배너 선택 요청 본문."""
    h_id: str = Field(..., min_length=1, max_length=50, description="선택하는 직원 아이디(홍보팀)")
    b_seq: int = Field(..., ge=1, description="배너로 띄울 banner_image 번호")
    c_start: date = Field(..., description="노출 시작일 (YYYY-MM-DD)")
    c_end: date = Field(..., description="노출 종료일 (YYYY-MM-DD, 이 날까지 노출)")


@router.post("", status_code=201, summary="배너 이미지 선택",
             description=f"{BANNER_DEPARTMENT} 재직자가 banner_image 중 하나를 골라 노출 기간과 함께 choice에 저장합니다. 선택 여부(c_boolean)는 1로 저장됩니다.")
def choose_banner_image(body: BannerChoice):
    # 1) 기간 검사: 종료일이 시작일보다 빠르거나, 이미 지난 기간이면 의미가 없으므로 거절합니다.
    today = now().date()
    if body.c_end < body.c_start:
        fail("BANNER_PERIOD_INVALID", "종료일은 시작일보다 같거나 늦어야 합니다.")
    if body.c_end < today:
        fail("BANNER_PERIOD_INVALID", "종료일이 이미 지났습니다. 오늘 이후 날짜를 입력해 주세요.")

    with database(write=True) as cursor:
        # 2) 권한 검사: 홍보팀 재직자만 선택할 수 있고, 이 직원 아이디가 choice.h_id에 저장됩니다.
        h_id = check_staff(cursor, body.h_id)

        # 3) 선택할 이미지가 banner_image에 실제로 있는지 확인합니다.
        cursor.execute("SELECT b_image FROM banner_image WHERE b_seq=%s", (body.b_seq,))
        banner = cursor.fetchone()
        if banner is None:
            fail("BANNER_NOT_FOUND", "배너 이미지를 찾을 수 없습니다.", 404)

        # 4) 중복 검사: 같은 이미지가 같은 기간에 이미 선택돼 있으면 중복 저장하지 않습니다.
        #    (두 기간이 겹치려면 '기존 시작일 <= 새 종료일' 이면서 '기존 종료일 >= 새 시작일' 이어야 합니다.)
        expire_choices(cursor)
        cursor.execute(
            "SELECT c_image_seq FROM choice WHERE b_seq=%s AND c_boolean=1 AND c_start<=%s AND c_end>=%s LIMIT 1",
            (body.b_seq, body.c_end, body.c_start),
        )
        if cursor.fetchone() is not None:
            fail("BANNER_DUPLICATED", "이 이미지는 해당 기간에 이미 선택되어 있습니다.", 409)

        # 5) 저장: c_image_seq는 자동증가라 넣지 않고, 선택 여부 c_boolean은 1(True)로 저장합니다.
        cursor.execute(
            "INSERT INTO choice (h_id, b_seq, c_boolean, c_start, c_end) VALUES (%s,%s,1,%s,%s)",
            (h_id, body.b_seq, body.c_start, body.c_end),
        )
        c_image_seq = cursor.lastrowid

    return {
        "c_image_seq": c_image_seq, "h_id": h_id, "b_seq": body.b_seq,
        "c_boolean": True, "c_start": body.c_start, "c_end": body.c_end,
        "image_url": image_url(banner["b_image"]),
    }


@router.get("/current", summary="현재 노출할 배너 조회",
            description="c_boolean=1이고 오늘이 시작일~종료일 사이인 배너를 시작일 순으로 반환합니다. 종료일이 지난 선택은 이 조회 때 자동으로 False로 바뀝니다.")
def current_banners():
    with database(write=True) as cursor:
        # 종료일이 지난 선택을 먼저 c_boolean=0으로 바꿉니다. (자동 False)
        expire_choices(cursor)
        # 선택 상태이고 오늘이 기간 안인 것만 이미지 정보와 함께 가져옵니다.
        cursor.execute(
            "SELECT c.c_image_seq, c.b_seq, b.b_image, c.c_start, c.c_end "
            "FROM choice c JOIN banner_image b ON b.b_seq=c.b_seq "
            "WHERE c.c_boolean=1 AND c.c_start<=%s AND c.c_end>=%s "
            "ORDER BY c.c_start, c.c_image_seq",
            (now().date(), now().date()),
        )
        rows = cursor.fetchall()
    for row in rows:
        row["image_url"] = image_url(row["b_image"])
    return {"results": rows}


@router.get("", summary="배너 선택 내역 조회",
            description="choice에 저장된 선택 내역을 최신순으로 반환합니다. is_active는 지금 실제로 노출 중인지 여부입니다.")
def list_choices():
    with database(write=True) as cursor:
        expire_choices(cursor)
        # b_seq는 NULL 허용 컬럼이라 이미지 연결이 없는 행도 보이도록 LEFT JOIN을 씁니다.
        cursor.execute(
            "SELECT c.c_image_seq, c.h_id, c.b_seq, b.b_image, c.c_boolean, c.c_start, c.c_end "
            "FROM choice c LEFT JOIN banner_image b ON b.b_seq=c.b_seq "
            "ORDER BY c.c_image_seq DESC"
        )
        rows = cursor.fetchall()
    today = now().date()
    for row in rows:
        row["c_boolean"] = bool(row["c_boolean"])
        # 선택 상태이면서 오늘이 기간 안이어야 실제 노출 중입니다.
        row["is_active"] = bool(
            row["c_boolean"] and row["c_start"] and row["c_end"] and row["c_start"] <= today <= row["c_end"]
        )
        row["image_url"] = image_url(row["b_image"]) if row["b_image"] else None
    return {"results": rows}


@router.patch("/{c_image_seq}/cancel", summary="배너 선택 해제",
              description="선택 내역의 c_boolean을 0(False)으로 바꿔 배너에서 내립니다. 선택 이력(행)은 남깁니다.")
def cancel_choice(
    c_image_seq: int = ApiPath(..., ge=1, description="해제할 선택 번호(choice.c_image_seq)"),
    h_id: str = Query(..., min_length=1, max_length=50, description="해제하는 직원 아이디(홍보팀)"),
):
    with database(write=True) as cursor:
        check_staff(cursor, h_id)
        cursor.execute("SELECT c_boolean FROM choice WHERE c_image_seq=%s", (c_image_seq,))
        choice = cursor.fetchone()
        if choice is None:
            fail("CHOICE_NOT_FOUND", "선택 내역을 찾을 수 없습니다.", 404)
        if not choice["c_boolean"]:
            fail("CHOICE_ALREADY_CANCELED", "이미 해제되었거나 기간이 끝난 선택입니다.", 409)
        # 행을 지우지 않고 c_boolean만 0으로 바꿔 누가 언제 선택했는지 이력은 남깁니다.
        cursor.execute("UPDATE choice SET c_boolean=0 WHERE c_image_seq=%s", (c_image_seq,))
    return {"c_image_seq": c_image_seq, "c_boolean": False}
