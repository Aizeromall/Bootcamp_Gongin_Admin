# 구장 조회 라우터 연동 작업자 : 김병재
# 최종 수정 일 : 2026-10-26

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

from FastAPI.login.admin_login import router as admin_login_router # 관리자 로그인
from FastAPI.login.manager_login import router as manager_login_router # 매니저 로그인
from FastAPI.match.match_manage import router as match_manage_router # 경기 관리 조회
from FastAPI.match.attendance_check import router as attendance_check_router # 출석 체크 등록
from FastAPI.match.match_score import router as match_score_router # 경기 결과기록 등록
from FastAPI.match.ground_search import router as ground_search_router # 구장 조회
from FastAPI.match.match_cancel import router as match_cancel_router # 구장 취소 내역 조회
from FastAPI.match.match_manage_cancel import router as match_manage_cancel_router # 매니저 매칭 취소
from FastAPI.management.team_management import router as team_management_router # 팀 관리 조회
from FastAPI.match.team_match_search import router as team_match_search_router # 팀 대 팀 매칭 조회
from FastAPI.report.report import router as report_router # 신고 내역 조회·심의 시작
from FastAPI.approval.vacation import router as vacation_router
from FastAPI.approval.groundapproval import router as ground_approval_router
from FastAPI.approval.groundcontract import router as ground_contract_router
from FastAPI.approval.groundshoot import router as ground_photo_router
from FastAPI.announce.writeannounce import router as write_announce_router
from FastAPI.announce.adminannounce import router as admin_announce_router
from FastAPI.announce.mannagerannounce import router as manager_announce_router
from FastAPI.appeal.appeal import router as appeal_router # 제재·이의신청 조회·재심의 시작
from FastAPI.images.insert_banner_image import router as insert_banner_image_router # 배너 이미지 등록
from FastAPI.images.select_banner_image import router as select_banner_image_router # 배너 이미지 선택

# 작업자 : 양태건
# 수정일 : 2026-10-26
# [추가 시작] 인증된 매니저의 경기 진행 라우터
from FastAPI.match.match_operations import router as match_operations_router
# [추가 끝]

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
# 작업자 : 최현준 / 작업 일 : 2026-10-27 / 휴가·구장 품의 및 사진 첨부
app.include_router(vacation_router)
app.include_router(ground_approval_router)
app.include_router(ground_contract_router)
app.include_router(ground_photo_router)
app.include_router(write_announce_router) # 공지 작성 / 작업자 : 최현준 / 작업 일 : 2026-10-27
app.include_router(admin_announce_router) # 본사 공지 조회
app.include_router(manager_announce_router) # 매니저 공지 조회
app.include_router(inquiry_router, prefix="/inquiry", tags=["inquiry"])
# 작업자 : 양태건
# 수정일 : 2026-10-26
# [추가 시작]
app.include_router(match_operations_router)
# [추가 끝]
app.include_router(admin_login_router)
app.include_router(manager_login_router)
app.include_router(match_manage_router)
app.include_router(attendance_check_router)
app.include_router(match_score_router)
app.include_router(ground_search_router, prefix="/match", tags=["Ground Search"]) # 구장 조회
app.include_router(match_cancel_router) # 구장 취소 내역 조회
app.include_router(match_manage_cancel_router) # 매니저 매칭 취소
app.include_router(team_management_router, prefix="/management", tags=["Team Management"]) # 팀 관리 조회
app.include_router(team_match_search_router, prefix="/match", tags=["Team Match Search"]) # 팀 대 팀 매칭 조회
app.include_router(report_router, prefix="/report", tags=["Report"]) # 신고 내역 조회·심의 시작
app.include_router(appeal_router, prefix="/appeal", tags=["Appeal"]) # 제재·이의신청 조회·재심의 시작
app.include_router(insert_banner_image_router) # 배너 이미지 등록 (/images/banner)
app.include_router(select_banner_image_router) # 배너 이미지 선택 (/images/banner-select)


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
