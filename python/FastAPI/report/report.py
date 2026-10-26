# 작업자 : 김병재
# 최초 작업 일 : 2026-10-26

"""관리자 신고 API router를 하나로 묶어 main.py에 전달합니다."""

from fastapi import APIRouter

from .detail_report import router as detail_router
from .list_report import router as list_router
from .review_report import router as review_router

# main.py의 prefix="/report"와 결합해 /report/list, /report/detail, /report/review 경로를 생성합니다.
router = APIRouter()
router.include_router(list_router, prefix="/list", tags=["Report List"])  # 신고 내역 목록
router.include_router(detail_router, prefix="/detail", tags=["Report Detail"])  # 신고 상세 + 피신고자 이력
router.include_router(review_router, prefix="/review", tags=["Report Review"])  # 심의 시작

# 최종 수정 일 : 2026-10-26
