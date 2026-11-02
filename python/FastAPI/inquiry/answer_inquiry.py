## 문의 답변 및 관리
## 최초작업일 2026-10-23 김병재

from fastapi import APIRouter, Form

from database import connect

router = APIRouter()

# 답변은 해당 문의 행(원글 또는 추가 문의)의 inquiry_detail, i_answer_date, h_id에 저장
# i_state: '0' = 답변 대기, '1' = 답변 완료
# h_id: 답변 작성자(본사 직원 ID)
@router.post(
    "",
    summary="문의 답변 등록",
    description="본사 직원이 문의에 답변을 등록하고 답변 완료 상태로 바꿉니다. 이미 답변된 문의에는 다시 답변할 수 없습니다. 처리 실패는 HTTP 200과 result가 Error인 응답으로 반환됩니다.",
)
async def answer_inquiry(
    i_seq: int = Form(..., description="답변할 문의 번호"),
    h_id: str = Form(..., description="답변 작성 본사 직원 아이디"),
    inquiry_detail: str = Form(..., description="답변 내용"),
):
    conn = None

    try:
        conn = connect()
        curs = conn.cursor()

        # 문의 존재 여부 및 이미 답변된 문의인지 확인
        curs.execute("SELECT i_state FROM inquiry WHERE i_seq = %s", (i_seq,))
        origin = curs.fetchone()
        if origin is None:
            return {"result": "Error", "message": "inquiry not found"}
        if origin[0] == '1':
            return {"result": "Error", "message": "already answered"}

        # 답변 작성자(h_id)가 본사 직원 테이블에 있는지 확인
        curs.execute("SELECT 1 FROM headquarter WHERE h_id = %s", (h_id,))
        if curs.fetchone() is None:
            return {"result": "Error", "message": "headquarter not found"}

        # 답변 내용, 답변일, 답변자 저장 후 답변 완료 처리
        curs.execute(
            """
            UPDATE inquiry
            SET inquiry_detail = %s, i_answer_date = NOW(), h_id = %s, i_state = '1'
            WHERE i_seq = %s
            """,
            (inquiry_detail.strip(), h_id, i_seq),
        )

        conn.commit()
        return {"result": "OK", "i_seq": i_seq}
    except Exception as e:
        if conn is not None:
            conn.rollback()
        print("Error:", e)
        return {'result': 'Error'}
    finally:
        if conn is not None:
            conn.close()
