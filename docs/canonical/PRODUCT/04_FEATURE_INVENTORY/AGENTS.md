# FEATURE_INVENTORY AGENTS

## OVERVIEW

기능/인터랙션 인벤토리를 TSV로 SSOT 관리합니다.

## WHERE TO LOOK

| 작업 | 위치 | 노트 |
|------|------|------|
| 섹션 진입점 | `PRODUCT/04_FEATURE_INVENTORY/index.md` | 테이블 목적/관계 요약 |
| 기능 카테고리 | `PRODUCT/04_FEATURE_INVENTORY/FEATURE_CATEGORIES/data.tsv` | PK: `category_key` |
| 기능 인벤토리 | `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv` | PK: `feature_id` |
| 인터랙션 인벤토리 | `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv` | FEATURES/카테고리/UI 참조 포함 |
| UI 참조 키 | `PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv` | `structure_key`를 사용 |

## CONVENTIONS

- `FEATURES.category_key`는 `FEATURE_CATEGORIES.category_key`를 참조합니다.
- `INTERACTIONS.feature_id`는 `FEATURES.feature_id`를 참조합니다.
- `INTERACTIONS.category_key`는 `FEATURE_CATEGORIES.category_key`를 참조합니다.
- `INTERACTIONS.interaction_id`는 stable key이며, 다른 문서에서 참조할 때 사용합니다.
- UI 참조는 `structure_key`로 고정합니다.

## ANTI-PATTERNS

- 긴 AC/엣지케이스를 TSV 셀에 누적하지 않기(멀티라인 금지 + diff 가독성 저하)
- `feature_id`/`category_key` 같은 키를 제목/라벨로 대체하지 않기
