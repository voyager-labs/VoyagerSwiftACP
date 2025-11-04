# 6. 아키텍처 및 통합

## 6.1 기술 스택(현황)

- macOS: SwiftUI, TCA(ComposableArchitecture), AppKit 브릿지 일부
- Backend: FastAPI, SQLModel, Alembic, SQLite(개발), uv 런타임, Hydra

## 6.2 소스 트리 현실(요약)

- macOS: `apps/macos/Voyager/Voyager/**`, `VoyagerHelper/**`
- Backend: `apps/backend/src/{app,core,infra,utils}`, 설정: `src/conf/**`

## 6.3 통합 접근

- Database Integration: 기존 SQLite 및 Alembic 기반 유지, 컬렉션 및(후속) 임베딩 확장용 스키마 추가
- API Integration: `POST /search`(메타데이터 필터 중심), `POST /index`(메타 인덱싱), `POST /collections`(생성/업데이트), `GET /collections`(조회)
- Frontend Integration: `KeyCommandView` + Dock UI 컴포넌트 신설, 결과/컬렉션 뷰 라우팅
- Testing Integration: 백엔드 단위/통합 테스트(pytest), macOS 단위/간단 UI 테스트 추가

### API Conventions (공통 규약)
- Content Negotiation: `Content-Type: application/json`, `Accept: application/json`
- Timestamps: UTC ISO‑8601 형식(`YYYY-MM-DDThh:mm:ssZ`)
- Pagination: `limit` 기본 50(최대 200), `offset` 기본 0. 응답 `meta`에 `total`, `took_ms` 포함
- Error Payload(표준): `{ "error": { "code", "message", "details" } }`
  - 코드 예: `INVALID_FILTER(400)`, `NOT_FOUND(404)`, `CONFLICT(409)`, `TIMEOUT(408|504)`, `SERVER_ERROR(500)`
