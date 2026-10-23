## 문의 답변 및 관리
## 최초작업일 2026-10-23 김병재

from fastapi import APIRouter
import pymysql

from database import connect

router = APIRouter()

# i_option 매핑 (i_option이 NULL이면 문의 내용 앞부분을 제목으로 사용)
# i_option 컬럼이 varchar라 키를 문자열로 관리
INQUIRY_OPTION = {
    '1': '매니저 신고 문의',
    '2': '구장 예약 문의',
    '3': '환불 문의',
    '4': '기타 문의',
}

# 미답변 여부 조건: i_state가 NULL이거나 '1'(답변 완료)이 아니면 미답변
UNANSWERED = "COALESCE(q.i_state, '0') <> '1'"

# 원글 조회 SQL (level 0). 한 행에 문의(post)와 답변(inquiry_detail, i_answer_date)이 함께 저장됨
# 문의자 이름은 customer, 답변자 이름은 headquarter에서 가져옴
SELECT_INQUIRY = """
    SELECT q.i_seq, q.c_id_seq, c.c_name, q.i_option, q.post, q.i_date,
           q.inquiry_detail, q.i_answer_date, q.i_state, q.h_id, h.h_name
    FROM inquiry q
    LEFT JOIN customer c ON c.c_id_seq = q.c_id_seq
    LEFT JOIN headquarter h ON h.h_id = q.h_id
    WHERE q.level = 0
    """

# 정렬: 미답변 문의가 맨 위(오래된 문의부터), 그 아래 답변 완료 문의(최신순)
ORDER_BY_UNANSWERED_FIRST = f"""
    ORDER BY ({UNANSWERED}) DESC,
             CASE WHEN {UNANSWERED} THEN q.i_date END ASC,
             q.i_date DESC
    """


# 문의 제목 생성: 옵션이 있으면 옵션명, 없으면 문의 내용 앞 30자
def make_title(row):
    return INQUIRY_OPTION.get(row['i_option']) or (row['post'] or '')[:30]


# 원글에 추가 문의(level 1, i_comment_seq = 원글 i_seq)를 follow_ups로 붙임
def attach_follow_ups(curs, rows):
    for row in rows:
        row['title'] = make_title(row)
        row['follow_ups'] = []
    if not rows:
        return rows

    by_seq = {row['i_seq']: row for row in rows}
    curs.execute(
        """
        SELECT i_seq, i_comment_seq, level, post, i_date, inquiry_detail, i_answer_date, i_state, h_id
        FROM inquiry
        WHERE level = 1 AND i_comment_seq IN %s
        ORDER BY i_seq
        """,
        (tuple(by_seq),),
    )
    for child in curs.fetchall():
        by_seq[child['i_comment_seq']]['follow_ups'].append(child)
    return rows


# 문의 목록 조회
# i_state: '0' = 답변 대기, '1' = 답변 완료 (지정 시 원글 상태가 일치하는 것만)
@router.get("")
async def list_inquiry(i_state: str | None = None):

    conn = None

    try:
        conn = connect()
        curs = conn.cursor(pymysql.cursors.DictCursor)

        sql = SELECT_INQUIRY
        params = []
        if i_state is not None:
            sql += " AND q.i_state = %s"
            params.append(i_state)
        # 미답변 문의를 최상단에 두는 정렬
        sql += ORDER_BY_UNANSWERED_FIRST

        curs.execute(sql, params)
        rows = attach_follow_ups(curs, curs.fetchall())
        return {'results': rows}

    except Exception as e:
        print("Error:", e)
        return {'result': 'Error'}

    finally:
        if conn is not None:
            conn.close()
