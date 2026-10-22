from fastapi import FastAPI

from FastAPI.management.management import router as management_router

app = FastAPI(title="공In중개사 관리자 API")

app.include_router(management_router)
