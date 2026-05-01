# 스키마 포맷 (확장)

이 레포는 표 형태 데이터 파일(예: `data.tsv`)의 구조/제약을 기술하기 위해 가벼운 `schema.json`
파일을 사용합니다.

초기 포맷은 아래만 포함했습니다.

- `name`
- `columns[]: { name, type, description }`

운영 중 필요한 메타데이터를 **하위 호환(backward-compatible)** 되게 확장하기 위해, 선택 필드를
추가합니다.

## 최상위 필드

- `schema_version` (string)
    - 예: `"1.0"`
- `name` (string)
    - 테이블 이름
- `primary_key` (string[] | optional)
    - row를 유일하게 식별하는 컬럼 이름 목록
- `null_values` (string[] | optional)
    - 테이블 전체에서 "빈 값"으로 취급할 센티넬(sentinel) 값 목록
    - 이 레포의 기본 센티넬은 `-`이며, 별도 지정이 없으면 `-`를 빈 값으로 간주합니다.

## 컬럼 필드

각 컬럼 객체는 아래 필드를 지원합니다.

- `name` (string)
- `type` (string)
    - 현재 지원하는 primitive: `string`, `number`
- `required` (boolean | optional)
    - row에서 값이 반드시 필요(필수 입력)한 컬럼인지
    - `required: true`인 컬럼은 `-`(= `null_values`, 기본값) 표기를 사용하지 않습니다.
    - `TBD`는 "아직 작성하지 못했지만 채워야 하는 값"을 의미하며, `required: true`인 컬럼에서도 사용할
      수 있습니다.
        - 단, `primary_key`로 지정된 컬럼에는 `TBD`를 사용하지 않습니다(안정적인 식별자 필요).
    - `required: false`인 컬럼은 `-`/`TBD` 표기를 사용할 수 있습니다.
- `description` (string | optional)
- `enum` (string[] | optional)
    - 해당 컬럼의 허용값 집합을 명시합니다.
    - 표현 형식은 JSON 배열입니다. 예: `"enum": ["command", "input", "display"]`
    - 값 없음/해당 없음은 enum 값으로 넣지 않고 `-`(null sentinel)로 표현합니다.
- `ref` (object | optional)
    - 외래키(foreign-key) 유사 참조를 선언

### `enum` 포맷

```json
{
    "name": "interaction_type",
    "type": "string",
    "required": false,
    "enum": ["command", "input", "display", "background"],
    "description": "인터랙션 타입."
}
```

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
