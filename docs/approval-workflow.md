# ERD 기준 품의·계약·휴가 처리
작업자 : 최현준 / 작업 일 : 2026-10-27

## 기준과 삭제한 구조

Miro에서 확인한 기존 관계와 실제 MySQL 테이블만 사용합니다.

- memorandum: m_code, m_content
- approval: a_seq, h_id, m_code, a_reason, a_state, a_step, a_date, a_signatures, a_price
- contract: c_seq, h_id, o_seq, m_code, c_date, c_record, c_treaty, c_rentalfee
- ground·owner·maintain·assign·shoot·h_vacation은 실제 존재하는 컬럼만 사용합니다.
- 별도 품의 ID, 유형·본문 보관용 추가 컬럼, 사진 임시 테이블, 계약 상태·만료일 컬럼, 배정 활성 컬럼을 만들지 않습니다.
- 컬럼을 임의 추가하던 미적용 마이그레이션 파일은 삭제했습니다. 실제 DB 구조·데이터는 변경하지 않았습니다.

## 파일별 역할

| 파일 | 역할 |
| --- | --- |
| groundapproval.py | 기존 양식 조회, 품의서 작성, 결재 관계 기록 추가, 조회, 구장 품의 입력 검사 |
| vacation.py | 대리인 후보 및 확정 휴가 조회 |
| vacationapproval.py | 휴가·대리 업무 중복 검사, 최종 승인 시 기존 휴가 관계 저장 |
| groundcontract.py | 매니저 일정 검사, 기존 계약 관계 조회 및 최종 계약·연장·해지 기록 |
| groundshoot.py | 첨부 파일 저장·읽기, 기존 shoot 관계 조회 |

SQL은 각 역할별 파일의 처리 함수에 작성합니다. 공통 SQL 모듈을 추가하지 않습니다.
main.py는 이 라우터와 기존 ground_search를 연결합니다.

## 작성 내용과 결재 관계

기존 양식은 memorandum의 m_content 문자열로 읽습니다.
제목에서 휴가·신규 계약·재계약(연장/갱신)·해지를 구분할 수 있어야 합니다.
JSON 문서인 경우에는 작성 내용의 '유형' 값을 읽습니다. 구분할 수 없으면 임의 판단하지 않고 오류를 반환합니다.

상신할 때 선택한 기존 양식을 덮어쓰지 않습니다.
새 품의서의 작성 내용을 기존 m_content(TEXT)에 저장하고 AUTO_INCREMENT m_code를 받습니다.
작성 내용에는 양식 원문·유형·작성자·결재선·구장 또는 휴가 신청 내용을 JSON 문자열로 담습니다.
이 항목들은 문서 본문 형식이지 DB에 추가한 속성·컬럼이 아닙니다.

approval은 같은 m_code로 관계 행을 누적합니다.

1. 상신: 작성자 h_id, a_step=0, a_state=심사중
2. 사원 확인: 실제 결재자 h_id, a_step=1
3. 팀장 확인: 실제 결재자 h_id, a_step=2
4. 임원 확인: 실제 결재자 h_id, a_step=3, a_state=승인완료

반려도 기존 기록을 덮어쓰지 않고 해당 단계의 반려 행을 추가합니다.
원결재자·실결재자·의견은 기존 a_signatures(VARCHAR(255))에 기록합니다.
처리일은 a_date에 저장합니다. 컬럼 길이를 넘기면 잘라내지 않고 오류를 반환합니다.

## API

- GET /approval/templates: 기존 양식 (결재 관계가 없는 품의서)
- GET /approval/approvers?m_code=양식번호: 담당 부서 결재자 후보
- POST /approval/requests: 양식으로 새 품의서 작성·상신
- GET /approval/requests?m_code=품의서번호: 결재 관계 행 조회
- GET /approval/requests/{m_code}: 품의서와 전체 결재 관계 이력
- POST /approval/requests/{m_code}/sign: 같은 품의서에 승인·반려 행 추가
- GET /approval/contracts 및 /{c_seq}: 기존 계약 관계 조회
- GET /approval/grounds/owners?keyword=검색어: 기존 소유주 검색
- GET /approval/grounds/managers: 매니저와 기존 assign 관계 조회
- GET /approval/vacation/deputies?h_id=신청자: 대리인 후보
- GET /approval/vacation: 기존 휴가 조회
- POST /approval/ground-photos/draft: multipart h_id, file 첨부
- GET /approval/ground-photos: 기존 shoot 관계 조회 (g_code 필터 선택)
- GET /approval/ground-photos/files/{s_image}: 첨부 파일 조회

