# 기술 부채와 알려진 이슈(관측)

1. macOS의 BackendManager 중복(`BackendManager`, `BackendManagerDotenv`, `BackendManagerWithConfig`) — 설정 소스(plist/.env)와 로깅 정책을 일원화 필요
2. `apps/backend/`의 로컬 DB 아티팩트 커밋 — 개발 편의상 허용하되, 민감/운영 데이터 금지 및 로테이션 주의
3. 검색/인덱스용 라우트 미구현 — SQLModel 리포지토리와 일치하는 스켈레톤 필요
4. Chunker 유틸 존재하나 MVP는 메타데이터 우선 — 의존 최소화로 선택적 사용 보장
5. macOS에서 `.env` 탐색 기반 설정 발견 로직 — 폴백/제한을 문서화 필요
