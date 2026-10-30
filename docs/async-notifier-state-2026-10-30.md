# 관리자 프론트 AsyncNotifier 상태관리

작성 일 : 2026-10-30 / 작업자 : 양태건

## 변경 범위

기존 혼합 구조에서 로그인과 24개 서버 조회를 AsyncNotifierProvider로 전환했습니다.
기존 저장·취소·업로드·지도 선택 AsyncNotifier는 유지합니다.
Provider 이름·조회 키·응답 모델·API 경로·자동 재시도 비활성화 정책은 유지합니다.
코드 생성 패키지를 추가하지 않고 Riverpod 3의 수동 선언을 사용합니다.

- 로그인: `LoginNotifier extends AsyncNotifier<StaffSession?>`.
  중복 로그인을 막고, reset 이후 도착한 이전 인증 결과는 무시합니다.
- 공통 조회: `OperationsDataNotifier`(경로별), `AdminDataNotifier`(담당자·경로별).
- 구장: `GroundListNotifier`, `GroundDetailNotifier`.
- 교육: 목록·매니저·배정 종목·평가 조회용 Notifier.
- 신고: 목록·상세 조회용 Notifier.
- 배너: 목록 조회용 Notifier.
- 매니저: 일정·팀 경기 상세·일자별 경기·예정 경기·결과·결과 상세·점수 규칙·출전명단·취소 결과 Notifier.
- 경기/취소: 팀 경기 목록·상세, 취소 목록·상세 Notifier.

`ref.watch(provider)`는 여전히 AsyncValue를 반환하므로 화면의 로딩·데이터·오류 분기와
`provider.future`, `ref.invalidate(provider)` 사용 방법을 유지합니다.
단순 조회는 Notifier의 build에서 로드하고 재조회는 기존 invalidate 경로를 사용합니다.
저장 동작은 해당 mutation Notifier의 메서드로 실행합니다.

## 경기 운영

화면 내부에 있던 서버 조회·명령 전송을 `MatchWorkflowNotifier`와
`MatchWorkflowService`로 옮겼습니다. 키는 담당자와 경기 API 경로입니다.
reload와 command가 통신 상태를 관리하고, 명령은 마지막 서버 버전을 전송합니다.
실패해도 Notifier가 마지막 확인 데이터를 보존해 화면 입력을 유지하며,
이미 처리 중인 명령은 재전송하지 않습니다.
경기 화면은 명령 성공 여부와 상태 변경을 구독하여 오버레이와 컨트롤러를 갱신합니다.

## 화면 상태까지 전환 (후속 요청 반영)

검색어·신고 필터·매칭 유형·한국 기준 날짜도 AsyncNotifierProvider로 전환했습니다.
화면/대화상자 29개의 선택값·페이징·품의 작성값·부상 입력·배너 선택·메뉴 등을
`screenStateProvider`의 화면별 Scope로 관리합니다. 야구 주자 선택과 결재 의견 대화상자도
각각 독립 Scope를 사용합니다. 기존 화면의 setState와 StatefulBuilder는 제거했습니다.

`AsyncScreenState`는 화면마다 Scope를 만들고 provider를 구독합니다.
상태 필드 getter/setter는 해당 Notifier의 값을 읽고 변경합니다.
컬렉션을 변경할 때는 화면별 복사 함수로 이전 스냅샷을 보존하고,
한 번의 사용자 동작에서 여러 필드를 수정하면 한 번에 반영합니다.
변경 도중 예외가 발생하면 이전 상태를 유지합니다.
계정이나 조회 문맥이 바뀌는 기존 초기화 경로는 Scope 교체로 처리합니다.
화면의 마지막 구독이 사라지면 autoDispose로 정리합니다.

입력 컨트롤러는 화면에서 dispose하는 UI 자원이며 입력 문자열 변경은 화면 Notifier에 반영합니다.
스크롤 컨트롤러·지도 컨트롤러·폼 키·오버레이·타이머 핸들 자체도 UI 자원으로 유지합니다.
타이머가 표시를 갱신할 때는 화면 Notifier를 갱신합니다.
기능별 서버 상태와 화면 입력 상태를 서로 다른 Notifier로 관리합니다.

일반 Provider는 HTTP client·서비스 객체·지도 위젯 팩토리 같은 의존성 주입에만 사용합니다.
이 객체들은 사용자 입력·서버 데이터 상태가 아니며 수명 관리와 테스트 주입을 담당합니다.
기능 데이터·입력·선택 상태에 FutureProvider 또는 일반 NotifierProvider를 사용하지 않습니다.
동기 선택값도 AsyncNotifier.build에서 즉시 초기화하며 불필요한 HTTP 요청이나 지연은 추가하지 않습니다.

## 저장 범위와 검증

AsyncNotifier 전환은 앱 메모리의 상태관리 변경이며 임시저장·영구 저장 기능을 추가하지 않습니다.
API·Python·실제 DB를 변경하지 않습니다.
Mock/위젯 테스트로 로그인·계정 변경·목록/상세·저장·경기 전체화면·결과 등록을 검증합니다.
추가 테스트 `test/async_state_test.dart`는 중복 명령·실패 복구·늦은 검색 응답·로그아웃 경합을 확인합니다.

추가 테스트 `test/screen_state_test.dart`로 화면별 상태 격리, 이전 스냅샷 보존,
예외 복구, 입력 문자열 반영과 화면 종료 후 상태 정리를 확인합니다.
