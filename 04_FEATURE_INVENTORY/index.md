# FEATURE_INVENTORY

Voyager의 기능/인터랙션 인벤토리를 표 형태(TSV)로 관리합니다.

## 테이블

- FEATURE_CATEGORIES
  - 목적: 기능 카테고리 정의(표시 순서/상태 포함)
  - PK: `category_key`
  - 파일: `04_FEATURE_INVENTORY/FEATURE_CATEGORIES/data.tsv`, `04_FEATURE_INVENTORY/FEATURE_CATEGORIES/schema.json`
- FEATURES
  - 목적: 기능 단위 인벤토리(릴리즈 단계/상태/한 줄 설명)
  - PK: `feature_id`
  - 주요 참조:
    - `category_key` -> FEATURE_CATEGORIES.category_key
  - 파일: `04_FEATURE_INVENTORY/FEATURES/data.tsv`, `04_FEATURE_INVENTORY/FEATURES/schema.json`
- INTERACTIONS
  - 목적: UI에서 호출되는 명령/입력 등 인터랙션 인벤토리
  - PK: `interaction_id`
  - 주요 참조:
    - `feature_id` -> FEATURES.feature_id
    - `category_key` -> FEATURE_CATEGORIES.category_key
  - 파일: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`, `04_FEATURE_INVENTORY/INTERACTIONS/schema.json`

## 인터랙션 키

- 유즈케이스 문서(예: `06_USE_CASES/`)의 Happy Path 테이블에서 `Invoked Interaction`은 `INTERACTIONS.interaction_id`를 사용합니다.

## UI 참조 키

- UI 영역은 `03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv`의 `structure_key`로 참조합니다.
  - FEATURES.related_ui
  - INTERACTIONS.related_region

## 작성/변경 규칙

- TSV 작성 규칙은 `META/tsv_rules.md`를 따릅니다.
