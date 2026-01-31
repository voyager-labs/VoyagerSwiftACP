# Registry JSON (스펙/운영)

Voyager는 검색 조건(속성/연산자)을 **JSON 레지스트리**로 정의하고,
macOS(UI/Helper)와 Backend가 동일한 정의를 공유합니다.

레지스트리는 크게 2개입니다.

- `shared/system_property_registry.json`: "무엇을" 검색할 수 있는가(속성 키/타입/라벨/메타데이터 키)
- `shared/property_condition_registry.json`: "어떻게" 비교할 것인가(연산자/값 형태/SQL 변환 규칙)

## 1. 배치 위치/배포

### 1.1 소스 트리

- `shared/system_property_registry.json`
- `shared/property_condition_registry.json`

### 1.2 macOS 번들 포함

Xcode 프로젝트 리소스로 `shared/*.json`이 포함됩니다.

- `apps/macos/Voyager/Voyager.xcodeproj/project.pbxproj`

로딩은 번들 리소스에서 수행합니다.

- `apps/macos/Voyager/Shared/Registries/RegistryLoader.swift`

### 1.3 Backend 바이너리(번들) 포함

Nuitka 빌드 시 `shared/` 경로로 데이터 파일이 포함됩니다.

- `scripts/build/compile-nuitka-binary.sh`
  - `--include-data-files=...=shared/system_property_registry.json`
  - `--include-data-files=...=shared/property_condition_registry.json`

## 2. system_property_registry.json

### 2.1 목적

"propertyKey"의 표준을 정의합니다.

- UI(컴포저)에서 보여줄 속성 목록/라벨/카테고리
- LLM이 조건으로 변환할 수 있는 속성 키(검색 alias 포함)
- 저장/조회 관점에서 이 속성이 DB 컬럼인지(JSON인지)

### 2.2 최상위 스키마

```json
{
  "$kind": "system_property_registry",
  "$version": "2.2.0",
  "categories": {
    "common": {
      "uniform_type_identifier": {
        "type": "categorical",
        "ui_label": "Content type",
        "description": "...",
        "system_keys": ["mditem:kMDItemContentType", "nsurl:NSURLContentTypeKey"],
        "search_aliases": ["content types"],
        "legacy_keys": ["contentType"],
        "db_indexed": true,
        "ui_pinned": true,
        "ui_hidden": false
      }
    }
  }
}
```

필드 설명

- `$kind`: 고정 문자열 `system_property_registry`
- `$version`: 문서/운영 관점의 버전(semver 권장)
- `categories`: `{ categoryKey: { propertyKey: definition } }`

### 2.3 property definition 스키마

각 `propertyKey`는 아래 필드를 가질 수 있습니다.

- `type` (필수): 값 타입
  - 허용 값(현재 기준): `string`, `number`, `date`, `boolean`, `string_list`, `categorical`
- `ui_label` (권장): UI 표시 라벨
- `description` (권장): 의미/출처 설명
- `system_keys` (필수): 원천 메타데이터 키 목록
  - prefix 예시: `mditem:`, `nsurl:`, `mdimporter:`
- `search_aliases` (선택): 자연어 쿼리에서 키를 추론하기 위한 alias
- `legacy_keys` (선택): 과거 키와의 매핑(마이그레이션/호환)
- `availability` (선택): OS 버전 등 가용성 메모
- `value_format` (선택): UI/표시용 포맷 힌트
- `db_indexed` (선택): 전용 DB 컬럼 사용 여부
  - `true`: entries 테이블의 컬럼을 직접 비교
  - `false`/없음: `entries.original_metadata` JSON에서 `system_keys` 기반으로 추출
- `ui_pinned` (선택): UI 상단 고정 여부
- `ui_hidden` (선택): UI/검색에서 숨김 처리

## 3. property_condition_registry.json

### 3.1 목적

각 타입별 "기본 연산자"와, 연산자 코드(예: `eq`, `btw`, `any`)의 정의를 제공합니다.

### 3.2 최상위 스키마

