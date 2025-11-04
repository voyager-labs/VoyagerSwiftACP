# 12. 로컬 회귀 스모크 체크리스트

- Backend
  - `cd apps/backend && uv run dev` 기동 후 `GET /` 헬스 확인
  - 소규모 데이터셋에서 `POST /search` 스텁 호출 → 200 응답 및 기본 필드 유효성
  - 로그에 DB 초기화/Alembic 적용 여부 표시 확인

- macOS
  - 앱 실행 → 단축키로 Dock 표시/입력/ESC 닫기 → 파일 리스트 포커스 복귀
  - 백엔드 중단 상태에서 Dock 동작 시 오류 메시지와 폴백 UX 확인
