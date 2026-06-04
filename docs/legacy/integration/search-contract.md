# 검색 기능

## 개요

VOY-164 이후 backend search API는 **convert-only**로 동작합니다.

1. 자연어 `query`를 LLM으로 해석해 `conditions`/`scopes`를 생성 또는 보정하고
2. 그 결과를 `appliedFilters`로 반환합니다.

중요: backend는 더 이상 로컬 SQLite 검색 실행을 하지 않습니다. 따라서 현재 응답의 `items`는 빈 배열(`[]`)입니다.

## 용어

- `query`: 사용자가 입력한 자연어 문자열
- `filters`: 클라이언트가 함께 전달하는 기존 필터(`scopes`, `conditions`)
- `appliedFilters`: 서버가 최종적으로 해석/보정한 필터
- Registry: `shared/system_property_registry.json`, `shared/property_condition_registry.json`

## API

### 엔드포인트

- `POST /api/collection`
    - 자연어 검색 쿼리 + 선택적 필터를 입력으로 받음
    - LLM 변환 결과를 `appliedFilters`로 반환

관련 코드

- `apps/backend/src/app/search/routes.py`
- `apps/backend/src/app/search/services.py`
- `apps/backend/src/app/search/schemas.py`

### 요청 스키마

- `QuerySearchRequest`
    - `query: str` (trim 후 공백만이면 422)
    - `filters: SearchFilters | null`
- `SearchFilters`
    - `scopes: string[]` (default `[]`)
    - `conditions: SearchCondition[]` (default `[]`)
- `SearchCondition`
    - `propertyKey: string`
    - `operator: string`
    - `value: string | number | array | null`

### 요청 예시

```bash
curl -X POST http://localhost:8000/api/collection \
  -H "Content-Type: application/json" \
  -d '{
    "query": "최근 다운로드한 PDF",
    "filters": {
      "scopes": ["/Users/you/Downloads"],
      "conditions": [
        {"propertyKey": "extension", "operator": "any", "value": ["pdf"]}
      ]
    }
  }'
```

## 응답/에러 처리

### 응답 스키마

`SearchResponse`가 top-level JSON으로 반환됩니다.

- `itemCount: int` (현재 `0`)
- `appliedFilters: { scopes: string[], conditions: SearchCondition[] }`
- `items: SearchItem[]` (현재 `[]`)
- `error: { code: string, details?: string } | null`

### 실패 표현

일부 실패는 HTTP status가 아니라 `error` 필드로 표현됩니다.

- HTTP 200 + `error != null` 가능
- 대표 코드: `LLM_CONVERSION_FAILED`

관련 코드

- `apps/backend/src/app/search/services.py`
- `apps/macos/Voyager/Packages/VoyagerModules/Sources/VoyagerFeaturesComposer/Api/SearchClient.swift`

## LLM 변환

### 구성 요소

- `SearchConditionConverter`
- `CachedSearchConditionConverter`

관련 코드

- `apps/backend/src/core/llm/search_condition_converter.py`
- `apps/backend/src/core/llm/prompts/compose_filter_system.md`

### 동작 요약

- query와 기존 filters를 바탕으로 변환 프롬프트를 구성
- 레지스트리 기반으로 허용 가능한 key/operator 범위를 제한
- 변환 실패 시 `LLM_CONVERSION_FAILED`를 반환하고 기존 filters를 유지

## 레지스트리

- `shared/system_property_registry.json`
    - 속성 키/타입/alias 등 정의
- `shared/property_condition_registry.json`
    - 연산자/값 형태 제약 정의

관련 코드

- `apps/backend/src/core/metadata/registry_loader.py`

## 디버깅/운영 팁

- 서버 단독으로 `POST /api/collection`을 호출해 `appliedFilters`와 `error`를 먼저 확인
- UI에서 결과가 비어 보여도 서버 응답의 `error` 필드를 함께 점검

## 테스트

현재 backend 테스트는 convert-only 계약을 기준으로 검증합니다.

- `apps/backend/tests/test_search_service_convert_only.py`
- `apps/backend/tests/test_system_property_registry.py`
