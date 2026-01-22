# Search API Spec (Message vs Filters)

## 엔드포인트 1: 쿼리 기반 검색

- `POST /api/search`
- **LLM이 자연어를 해석하여 조건 생성**

### 요청 필드

| 필드                 | 타입     | 필수 | 설명                          |
| -------------------- | -------- | ---- | ----------------------------- |
| `query`              | string   | ✅   | 자연어 검색 쿼리 (최소 1자)   |
| `filters`            | object   | ❌   | 선택적 필터                   |
| `filters.scopes`     | string[] | ❌   | 검색 경로 범위 (빈 배열 가능) |
| `filters.conditions` | object[] | ❌   | 검색 조건 목록 (빈 배열 가능) |

### 동작 방식

1. **쿼리 우선 해석**: LLM이 `query`를 분석하여 조건 생성
2. **기존 조건 조합**: `filters.conditions`가 있으면 LLM이 지능적으로 조합
3. **스코프 우선순위**:
    - ⚠️ **쿼리에서 폴더를 언급하면 쿼리의 폴더가 우선**
    - 쿼리에 폴더 언급이 없으면 `filters.scopes` 유지

### 요청 예시

```json
{
    "query": "다운로드 폴더에서 최근에 생성된 png 파일 찾아줘",
    "filters": {
        "scopes": [],
        "conditions": []
    }
}
```

**filters 없이 요청도 가능:**

```json
{
    "query": "10MB 이상의 PDF 파일"
}
```

### 응답 예시

```json
{
    "itemCount": 5,
    "appliedFilters": {
        "scopes": ["/Users/username/Downloads"],
        "conditions": [
            { "propertyKey": "creation_date", "operator": "gt", "value": "2025-12-23" },
            { "propertyKey": "extension", "operator": "eq", "value": "png" }
        ]
    },
    "items": [
        {
            "id": 1,
            "path": "/Users/username/Downloads/screenshot.png",
            "name": "screenshot.png",
            "size": 102400,
            "extension": "png",
            "fileKind": "PNG Image",
            "modificationDate": "2025-12-29T10:30:00"
        }
    ]
}
```

---

## 엔드포인트 2: 필터 전용 검색

- `POST /api/search/filters`
- **LLM 없이 조건을 직접 적용**

### 요청 필드

| 필드                 | 타입     | 필수 | 설명           |
| -------------------- | -------- | ---- | -------------- |
| `filters`            | object   | ✅   | 필수 필터      |
| `filters.scopes`     | string[] | ✅   | 검색 경로 범위 |
| `filters.conditions` | object[] | ✅   | 검색 조건 목록 |

### 요청 예시

```json
{
    "filters": {
        "scopes": ["/Users/username/Documents"],
        "conditions": [
            { "propertyKey": "name_full", "operator": "matches", "value": "%report%" },
            { "propertyKey": "file_allocated_size", "operator": "between", "value": [1048576, 104857600] }
        ]
    }
}
```

### 응답 예시

```json
{
    "itemCount": 1,
    "appliedFilters": {
        "scopes": ["/Users/username/Documents"],
        "conditions": [
            { "propertyKey": "name_full", "operator": "matches", "value": "%report%" },
            { "propertyKey": "file_allocated_size", "operator": "between", "value": [1048576, 104857600] }
        ]
    },
    "items": [
        {
            "id": 10,
            "path": "/Users/username/Documents/q1_report.pdf",
            "name": "q1_report.pdf",
            "size": 2097152,
            "extension": "pdf",
            "fileKind": "PDF Document",
            "modificationDate": "2025-12-15T14:20:00"
        }
    ]
}
```

---

## 프론트엔드 개발 가이드

### 빈 배열 처리

| 필드         | 빈 배열 전송 | 동작                               |
| ------------ | ------------ | ---------------------------------- |
| `scopes`     | `[]`         | ✅ **전체 인덱싱된 파일에서 검색** |
| `conditions` | `[]`         | ✅ 조건 없이 검색 (스코프만 적용)  |

**예시: 전체 검색**

```json
{
    "filters": {
        "scopes": [],
        "conditions": [{ "propertyKey": "extension", "operator": "eq", "value": "pdf" }]
    }
}
```

→ 인덱싱된 모든 경로에서 PDF 파일 검색

---

### 스코프(Scopes) 규칙

#### 엔드포인트 1 (`/api/search`)

| 상황                                                       | 동작                                             |
| ---------------------------------------------------------- | ------------------------------------------------ |
| 쿼리: "다운로드 폴더에서..." + scopes: []                  | ✅ **쿼리 우선** → `/Users/.../Downloads`        |
| 쿼리: "PDF 찾아줘" + scopes: ["/Users/.../Documents"]      | ✅ **기존 스코프 유지** → `/Users/.../Documents` |
| 쿼리: "데스크탑에서..." + scopes: ["/Users/.../Documents"] | ✅ **쿼리 우선** → `/Users/.../Desktop`          |

#### 엔드포인트 2 (`/api/search/filters`)

- 전달된 `scopes` 그대로 적용 (해석 없음)
- `scopes: []` → 전체 파일 검색

---

### 지원 속성 (propertyKey)

