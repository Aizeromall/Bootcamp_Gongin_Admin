# 작업자 : 양태건
# 수정일 : 2026-10-26
# [추가 시작] 실제 MySQL에서 HTTP 흐름을 검증하고 모든 테스트 데이터를 롤백합니다.
# 실행: /opt/anaconda3/bin/python python/tests/integration_match_flow.py
import json
from copy import deepcopy
import sys
import uuid
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import main
import pymysql
from fastapi.testclient import TestClient
from database import connect
from FastAPI.match import match_operations as operations, manager_session as sessions


class TransactionProxy:
    def __init__(self, conn):
        self.conn = conn

    def cursor(self, *args, **kwargs):
        return self.conn.cursor(*args, **kwargs)

    def commit(self):
        pass  # 테스트 데이터는 마지막에 실제 연결에서 모두 롤백합니다.

    def rollback(self):
        pass

    def close(self):
        pass


def run():
    conn = connect()
    tag = uuid.uuid4().hex[:12]
    proxy = TransactionProxy(conn)
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute("SELECT h_id,m_id FROM assign LIMIT 1")
            assigned = cursor.fetchone()
            assert assigned, "검증용 기존 배정 정보가 필요합니다."
            cursor.execute("SELECT * FROM ground LIMIT 1")
            ground = cursor.fetchone()
            assert ground, "구장이 필요합니다."
            ground["g_code"] = 1900000000 + int(tag[:5], 16)
            ground["g_name"] = "자동 검증 구장"
            columns = ",".join(f"`{key}`" for key in ground)
            cursor.execute(
                f"INSERT INTO ground ({columns}) VALUES ({','.join(['%s']*len(ground))})",
                tuple(ground.values()),
            )
            cursor.execute(
                "INSERT INTO assign (h_id,m_id,g_code,a_day,a_time) VALUES (%s,%s,%s,%s,%s)",
                (
                    assigned["h_id"],
                    assigned["m_id"],
                    ground["g_code"],
                    "월",
                    "18:00~22:00",
                ),
            )
            ids = []
            for i in (1, 2):
                customer = f"flow_{tag}_{i}_01"
                cursor.execute(
                    "INSERT INTO customer (c_id_seq,c_pw,c_name,c_prefer_stock) VALUES (%s,%s,%s,%s)",
                    (customer, "not-a-login-password", f"검증 선수{i}", "1"),
                )
                cursor.execute(
                    "INSERT INTO reservation (c_id_seq,g_code,r_date,rs_time,re_time,r_check) VALUES (%s,%s,%s,%s,%s,%s)",
                    (
                        customer,
                        ground["g_code"],
                        "2026-10-26",
                        "19:00:00",
                        "21:00:00",
                        0,
                    ),
                )
                ids.append(cursor.lastrowid)
        with patch.object(operations, "connect", return_value=proxy), patch.object(
            sessions, "connect", return_value=proxy
        ):
            token = sessions.issue_manager_session(assigned["m_id"])
            client = TestClient(main.app)
            headers = {"Authorization": f"Bearer {token}"}
            assert client.get("/match/operations").status_code == 401
            assert sessions.verify_manager_token(token) == assigned["m_id"]
            path = f"/match/operations/{ids[0]}"
            result = client.get(path, headers=headers)
            assert result.status_code == 200, result.text
            data = result.json()

            def command(action, **values):
                nonlocal data
                response = client.post(
                    path,
                    headers=headers,
                    json={"action": action, "version": data["version"], **values},
                )
                assert response.status_code == 200, (action, response.text)
                data = response.json()

            for r_seq in ids:
                command("attendance", r_seq=r_seq, attendance=True)
            command("teams", assignments={str(ids[0]): "A", str(ids[1]): "B"})
            command("start")
            command("event", r_seq=ids[0], kind="goal")
            assert data["scores"] == {"A": 1, "B": 0}
            command("undo")
            assert data["scores"] == {"A": 0, "B": 0}
            command("event", r_seq=ids[0], kind="goal")
            command("event", r_seq=ids[1], kind="assist")
            command(
                "injury",
                r_seq=ids[0],
                body_parts=["발목·발"],
                severity="mild",
                measures=["아이싱"],
                description="통합 검증 🩹",
                occurred_seconds=0,
            )
            assert (
                len(client.get(path, headers=headers).json()["state"]["injuries"]) == 1
            )
            # 작업자 : 양태건
            # 수정일 : 2026-10-26
            # 부상은 결과 등록 전에 DB에 저장되고 재시작 후에도 회원별로 복원됩니다.
            command(
                "injury",
                r_seq=ids[0],
                body_parts=["무릎"],
                severity="moderate",
                measures=["병원 이송"],
                description="추가 부상",
                occurred_seconds=0,
            )
            with conn.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute(
                    "SELECT c_id_seq,c_r_r_injury FROM c_result_record WHERE c_r_r_code=%s ORDER BY c_r_r_seq",
                    (data["match_code"],),
                )
                injuries = cursor.fetchall()
                assert len(json.loads(injuries[0]["c_r_r_injury"])) == 2
                assert (
                    json.loads(injuries[0]["c_r_r_injury"])[0]["description"]
                    == "통합 검증 🩹"
                )
                assert injuries[1]["c_r_r_injury"] == ""
            snapshot = deepcopy(operations._MATCHES)
            operations._MATCHES.clear()
            restarted = client.get(path, headers=headers).json()
            assert (
                restarted["status"] == "attendance"
                and len(restarted["state"]["injuries"]) == 2
            )
            operations._MATCHES.clear()
            operations._MATCHES.update(snapshot)
            command("end")
            command("publish")
            command("publish")
            assert data["status"] == "completed"
            operations._MATCHES.clear()  # 서버 재시작 상황: 최종 결과를 기존 DB에서 다시 읽습니다.
            recovered = client.get(path, headers=headers).json()
            assert recovered["status"] == "completed" and recovered["scores"] == {
                "A": 1,
                "B": 0,
            }
            assert recovered["stats"][str(ids[0])]["goal"] == 1
            assert len(recovered["state"]["injuries"]) == 2
            listed = client.get("/match/operations", headers=headers).json()["results"]
            assert any(
                row["match_code"] == data["match_code"] and row["status"] == "completed"
                for row in listed
            )
            with conn.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute(
                    "SELECT c_r_r_score,c_r_r_statcode FROM c_result_record WHERE c_r_r_code=%s",
                    (data["match_code"],),
                )
                saved = cursor.fetchall()
                assert len(saved) == 2 and all(p["c_r_r_score"] == "1:0" for p in saved)
                assert {p["c_r_r_statcode"] for p in saved} == {
                    "G:1,A:0,S:0,Y:0,R:0",
                    "G:0,A:1,S:0,Y:0,R:0",
                }
        print(
            "HTTP·실제 DB 검증 통과: 인증, 출석, 팀, 골·도움·취소, 부상, 결과 일괄 저장, 중복 등록 방지, 지난 매치"
        )
    finally:
        operations._MATCHES.clear()
        conn.rollback()
        conn.close()
        print("테스트 데이터 전체 롤백 완료")


if __name__ == "__main__":
    run()
# [추가 끝]
