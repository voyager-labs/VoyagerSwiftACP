# voyager-feature-inventory-checker AGENTS

## OVERVIEW

`feature_id`(예: `FMW-001`) 기준으로 FEATURES/INTERACTIONS/WINDOW_STRUCTURE를 교차 조회해 정합성을 빠르게 확인합니다.

## WHERE TO LOOK

| 항목 | 위치 | 노트 |
|------|------|------|
| 스킬 설명/사용법 | `.agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/SKILL.md` | 체크 범위 요약 |
| deterministic 체크 | `.agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/check_feature.py` | stdlib only |
| polars 검색/조회 | `.agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/vfi.py` | venv auto-bootstrap |
| 스키마 마이그레이션 | `.agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/migrate_inventory_schema_v2.py` | v2 헤더 추가 |

## INPUTS

- `feature_id` 또는 제목 부분 문자열(옵션: `--match contains`)

## COMMANDS

```bash
# venv 생성 + polars 설치(1회)
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/vfi.py setup

# feature 조회/검색
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/vfi.py show FMW-001
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/vfi.py search "Quick Look" --scope interactions

# 정합성 체크(경고/검증)
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/check_feature.py FMW-001

# v2 스키마 마이그레이션
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/migrate_inventory_schema_v2.py
```

## OUTPUTS

- FEATURES row 요약
- 카테고리/참조(UI) 일관성 경고
- 관련 INTERACTIONS 목록