```json
{
  "$kind": "property_condition_registry",
  "$version": "2.1.0",
  "property_types": {
    "string": {"operators": ["cn", "eq"], "sql_cast": "TEXT"}
  },
  "operators": {
    "eq": {
      "ui_label": "Is",
      "sql_operator": "=",
      "sql_kind": "comparison",
      "value_shape": "single",
      "value_count": 1,
      "allowed_types": ["string", "number"],
      "aliases": ["is", "equals"],
      "inverse_of": "neq",
      "ui_value_kind": {"string": "singleText", "number": "singleNumber"}
    }
  }
}
```

필드 설명

- `$kind`: 고정 문자열 `property_condition_registry`
- `$version`: 문서/운영 관점의 버전(semver 권장)
- `property_types`: `{ typeKey: defaults }`
- `operators`: `{ operatorCode: operatorDefinition }`

### 3.3 property_types.<typeKey>

- `operators`: 해당 타입에서 기본 제공할 연산자 코드 목록
- `sql_cast`: JSON 추출 시 캐스팅 타입(backend에서 사용)
  - 예: `TEXT`, `REAL`, `INTEGER`

### 3.4 operators.<operatorCode>

- `ui_label`: UI에 표시할 연산자 이름
- `sql_operator`: SQL operator 또는 템플릿(backend에서 사용)
- `sql_kind`: backend가 clause를 생성하는 방식
  - 예: `comparison`, `range`, `like_prefix`, `like_suffix`, `like_pattern`,
    `exists`, `empty`, `string_list_any`, `string_list_all`, `string_list_not_any`, `string_list_not_all`
- `value_shape`: 값 형태
  - `none` / `single` / `list` / `range`
- `value_count`: 값 개수
  - `0`, `1`, `2`, 또는 `"n"`(1개 이상)
- `allowed_types`: 적용 가능한 타입 목록
- `inverse_of`: 역연산자(있는 경우)
- `aliases`: 자연어/동의어(LLM 프롬프트/UX에서 활용 가능)
- `ui_value_kind`: UI 입력 컨트롤 힌트 (typeKey → UI kind)

## 4. 로딩/사용 방식

### 4.1 macOS

레지스트리는 번들 리소스에서 JSON으로 로드됩니다.

- 로더: `apps/macos/Voyager/Shared/Registries/RegistryLoader.swift`
- 스키마:
  - `apps/macos/Voyager/Shared/Registries/SystemPropertyRegistry.swift`
  - `apps/macos/Voyager/Shared/Registries/PropertyConditionRegistry.swift`

`RegistrySnapshot.load()`는 아래를 구성합니다.

- 카테고리/라벨/타입 맵
- `legacyKeyMap` (legacy → current)
- 속성별 연산자 옵션(타입 기본 연산자 + UI 유효성 필터)

관련 코드

- `apps/macos/Voyager/Voyager/05_Entities/Collection/Model/RegistrySnapshot.swift`

### 4.2 Backend

backend는 레지스트리를 파일 시스템에서 찾고 로드합니다.

- 로더: `apps/backend/src/core/metadata/registry_loader.py`
  - `$kind` 검증
  - `system_keys`에서 `json_path` 유도
  - 타입별 기본 연산자/allowed_types를 기반으로 `supported_operators` 계산

검색 조건 → SQL 변환은 아래에서 수행합니다.

- `apps/backend/src/core/search/condition_builder.py`
  - `db_indexed=true`: 컬럼 비교
  - `db_indexed=false`: `original_metadata` JSON에서 `json_extract` + `sql_cast`
  - `string_list_*`: SQLite JSON1 함수(`json_each`, `json_array_length`) 기반

## 5. 운영 가이드

### 5.1 새 propertyKey 추가

1) `shared/system_property_registry.json`에 항목 추가

- `type`, `ui_label`, `description`, `system_keys`를 우선 채움
- 자연어 추론이 필요하면 `search_aliases` 추가
- 키 변경/정규화가 필요하면 `legacy_keys`로 호환 유지

2) 저장 방식 결정 (`db_indexed`)

- `db_indexed=true`로 두려면:
  - entries 테이블에 실제 컬럼이 존재해야 함
  - 인덱싱 파이프라인이 해당 값을 컬럼에 저장해야 함
- `db_indexed=false`로 둘려면:
  - `system_keys`에 해당하는 값이 `original_metadata` JSON에 저장되어 있어야 함

