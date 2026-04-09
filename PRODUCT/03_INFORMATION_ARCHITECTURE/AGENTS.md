# INFORMATION_ARCHITECTURE AGENTS

## OVERVIEW

UI 구조/메뉴/오브젝트 키를 TSV로 SSOT 관리합니다.

## WHERE TO LOOK

| 작업             | 위치                                                            | 노트                                         |
| ---------------- | --------------------------------------------------------------- | -------------------------------------------- |
| 섹션 진입점      | `PRODUCT/03_INFORMATION_ARCHITECTURE/index.md`                  | 테이블 목적/PK/관계 요약                     |
| 메뉴 트리        | `PRODUCT/03_INFORMATION_ARCHITECTURE/MENUS/data.tsv`            | PK: `menu_node_id`, parent는 `-`로 루트 표현 |
| 메뉴 스키마      | `PRODUCT/03_INFORMATION_ARCHITECTURE/MENUS/schema.json`         | `required` 중심, `ref`로 self-reference      |
| 윈도우/영역 구조 | `PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv` | PK: `structure_key` (기능/인터랙션에서 참조) |
| 오브젝트 사전    | `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv`          | PK: `key`                                    |

## CONVENTIONS

- `WINDOW_STRUCTURE.structure_key`는 다른 테이블에서 UI 참조 키로 사용됨
    - `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`의 `related_ui`
    - `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`의 `related_region`

## ANTI-PATTERNS

- TSV에서 섹션 구분을 빈 줄로 표현하지 않기(규칙은 `META/tsv_rules.md`)
- `structure_key`를 사람 라벨로 대체하지 않기(참조 안정성 깨짐)
