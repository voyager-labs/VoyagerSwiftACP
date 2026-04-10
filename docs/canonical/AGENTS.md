# PROJECT KNOWLEDGE BASE

**Generated:** 2026-02-09 14:48:44 KST

## OVERVIEW

Voyager 문서를 GitHub SSOT로 운영하는 레포입니다. 문서는 Markdown, 표/인벤토리는 `data.tsv` +
`schema.json`으로 관리합니다.

## STRUCTURE

```text
./
├── README.md                      # 게이트웨이(진입 링크)
├── META/                          # SSOT 운영/포맷 규칙
├── PRODUCT/                       # 제품 기획/스펙/유즈케이스
│   ├── 01_PRODUCT_THESIS/         # 제품 가설/문제/핵심 가치
│   ├── 02_USER_PERSONA/           # 페르소나
│   ├── 03_INFORMATION_ARCHITECTURE/ # IA 테이블(MENUS/WINDOW_STRUCTURE/OBJECTS)
│   ├── 04_FEATURE_INVENTORY/      # 기능/인터랙션 인벤토리 테이블
│   ├── 05_FEATURE_SPECS/          # 인터랙션 기반 기능 스펙 문서
│   ├── 06_USE_CASES/              # 유즈케이스(테이블 기반)
│   └── LINEAR_ISSUE_DRAFTS/       # Linear 이슈 초안/정리
├── BRANDING/                      # 브랜딩/메시징(추가 예정)
├── GROWTH/                        # 그로스/채널/실험(추가 예정)
└── .agents/                       # 로컬 검증/조회 스크립트(스킬)
```

## WHERE TO LOOK

| 작업                  | 위치                                                                                  | 노트                                       |
| --------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------ |
| 레포 운영 규칙 확인   | `META/README.md`                                                                      | 규칙은 여기로 모음                         |
| TSV 작성 규칙         | `META/tsv_rules.md`                                                                   | `-`/`TBD`, 빈 행 금지, 컬럼 수 고정        |
| schema.json 포맷      | `META/schema_format.md`                                                               | `required` 중심, `ref`로 참조              |
| 제품 기획 진입점      | `PRODUCT/01_PRODUCT_THESIS/00_index.md`                                               | TL;DR/Problem/Target/Pillar/Core flow      |
| 페르소나 확인         | `PRODUCT/02_USER_PERSONA/00_index.md`                                                 | Alex/Eric/Mia                              |
| IA(UI 구조/메뉴) 편집 | `PRODUCT/03_INFORMATION_ARCHITECTURE/index.md`                                        | `WINDOW_STRUCTURE.structure_key`는 참조 키 |
| 기능/인터랙션 편집    | `PRODUCT/04_FEATURE_INVENTORY/index.md`                                               | FEATURES/INTERACTIONS 테이블               |
| 기능 스펙 확인/편집   | `PRODUCT/05_FEATURE_SPECS/index.md`                                                   | interaction_id 기반 스펙                   |
| 유즈케이스 흐름 확인  | `PRODUCT/06_USE_CASES/index.md`                                                       | PREV/NEXT 내비                             |
| 특정 feature_id 검증  | `.agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/SKILL.md` | 빠른 lookup/정합성 체크                    |

## CONVENTIONS (THIS REPO)

- **PR-first**: 의미 있는 변경은 PR로 남기고 리뷰/추적(blame)을 전제로 함
- **링크는 상대경로**: 이동/포크에도 깨지지 않게 파일 기준 상대경로 사용
- **TSV는 사람+머신 SSOT**: GitHub에서 TSV를 그대로 읽고 리뷰하는 것을 전제로 함
    - 빈 행 금지
    - 헤더 포함, 모든 행은 동일한 컬럼 수 유지
    - 값 없음/해당 없음: `-`
    - 아직 작성 못함: `TBD`
    - AI 초안 표시(셀 맨 앞): `<<AI>>`
- **schema.json**: `required`만 사용(= `nullable` 없음)
    - `-`는 `null_values`로 취급
    - `TBD`는 작성해야 하는 값으로 취급(= required에서도 허용)
    - 단, `primary_key` 컬럼에는 `TBD`를 사용하지 않음
    - 참조는 `ref` 메타로 기술

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

- `BRANDING/`, `GROWTH/`는 도메인 분리를 위해 추가된 상위 폴더입니다(내용은 점진적으로 채웁니다).
- `.agents/`는 스킬/스크립트 묶음이라 파일 수가 많음. 목적 없이 대규모 변경하지 않기.
