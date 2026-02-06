# 스키마 포맷 (확장)

이 레포는 표 형태 데이터 파일(예: `data.tsv`)의 구조/제약을 기술하기 위해 가벼운 `schema.json` 파일을 사용합니다.

초기 포맷은 아래만 포함했습니다.

- `name`
- `columns[]: { name, type, description }`

운영 중 필요한 메타데이터를 **하위 호환(backward-compatible)** 되게 확장하기 위해, 선택 필드를 추가합니다.

## 최상위 필드

- `schema_version` (string)
  - 예: `"1.0"`
- `name` (string)
  - 테이블 이름
- `primary_key` (string[] | optional)
  - row를 유일하게 식별하는 컬럼 이름 목록
- `null_values` (string[] | optional)
  - 테이블 전체에서 "빈 값"으로 취급할 센티넬(sentinel) 값 목록

## 컬럼 필드

각 컬럼 객체는 아래 필드를 지원합니다.

- `name` (string)
- `type` (string)
  - 현재 지원하는 primitive: `string`, `number`
- `required` (boolean | optional)
  - 컬럼이 존재해야 하고, 값이 비어 있으면 안 되는지
- `nullable` (boolean | optional)
  - null/빈 값 허용 여부 (`null_values`에 포함된 값 포함)
- `description` (string | optional)
- `ref` (object | optional)
  - 외래키(foreign-key) 유사 참조를 선언

### `ref` 포맷

단일 컬럼 참조:

```json
{
  "table": "MENUS",
  "column": "menu_node_id"
}
```

복합 참조(셀프 참조 또는 복합 키):

```json
{
  "table": "WINDOW_STRUCTURE",
  "columns": ["window_id", "parent_region_id"],
  "references": ["window_id", "region_id"]
}
```

## 노트

- 스키마는 우선 "기술(descriptive)" 목적이며, 강제(검증)는 tooling/CI로 이후 추가할 수 있습니다.
- 애매할 때는 관계를 자유 텍스트로 우겨넣기보다, `ref` 메타데이터를 추가하는 방식을 우선합니다.
