-- 작업자 : 양태건
-- 수정일 : 2026-10-26
-- [수정 시작] 사용자가 추가한 기존 컬럼만 확장합니다. 새 테이블은 생성하지 않습니다.
-- 부위·정도·조치·내용·발생 시각을 포함한 JSON 목록을 50자 제한 없이 보관합니다.
ALTER TABLE c_result_record MODIFY COLUMN c_r_r_injury TEXT NOT NULL;
-- [수정 끝]
