# INFORMATION_ARCHITECTURE

Voyager의 제품 문서 SSOT에서 **정보 구조(IA)** 를 표 형태(TSV)로 관리합니다.

## 테이블

- MENUS
  - 목적: 상단 메뉴/컨텍스트 메뉴 등 메뉴 트리 정의
  - PK: `menu_node_id`
  - 파일: `PRODUCT/03_INFORMATION_ARCHITECTURE/MENUS/data.tsv`, `PRODUCT/03_INFORMATION_ARCHITECTURE/MENUS/schema.json`
- WINDOW_STRUCTURE
  - 목적: 화면/윈도우의 UI 영역 구조(계층) 정의
  - PK: `structure_key`
  - 파일: `PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv`, `PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/schema.json`
- OBJECTS
  - 목적: 제품에서 다루는 오브젝트(개념/엔티티) 키 사전
  - PK: `key`
  - 파일: `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv`, `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/schema.json`

## 참조 관계

- `WINDOW_STRUCTURE.structure_key`는 기능/인터랙션에서 UI 참조 키로 사용됩니다.
  - `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`의 `related_ui`
  - `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`의 `related_region`

## 작성/변경 규칙

- TSV 작성 규칙은 `META/tsv_rules.md`를 따릅니다.
