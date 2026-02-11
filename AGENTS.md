# PROJECT KNOWLEDGE BASE

**Generated:** 2026-02-09 14:48:44 KST
**Commit:** c9cdf37
**Branch:** main

## OVERVIEW

Voyager 앱의 기획/문서 자료를 GitHub SSOT로 운영하는 레포입니다. 문서는 Markdown, 표/인벤토리는 `data.tsv` + `schema.json`으로 관리합니다.

## STRUCTURE

```text
./
├── README.md                      # 게이트웨이(진입 링크)
├── META/                          # 운영/포맷 규칙
├── 01_PRODUCT_THESIS/             # 제품 가설/문제/핵심 가치
├── 02_USER_PERSONA/               # 페르소나
├── 03_INFORMATION_ARCHITECTURE/   # IA 테이블(MENUS/WINDOW_STRUCTURE/OBJECTS)
├── 04_FEATURE_INVENTORY/          # 기능/인터랙션 인벤토리 테이블
├── 05_USE_CASES/                  # 유즈케이스(테이블 기반)
└── .agents/                       # 로컬 검증/조회 스크립트(스킬)
```

## WHERE TO LOOK

| 작업 | 위치 | 노트 |
|------|------|------|
| 레포 운영 규칙 확인 | `META/README.md` | 규칙은 여기로 모음 |
| TSV 작성 규칙 | `META/tsv_rules.md` | `-`/`TBD`, 빈 행 금지, 컬럼 수 고정 |
| schema.json 포맷 | `META/schema_format.md` | `required`만 사용(= nullable 없음). `-`는 null, `TBD`는 작성 필요 |
| IA(UI 구조/메뉴) 편집 | `03_INFORMATION_ARCHITECTURE/index.md` | `WINDOW_STRUCTURE.structure_key`는 참조 키 |
| 기능/인터랙션 편집 | `04_FEATURE_INVENTORY/index.md` | FEATURES/INTERACTIONS에서 다른 문서로 확장 예정 |
| 유즈케이스 흐름 확인 | `05_USE_CASES/index.md` | PREV/NEXT 내비, Invoked Interaction/UISurface 컬럼 |
| 특정 feature_id 검증 | `.agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/SKILL.md` | 빠른 lookup/정합성 체크 |

## CONVENTIONS (THIS REPO)

- **PR-first**: 의미 있는 변경은 PR로 남기고 리뷰/추적(blame)을 전제로 함
- **링크는 상대경로**: 이동/포크에도 깨지지 않게 파일 기준 상대경로 사용
- **TSV는 사람+머신 SSOT**: GitHub에서 TSV를 그대로 읽고 리뷰하는 것을 전제로 함
  - 빈 행 금지
  - 헤더 포함, 모든 행은 동일한 컬럼 수 유지
  - 값 없음/해당 없음: `-`
  - 아직 작성 못함: `TBD`
  - AI 초안 표시(셀 맨 앞): `<<AI>> `
- **schema.json**: `required`만 사용(= `nullable` 없음)
  - `-`는 `null_values`(기본값)로 취급
  - `TBD`는 작성해야 하는 값으로 취급(= required에서도 허용)
  - 단, `primary_key` 컬럼에는 `TBD`를 사용하지 않음
  - 참조는 `ref` 메타로 기술

## ANTI-PATTERNS (THIS REPO)

- TSV에 **빈 행/구분용 줄**을 넣어 섹션을 표현하지 않기
- TSV 셀에 **멀티라인(줄바꿈)** 넣지 않기
- TSV에서 null 의미로 `NULL` 같은 문자열을 쓰지 않기(표준은 `-`, `TBD`)
- 링크를 절대경로/외부 도구 전용 포맷으로 쓰지 않기(상대경로 유지)

## AI AGENT WORKING RULES (SEARCH / ANALYZE)

이 레포는 문서 SSOT이며, 대부분의 질문은 **레포 내부 파일만**으로 답을 낼 수 있습니다.

- **기본 조사 범위는 레포 내부**: 사용자가 URL/외부 레포/외부 라이브러리를 명시하지 않으면 웹 검색/외부 레퍼런스 조회를 하지 않습니다.
- **외부 소스 여부를 묻지 않기**: "외부도 찾아볼까요?" 같은 확인 질문은 기본적으로 하지 않습니다. 내부 자료만으로 진행하고, 외부가 필요/유익한 경우에만 *옵션*으로 제안합니다.
- **불필요한 CLI 검색 금지**: 레포 탐색/검색은 OpenCode의 전용 도구(Glob/Grep/AST-grep/Read)를 우선 사용합니다. Bash로 `rg`/`grep`/`find`를 돌려 결과를 긁는 방식은 피합니다.
- **스코프를 좁게 유지**: 사용자가 특정 문서/디렉토리를 지목하면(예: `04_FEATURE_INVENTORY/`) 해당 범위부터 조사하고, 필요할 때만 점진적으로 확장합니다.
- **[search-mode]/[analyze-mode] 해석**: "검색을 많이" 하라는 요청은 *내부 자료에서의 다각도 검색*을 의미합니다. 외부 조사까지 자동 확장하지 않습니다.

## COMMANDS

```bash
# 특정 feature_id를 FEATURES/INTERACTIONS/WINDOW_STRUCTURE 기준으로 빠르게 점검
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/check_feature.py FMW-001

# 다른 레포에서 이 레포를 subtree로 벤더링(소비자 레포에서 실행)
git remote add -f voyager-docs git@github.com:voyager-labs/voyager-documentation.git
git subtree add --prefix=docs/voyager voyager-docs main --squash
git subtree pull --prefix=docs/voyager voyager-docs main --squash
```

## NOTES

- `PRODUCT/`는 현재 비어 있음(레거시 자리). 신규 문서는 01~05 및 META 아래에 추가.
- `.agents/`는 스킬/스크립트 묶음이라 파일 수가 많음. 목적 없이 대규모 변경하지 않기.
