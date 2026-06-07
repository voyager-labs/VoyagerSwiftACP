# Voyager Backend

LLM 기반 자연어 파일 검색 API

## 테스트 환경 설정

### 1. 서버 실행

```bash
cd apps/backend
uv sync
uv run dev
```

서버: http://localhost:8000

## API 엔드포인트

이 백엔드는 현재 `/api/collection` 엔드포인트를 제공합니다.

참고: OpenAPI 문서는 `http://localhost:8000/docs` 에서 확인할 수 있습니다.

### `POST /api/collection`

자연어 쿼리 기반 조건 변환(LLM) + 선택적 필터

요청(JSON): `QuerySearchRequest`

- `query`: string
- `filters` (optional): `{ scopes: string[], conditions: SearchCondition[] }`

```bash
curl -X POST http://localhost:8000/api/collection \
  -H "Content-Type: application/json" \
  -d '{"query":"PDF 파일"}'
```

### 응답/에러 처리 메모

- 응답은 `{ "data": ... }` 형태의 envelope가 아니라 `SearchResponse`가 top-level로 반환됩니다.
- convert-only 전환으로 `items`는 현재 빈 배열(`[]`)이며, `appliedFilters`가 핵심 결과입니다.
- 일부 실패 케이스는 HTTP error로 raise 되지 않고 `SearchResponse.error` 필드로 표현되며, 이 경우에도 HTTP status가 `200`일 수 있습니다.

**쿼리 예시:**

- "PDF 파일"
- "최근 1주일 이내 수정된 이미지"
- "큰 동영상 파일"
- "Downloads 폴더의 파일"

---

**상세 가이드**

- 개발 환경: `docs/legacy/development.md`
- 검색 API/흐름: `docs/legacy/features/search.md`
