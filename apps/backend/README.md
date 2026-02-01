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

### 2. Ollama 설치

```bash
brew install ollama
ollama pull qwen2.5:7b
```

### 3. 파일 인덱싱

```bash
uv run index --path ~/Downloads
```

---

## API 엔드포인트

이 백엔드는 현재 `/api/collection*` 하위에 검색 API를 제공합니다.

참고: OpenAPI 문서는 `http://localhost:8000/docs` 에서 확인할 수 있습니다.

### `POST /api/collection`
자연어 검색(LLM 기반) + 선택적 필터

요청(JSON): `QuerySearchRequest`
- `query`: string
- `filters` (optional): `{ scopes: string[], conditions: SearchCondition[] }`

```bash
curl -X POST http://localhost:8000/api/collection \
  -H "Content-Type: application/json" \
  -d '{"query":"PDF 파일"}'
```

### `POST /api/collection/filters`
필터 기반 검색(자연어 없이 필터만)

요청(JSON): `FilterSearchRequest`
- `filters`: `{ scopes: string[], conditions: SearchCondition[] }`

```bash
curl -X POST http://localhost:8000/api/collection/filters \
  -H "Content-Type: application/json" \
  -d '{"filters":{"scopes":[],"conditions":[]}}'
```

### 응답/에러 처리 메모

- 응답은 `{ "data": ... }` 형태의 envelope가 아니라 `SearchResponse`가 top-level로 반환됩니다.
- 일부 실패 케이스는 HTTP error로 raise 되지 않고 `SearchResponse.error` 필드로 표현되며, 이 경우에도 HTTP status가 `200`일 수 있습니다.

**쿼리 예시:**
- "PDF 파일"
- "최근 1주일 이내 수정된 이미지"
- "큰 동영상 파일"
- "Downloads 폴더의 파일"

---

**상세 가이드**

- 개발 환경: `docs/development.md`
- 검색 API/흐름: `docs/features/search.md`
