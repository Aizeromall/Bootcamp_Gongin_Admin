# 작업자 : 김병재
# 최초 작업 일 : 2026-10-27

"""관리자 제재·이의신청 API router를 하나로 묶어 main.py에 전달합니다."""

from fastapi import APIRouter

from .detail_appeal import router as detail_router
from .list_appeal import router as list_router
from .list_sanction import router as sanction_router
from .review_appeal import router as review_router

# main.py의 prefix="/appeal"과 결합해 /appeal/list, /appeal/sanction, /appeal/detail, /appeal/review 경로를 생성합니다.
router = APIRouter()
router.include_router(list_router, prefix="/list", tags=["Appeal List"])  # 이의신청 목록
router.include_router(sanction_router, prefix="/sanction", tags=["Appeal Sanction List"])  # 제재 목록 탭
router.include_router(detail_router, prefix="/detail", tags=["Appeal Detail"])  # 이의신청 상세
router.include_router(review_router, prefix="/review", tags=["Appeal Review"])  # 재심의 시작

# 최종 수정 일 : 2026-10-27
