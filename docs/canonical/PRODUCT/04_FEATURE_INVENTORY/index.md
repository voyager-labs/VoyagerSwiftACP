# FEATURE_INVENTORY

Voyager의 기능/인터랙션 인벤토리를 표 형태(TSV)로 관리합니다.

## 테이블

- FEATURE_CATEGORIES
    - 목적: 기능 카테고리 정의(표시 순서/상태 포함)
    - PK: `category_key`
    - 파일: `PRODUCT/04_FEATURE_INVENTORY/FEATURE_CATEGORIES/data.tsv`,
      `PRODUCT/04_FEATURE_INVENTORY/FEATURE_CATEGORIES/schema.json`
- FEATURES
    - 목적: 기능 단위 인벤토리(릴리즈 단계/한 줄 설명/권한 메타데이터)
    - PK: `feature_id`
    - 주요 참조:
        - `category_key` -> FEATURE_CATEGORIES.category_key
        - `entitlement_key` -> 기능 사용을 unlock하는 제품 권한 키
    - 파일: `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`,
      `PRODUCT/04_FEATURE_INVENTORY/FEATURES/schema.json`
- INTERACTIONS
    - 목적: UI에서 호출되는 명령/입력 등 인터랙션 인벤토리
    - PK: `interaction_id`
    - 주요 참조:
        - `feature_id` -> FEATURES.feature_id
        - `category_key` -> FEATURE_CATEGORIES.category_key
    - 파일: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`,
      `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/schema.json`

## 인터랙션 키

- 유즈케이스 문서(예: `PRODUCT/06_USE_CASES/`)의 Happy Path 테이블에서 `Invoked Interaction`은
  `INTERACTIONS.interaction_id`를 사용합니다.

## UI 참조 키

- UI 영역은 `PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv`의 `structure_key`로
  참조합니다.
    - FEATURES.related_ui
    - INTERACTIONS.related_region

## 권한 메타데이터

- 기능별 사용 권한은 `FEATURES.entitlement_key`에 기록합니다.
- 가격/패키징 정책의 기준 claim은 `BUSINESS/05_business_model_and_pricing.md`가 유지합니다.

## 작성/변경 규칙

- TSV는 빈 행 없이 고정 컬럼 수를 유지하고, 결측은 `-`/`TBD`로 표기합니다.