상신 응답의 m_code가 새로 작성한 품의서 번호입니다.
그 번호로 상세 조회·결재를 요청합니다. 기존 양식 번호와 혼동하지 않습니다.
별도 approval_id를 요구하지 않습니다. 실제 관계 PK인 a_seq는 조회 결과에만 포함됩니다.

조회에는 인증·부서 제한이 없습니다.
작성·결재는 요청 h_id의 재직·부서·직급·현재 단계 담당자를 확인합니다.
h_id 입력만으로 신원이 증명되는 것은 아니므로 외부 공개 배포 전에는 기존 로그인과 쓰기 요청 신원 연결을 검토해야 합니다.

## 신규 계약

구장명 g_name, 종목 e_code, 주소 g_address, 위도 g_lat, 경도 g_lng,
수용 인원 g_num, 이용 정보 g_information, 운영 시간 g_time, 이용 금액 g_price를 모두 입력합니다.
e_code는 실제 ground의 VARCHAR(50)에 맞추고 축구·농구·배구·야구 문자열 중 하나를 받습니다.
Swagger Schema와 예제에 전체 구장 정보를 명시했습니다.

소유주는 owner_mode=신규이면 o_name과 선택 o_phone,
owner_mode=기존이면 기존 o_seq를 사용합니다. 신규 번호를 직접 입력하지 않습니다.
계약 조건·기간 등은 기존 c_treaty 작성 내용으로 전달하고, 대관료는 c_rentalfee로 받습니다.

배정은 m_id, a_day(요일 배열), a_period(오전/오후), a_start·a_end(HH:mm)로 입력합니다.
기존 assign의 a_day·a_time에 맞춰 저장하며, 같은 매니저의 기존·심사 중 시간 중복과 구장 운영 시간을 상신·최종 승인 때 검사합니다.

사진 업로드는 파일명 s_image를 반환합니다. 품의 내용에 s_image 배열로 첨부합니다.
별도 임시 DB 테이블 없이 파일만 임시 보관하고 승인 후 생성된 구장 번호로 shoot에 기록합니다.
JPEG/PNG/WebP, 10MB·25MP 제한 및 실제 이미지 형식을 검사합니다.

최종 승인 시 필요한 owner → ground → 소유주·구장 관계 maintain → shoot·assign → contract를 한 트랜잭션으로 저장합니다.
contract는 기존 o_seq·m_code 관계를 사용합니다. contract에 구장 FK를 새로 추가하지 않습니다.
생성된 g_code·o_seq는 품의서 작성 내용에도 보관합니다.
조회는 기존 /match/ground와 /match/ground/{g_code}를 유지합니다.

## 재계약·해지

재계약은 기존 구장 g_code를 선택하고 c_treaty·c_rentalfee를 입력합니다.
기존 품의서 내용 및 소유주·구장 관계에서 현재 계약을 확인합니다.
기존 소유주가 여러 구장을 관리하고 계약 구장이 문서에 명시되어 있지 않으면 추측해 연결하지 않습니다.

재계약·해지도 최종 승인 시 기존 contract 관계에 행을 추가하여 이전 계약을 남깁니다.
해지 여부는 해지 품의서 내용과 승인 기록으로 판단하고 별도 상태 컬럼을 만들지 않습니다.
계약 기간은 c_treaty 문서 내용으로 다루므로 별도 만료일 컬럼이나 자동 만료일 비교는 없습니다.
상신 후 다른 계약이 체결되면 최종 승인을 중단하고 재상신하도록 안내합니다.
구장·배정·과거 계약 이력은 삭제하지 않습니다.

## 휴가·대리 결재

휴가는 전 직원이 신청하고 인사팀 사원·팀장·임원이 결재합니다.
구장 계약 관련 작성·결재는 영업팀으로 한정합니다.
대리 업무 기간에 본인이 휴가를 신청하거나 휴가 중인 대리인을 지정하면 차단합니다.
심사 중 품의와 확정 h_vacation을 함께 검사하고 최종 승인 때 재검사합니다.

담당자가 휴가 중이면 h_vacation의 h_deputy가 결재합니다.
대리자도 휴가 중이면 차단하며 연쇄 위임하지 않습니다.
최종 승인 후 h_vacation의 기존 h_id·h_deputy·h_start·h_end만 저장합니다.

## 검증

가상 DB는 실제 ERD에 있는 컬럼만 생성하며 FK와 서명 길이 제한도 검사합니다.
검증 명령: python3 -m unittest discover -s python/tests -p 'test_*.py'
운영 DB에서는 조회 API만 호출해 기존 컬럼 호환을 확인합니다. 가상 데이터를 운영 DB에 넣지 않습니다.
실제 MySQL의 동시 잠금과 전체 상신·결재 저장 검증은 별도로 필요합니다.

최종 수정일 : 2026-10-27