| propertyKey   | 타입     | 지원 연산자                   | 설명                           |
| ------------- | -------- | ----------------------------- | ------------------------------ |
| `name_full`        | STRING   | eq, neq, empty, exists, starts_with, ends_with, matches | 파일 이름 (확장자 포함) |
| `extension`        | STRING   | eq, neq, empty, exists, starts_with, ends_with, matches | 확장자 (점 없이: "pdf", "png") |
| `file_allocated_size` | NUMBER   | eq, gt, gte, lt, lte, between, not_between | 파일 크기 (bytes) |
| `creation_date`    | DATE | eq, gt, gte, lt, lte, between, not_between | 생성일 |
| `modification_date` | DATE | eq, gt, gte, lt, lte, between, not_between | 수정일 |
| `file_kind`        | STRING   | eq, neq, empty, exists, starts_with, ends_with, matches | 파일 종류 |
| `content_type_tree` | STRING   | eq, neq, empty, exists, starts_with, ends_with, matches | UTI 타입 트리 |
| `downloaded_date`  | DATE | eq, gt, gte, lt, lte, between, not_between | 다운로드 완료 시간 |

---

### 연산자 (operator)

| 연산자      | 설명          | value 형식 | 예시                    |
| ----------- | ------------- | ---------- | ----------------------- |
| `eq`        | 정확히 일치   | 단일값     | `"pdf"`, `1024`         |
| `neq`       | 일치하지 않음 | 단일값     | `"pdf"`, `1024`         |
| `gt`        | 초과 (>)      | 단일값     | `10485760`              |
| `gte`       | 이상 (>=)     | 단일값     | `10485760`              |
| `lt`        | 미만 (<)      | 단일값     | `10485760`              |
| `lte`       | 이하 (<=)     | 단일값     | `10485760`              |
| `between`   | 범위          | [min, max] | `[1048576, 104857600]`  |
| `not_between` | 범위 밖     | [min, max] | `[1048576, 104857600]`  |
| `starts_with` | 접두어 일치 | 단일값     | `"report"`             |
| `ends_with`   | 접미어 일치 | 단일값     | `"report.pdf"`               |
| `matches`   | 패턴 매칭 (SQL LIKE) | 단일값 | `"%report%"`      |
| `contains_any` | 목록 중 하나 포함 | 배열 | `["tag1", "tag2"]` |
| `contains_all` | 목록 전부 포함 | 배열 | `["tag1", "tag2"]` |
| `not_contains_any` | 목록 포함 없음 | 배열 | `["tag1", "tag2"]` |
| `not_contains_all` | 목록 일부 미포함 | 배열 | `["tag1", "tag2"]` |
| `empty`     | 값 없음       | 없음       | -                       |
| `exists`    | 값 존재       | 없음       | -                       |

---

### value 타입

| 타입     | 형식         | 예시                              |
| -------- | ------------ | --------------------------------- |
| STRING   | 문자열       | `"pdf"`, `"report"`               |
| NUMBER   | 숫자 (bytes) | `10485760` (10MB)                 |
| DATE     | YYYY-MM-DD   | `"2025-12-25"`                    |
| 배열     | [...]        | `["jpg", "png"]`, `[1024, 10240]` |

**크기 변환 참고:**

- 1 KB = 1,024 bytes
- 1 MB = 1,048,576 bytes
- 1 GB = 1,073,741,824 bytes

---

### 응답 아이템 (SearchItem)

| 필드               | 타입           | 설명                    |
| ------------------ | -------------- | ----------------------- |
| `id`               | number         | 파일 ID                 |
| `path`             | string         | 절대 경로               |
| `name`             | string         | 파일 이름 (확장자 포함) |
| `size`             | number         | 파일 크기 (bytes)       |
| `extension`        | string \| null | 확장자                  |
| `fileKind`         | string \| null | 파일 종류               |
| `modificationDate` | string \| null | 수정일 (ISO 8601)       |

---

### 에러 응답

#### 400 Bad Request

```json
{
    "detail": "query는 최소 1자 이상이어야 합니다"
}
```

#### 422 Validation Error

```json
{
    "detail": [
        {
            "loc": ["body", "query"],
            "msg": "field required",
            "type": "value_error.missing"
        }
    ]
}
```

---

## 사용 시나리오

### 시나리오 1: 자연어 검색

```json
// 요청
{ "query": "어제 다운로드한 이미지 파일들" }

// 응답 appliedFilters
{
  "scopes": ["/Users/username/Downloads"],
  "conditions": [
    { "propertyKey": "downloaded_date", "operator": "gt", "value": "2025-12-29" },
    { "propertyKey": "extension", "operator": "eq", "value": "jpg" }
  ]
}
```

### 시나리오 2: 자연어 + 기존 필터 조합

```json
// 요청: 기존 조건 + 추가 쿼리
{
  "query": "이 중에서 10MB 이상인 것만",
  "filters": {
    "scopes": ["/Users/username/Downloads"],
    "conditions": [
      { "propertyKey": "extension", "operator": "eq", "value": "pdf" }
    ]
  }
}

// 응답: LLM이 기존 조건 유지 + 새 조건 추가
{
  "appliedFilters": {
    "scopes": ["/Users/username/Downloads"],
    "conditions": [
      { "propertyKey": "extension", "operator": "eq", "value": "pdf" },
      { "propertyKey": "file_allocated_size", "operator": "gte", "value": 10485760 }
    ]
  }
}
```

### 시나리오 3: 직접 필터 검색

```json
// 요청: LLM 없이 직접 필터 적용
{
    "filters": {
        "scopes": [],
        "conditions": [{ "propertyKey": "file_allocated_size", "operator": "gt", "value": 104857600 }]
    }
}

// 응답: 전체 경로에서 100MB 초과 파일
```
