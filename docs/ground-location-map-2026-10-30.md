# 신규 구장 품의 지도 위치 선택

작성 일 : 2026-10-30 / 작업자 : 양태건

## 동작

신규 계약 품의의 구장 정보에서 지도 위치를 누르면 선택 좌표를 본사 전용
`GET /approval/ground-location?lat=...&lng=...`에 전달합니다.
도로명주소를 우선하고 없으면 지번주소를 사용합니다. 상세 주소가 없는 좌표는 거절합니다.
화면에는 선택 주소만 표시하며 전체 주소·위도·경도를 직접 입력하는 필드는 없습니다.
선택이 바뀌면 이전 응답을 무시하며, 변환 중이거나 실패하면 상신할 수 없습니다.

주소와 좌표는 기존 `POST /approval/requests`의 `data.g_address`, `g_lat`, `g_lng`로 전달됩니다.
품의 상신 시 기존 `memorandum.m_content`에 보관하고 최종 승인 시 기존 구장 INSERT로
`ground.g_address`, `g_lat`, `g_lng`에 저장합니다. 지도 클릭만으로 운영 DB를 변경하지 않습니다.
새 테이블·컬럼은 필요 없습니다.

## 서비스 설정

네이버 클라우드의 새 Maps Application에서 Mobile Dynamic Map과 Reverse Geocoding을 활성화합니다.
Android 패키지/iOS Bundle ID 등 서비스 등록 조건을 네이버 콘솔에서 확인합니다.

- Flutter: 실행 또는 빌드할 때 `--dart-define=NAVER_MAP_CLIENT_ID=<Mobile Dynamic Map Client ID>`를 전달합니다.
  Client ID는 공개 앱 식별자이며 Client Secret을 앱에 넣지 않습니다.
- 서버: 로컬 비공개 `.env`에 `NAVER_MAPS_CLIENT_ID`, `NAVER_MAPS_CLIENT_SECRET`을 설정합니다.
  값은 커밋·로그·채팅에 넣지 않습니다. 기존 환경 로더를 사용하며 서버 재시작 후 반영됩니다.
- 새 Maps의 `https://maps.apigw.ntruss.com/map-reversegeocode/v2/gc`를 사용합니다.
  발급받은 Application에서 주소 변환 API 사용이 활성화돼 있어야 합니다.

현재 설치된 Flutter 네이버 지도는 Android/iOS용입니다. 웹·데스크톱에서는 지원 안내를 표시하고
지도 선택 없이 상신하지 않습니다. 이 작업에서 별도의 웹 지도 구현은 추가하지 않았습니다.

공식 계약: https://api.ncloud-docs.com/docs/application-maps-overview

## 확인

Mock 지도/HTTP 및 가상 DB 테스트로 흐름을 검증합니다. 실제 인증키가 없는 상태에서는
네이티브 지도·네이버 주소 응답·실제 기기 연동을 확인할 수 없습니다.
설정 후 지도 클릭 → 주소 확인 → 상신 → 최종 승인 → 구장 좌표 저장을 직접 확인합니다.