주의: `system_keys`가 `nsurl:`만 있고 인덱싱 파이프라인이 해당 값을 저장하지 않으면,
쿼리는 항상 NULL로 평가될 수 있습니다. (필요 시 `ui_hidden=true`로 숨김 처리 권장)

### 5.2 새 operator 추가

1) `shared/property_condition_registry.json`에 `operators.<code>` 추가

- `sql_kind`는 backend 구현(ConditionBuilder)의 분기와 정합해야 함
- `ui_value_kind`는 macOS에서 입력 UI를 결정하므로 type별 키를 빠뜨리면 UI 옵션에서 제외될 수 있음

2) 노출할 타입의 `property_types.<typeKey>.operators`에 code를 추가

### 5.3 버전/호환성

- `$version`은 레지스트리 구조/의미가 바뀔 때 업데이트를 권장합니다.
- `propertyKey`는 외부/내부 API 계약의 일부로 취급하고, rename 시에는 삭제 대신 `legacy_keys`로 우회합니다.

## 6. 트러블슈팅

### 6.1 macOS에서 레지스트리 로드 실패

- 리소스 누락: `RegistryLoader.LoadError.resourceURLNotFound`
  - Xcode 리소스에 `shared/*.json`이 포함되었는지 확인
- 디코드 실패: `RegistryLoader.LoadError.decodeFailed`
  - JSON 문법/필드 타입 불일치 확인

### 6.2 backend에서 레지스트리 파일을 못 찾음

`registry_loader.resolve_registry_path()`가 여러 후보 경로를 탐색한 뒤 실패할 수 있습니다.

- source 모드: repo 루트에 `shared/`가 존재해야 함
- bundled 모드: Nuitka dist에 `shared/*.json`이 포함되어야 함
  - 빌드 스크립트: `scripts/build/compile-nuitka-binary.sh`

---

## 7. 변경 가이드 (운영 관점)

레지스트리는 검색 동작을 좌우하는 계약(Contract)입니다. 스키마/키 변경은 "문서 수정"이 아니라 "기능 변경"으로 취급합니다.

### 7.1 안전한 변경 순서 (권장)

1) 새 키/연산자를 "추가" 형태로 먼저 넣습니다. (기존 키 삭제/rename은 뒤로 미룸)
2) Backend 로더/변환기에서 새 키를 해석 가능하도록 맞춥니다.
3) macOS UI(컴포저)에서 새 키를 노출하거나, 기존 노출을 새 키로 전환합니다.
4) 충분한 기간 동안 `legacy_keys`를 유지한 뒤, 실제 제거를 고려합니다.

### 7.2 호환성 원칙

- `propertyKey` rename은 가급적 피하고, 필요한 경우 `legacy_keys`로 호환 경로를 제공
- `$version`은 "구조/의미"가 바뀔 때 업데이트 권장 (semver 권장)
- UI 라벨/설명 변경은 비교적 안전하지만, `type`/`operators`/SQL 변환 규칙 변경은 기능에 직접 영향

---

## 8. 검증 절차 (변경 후 체크리스트)

### 8.1 정적 검증

- JSON 문법/포맷이 올바른지 (트레일링 콤마, 따옴표 누락 등)
- `$kind`, `$version`이 기대값인지
- `system_property_registry.json`
  - 새 `propertyKey`가 `categories`에 등록되어 있는지
  - `type`이 정의된 타입 키인지
- `property_condition_registry.json`
  - 새 operator `code`가 정의되어 있는지
  - 허용 타입(`property_types`)에 operator가 연결되어 있는지

### 8.2 런타임 검증(권장)

- macOS: 번들 리소스 로딩이 성공하는지 확인
  - 실패 시: `RegistryLoader.LoadError.*` 에러를 우선 확인
- Backend:
  - source 모드에서 repo 루트 `shared/` 경로를 제대로 찾는지
  - bundled 모드에서 Nuitka dist에 데이터 파일이 포함되는지

### 8.3 기능 검증(권장)

- UI 컴포저에서 새 속성/연산자가 보이는지
- 자연어 쿼리 -> 조건 변환에서 새 키가 생성되는지 (LLM 프롬프트/alias 영향)
- 실제 SQL 변환 및 결과가 기대 동작인지
