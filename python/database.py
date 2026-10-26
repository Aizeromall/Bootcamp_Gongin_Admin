import os
from dotenv import load_dotenv
import pymysql

load_dotenv()

def connect(found_rows: bool = False):
    # found_rows=True: UPDATE 시 값이 그대로여도 매칭된 행 수를 rowcount로 반환
    return pymysql.connect(
        host = os.getenv('DB_HOST'),
        user = os.getenv('DB_USER'),
        password =os.getenv('DB_PASSWORD'),
        database = os.getenv('DB_NAME'),
        # 작업자 : 양태건
        # 수정일 : 2026-10-26
        # 부상 설명의 한글·이모지를 보존합니다.
        charset = 'utf8mb4',
        client_flag = pymysql.constants.CLIENT.FOUND_ROWS if found_rows else 0
    )