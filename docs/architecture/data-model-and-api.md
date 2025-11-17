# 데이터 모델과 API

## 데이터 모델

- 파일 엔트리 스키마: `apps/backend/src/infra/schemas/file_entry_schema.py` (메타데이터 영속 대상)
- 컬렉션(후속)과 임베딩(후속)용 스키마는 추후 추가 예정

## 현재/계획 API

- 현재: `GET /` — 헬스/플레이스홀더
- 계획(PRD 기준):
  - `POST /index` — 선택 경로 메타데이터 인덱싱 등록(초기엔 동기 처리 가능)
  - `POST /search` — 자연어 또는 구조화 메타 필터 → 파일 결과 반환
  - `POST /collections` / `GET /collections` — 컬렉션 생성/업데이트 및 조회

## API Contracts (Draft)

### 공통 규약 (API Conventions)

- Content Negotiation: `Content-Type: application/json`, `Accept: application/json`
- Timestamps: 모든 시간 필드는 UTC ISO‑8601 형식(`YYYY-MM-DDThh:mm:ssZ`)
- Pagination: `limit` 기본 50(최대 200), `offset` 기본 0. 응답 `meta`에 `total`, `took_ms` 포함
- Error Payload(표준)
  ```json
  {
    "error": {
      "code": "INVALID_FILTER",
      "message": "Filter 'extension' must be array of strings",
      "details": { "field": "filters.extension" }
    }
  }
  ```
  - 공통 코드: `INVALID_FILTER(400)`, `NOT_FOUND(404)`, `CONFLICT(409)`, `TIMEOUT(408|504)`, `SERVER_ERROR(500)`

### `POST /search`
- Request
  ```json
  {
    "query": "recent pdf about voyager",
    "filters": {
      "extension": ["pdf"],
      "modified_after": "2024-01-01T00:00:00Z",
      "path_contains": ["/Documents/"]
    },
    "limit": 50,
    "offset": 0
  }
  ```
  - Notes: `limit` 기본 50(최대 200), `offset` 기본 0
- Response 200
  ```json
  {
    "items": [
      {
        "path": "/Users/me/Documents/voyager-spec.pdf",
        "name": "voyager-spec.pdf",
        "size": 123456,
        "modified_at": "2024-10-10T12:34:56Z",
        "uti": "com.adobe.pdf",
        "score": 0.91
      }
    ],
    "meta": { "total": 12, "took_ms": 120 }
  }
  ```
- Errors: `400` invalid filters, `500` server error, timeout → 표준 에러 페이로드

### `POST /index`
- Request
  ```json
  {
    "paths": ["/Users/me/Documents"],
    "recursive": true,
    "follow_symlinks": false
  }
  ```
- Response 200
  ```json
  {
    "indexed": 124,
    "skipped": 7,
    "errors": 0,
    "took_ms": 1530
  }
  ```
- Notes: 초기 동기 처리 → 후속으로 비동기 잡 + 상태 조회 엔드포인트 도입
  - 정책: 로컬 개발 표준은 지정 루트 전체(full) 인덱싱. 부분 경로 인덱싱은 후속 옵션으로 검토

## Migration Concurrency & Backup
- 초기화/마이그레이션 시 동시 실행 방지를 위해 락 파일을 사용합니다(단일 실행 보장)
- 버전 미스매치 또는 무버전 DB 부트스트랩 시 자동 백업이 생성될 수 있습니다(운영 경로는 추후 재확인)

### `POST /collections` / `GET /collections`
- Create/Update (POST) Request
  ```json
  {
    "name": "Recent PDFs",
    "query": "pdf modified after 2024-01-01",
    "filters": { "extension": ["pdf"], "modified_after": "2024-01-01T00:00:00Z" }
  }
  ```
- Get (GET) Response 200
  ```json
  {
    "items": [
      { "id": 1, "name": "Recent PDFs", "query": "...", "filters": {"extension": ["pdf"]} }
    ]
  }
  ```
 - Notes: `GET /collections`는 `limit`/`offset`을 지원(기본 50/0, 최대 200). 응답은 `meta`를 포함할 수 있음
