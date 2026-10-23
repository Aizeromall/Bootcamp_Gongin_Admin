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
        charset = 'utf8',
        client_flag = pymysql.constants.CLIENT.FOUND_ROWS if found_rows else 0
    )