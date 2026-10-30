# 수정 일 : 2026-10-27 / 작업자 : 양태건
# 교육 개설·조회·이수 라우터만 집계합니다. 스키마 생성이나 자동 마이그레이션은 없습니다.
from fastapi import APIRouter
from .education_list import router as list_router
from .education_create import router as create_router
from .education_complete import router as complete_router

router = APIRouter(prefix="/education", tags=["Manager Education"])
router.include_router(list_router)
router.include_router(create_router)
router.include_router(complete_router)
# 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
