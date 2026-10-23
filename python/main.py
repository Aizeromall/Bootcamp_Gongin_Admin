from fastapi import FastAPI

from FastAPI.management.management import router as management_router
from FastAPI.inquiry.inquiry import router as inquiry_router

app = FastAPI(title="공In중개사 관리자 API")

app.include_router(management_router) # 매니저 및 회원관리 백엔드
app.include_router(inquiry_router, prefix="/inquiry", tags=["inquiry"]) # 문의 백엔드