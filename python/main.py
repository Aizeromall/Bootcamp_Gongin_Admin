import os
from pathlib import Path

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# 프로젝트 루트 .env를 먼저 읽어, 아래 라우터가 동일한 DB 설정을 사용하게 합니다.
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

from FastAPI.management.management import router as management_router
from FastAPI.inquiry.inquiry import router as inquiry_router

app = FastAPI(title="공In중개사 관리자 API")

app.include_router(management_router) # 매니저 및 회원관리 백엔드
app.include_router(inquiry_router, prefix="/inquiry", tags=["inquiry"]) # 문의 백엔드
from FastAPI.login.admin_login import router as admin_login_router # 관리자 로그인
from FastAPI.login.manager_login import router as manager_login_router # 매니저 로그인
from FastAPI.match.match_manage import router as match_manage_router # 경기 관리 조회

app = FastAPI(title="공In중개사 관리자 API")

# Flutter 웹 클라이언트의 API 요청을 허용합니다.
api_host = os.getenv("API_HOST", "0.0.0.0")
cors_origins = ["http://localhost:5000", "http://localhost:8081"]
if api_host not in {"0.0.0.0", "127.0.0.1", "localhost"}:
    cors_origins.extend([f"http://{api_host}:5000", f"http://{api_host}:8081"])

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)

# 기존 관리·관리자·매니저 기능 라우터를 그대로 등록합니다.
app.include_router(management_router)
app.include_router(admin_login_router)
app.include_router(manager_login_router)
app.include_router(match_manage_router)


@app.get("/health", tags=["Health"])
def health() -> dict[str, str]:
    """서버 상태를 반환합니다."""

    return {"status": "ok", "service": "gongin-admin"}


if __name__ == "__main__":
    try:
        api_port = int(os.getenv("API_PORT", "8000"))
    except ValueError as error:
        raise RuntimeError("API_PORT 설정이 올바르지 않습니다.") from error

    # .env의 API_HOST/API_PORT로 FastAPI 서버를 실행합니다.
    uvicorn.run(app, host=api_host, port=api_port)
