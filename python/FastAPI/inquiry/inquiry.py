## 문의 답변 및 관리
## 최초작업일 2026-10-23 김병재

from fastapi import APIRouter

from .answer_inquiry import router as answer_router
from .detail_inquiry import router as detail_router
from .list_inquiry import router as list_router

# 문의 관련 라우터를 하나로 묶어 main.py로 전달
router = APIRouter()
router.include_router(answer_router, prefix='/answer')   # 답변 등록
router.include_router(list_router, prefix='/list')       # 목록 조회
router.include_router(detail_router, prefix='/detail')   # 상세 조회
