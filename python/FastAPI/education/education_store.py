# 수정 일 : 2026-10-27 / 작업자 : 양태건
# 새 테이블 없이 기존 training.t_detail의 JSON 메타데이터로 교육 과정을 묶습니다.
import json

EDUCATION_SELECT = """
 SELECT t.training_seq,t.h_id,t.m_id,t.t_detail,t.t_state,t.t_date,
        m.m_name,m.m_workplace
 FROM training t LEFT JOIN match_manager m ON m.m_id=t.m_id
"""


def course_metadata(row):
    try:
        value = json.loads(row["t_detail"] or "")
    except (ValueError, TypeError):
        value = None
    if (
        isinstance(value, dict)
        and value.get("_education") == 1
        and isinstance(value.get("course_id"), str)
    ):
        return value
    return dict(
        course_id=f"legacy_{row['training_seq']}",
        title="기존 교육 기록",
        description=row["t_detail"] or "",
        category=None,
        format=None,
        scheduled_at=None,
        duration_minutes=None,
        location=None,
        instructor=None,
    )


def group_courses(rows):
    groups = {}
    for row in rows:
        info = course_metadata(row)
        key = info["course_id"]
        if key not in groups:
            groups[key] = {
                **info,
                "course_id": key,
                "date": str(row["t_date"]) if row["t_date"] else None,
                "managers": [],
            }
        groups[key]["managers"].append(
            dict(
                training_seq=row["training_seq"],
                m_id=row["m_id"],
                name=row.get("m_name") or row["m_id"],
                workplace=row.get("m_workplace"),
                completed=None if row["t_state"] is None else bool(row["t_state"]),
            )
        )
    for item in groups.values():
        item["total"] = len(item["managers"])
        item["completed_count"] = sum(m["completed"] is True for m in item["managers"])
    return sorted(
        groups.values(),
        key=lambda c: (
            c.get("scheduled_at") or c.get("date") or "9999",
            c["course_id"],
        ),
    )


def load_courses(cursor):
    cursor.execute(EDUCATION_SELECT + " ORDER BY t.t_date,t.training_seq")
    return group_courses(cursor.fetchall())


# 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
