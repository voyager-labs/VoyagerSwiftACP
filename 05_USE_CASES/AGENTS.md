# USE_CASES AGENTS

## OVERVIEW

유즈케이스를 문서로 유지하며, Happy Path 테이블에서 인터랙션/UISurface를 참조합니다.

## WHERE TO LOOK

| 작업 | 위치 | 노트 |
|------|------|------|
| 섹션 진입점 | `05_USE_CASES/index.md` | 유즈케이스 목록 |
| 템플릿 | `05_USE_CASES/templates.md` | 표 포맷 기준 |
| UC 흐름 | `05_USE_CASES/mvp.md` | UC04 역할 포함 |

## CONVENTIONS

- 문서 상단/하단에 PREV/NEXT 내비게이션 링크를 둡니다.
- Happy Path 테이블의 `Invoked Interaction` 컬럼은 `INT.*` 키를 사용합니다.
- `UI Surface`는 `WINDOW_STRUCTURE.structure_key`를 사용하거나, 임시로 사람이 읽는 라벨을 사용하되 이후 키로 정규화합니다.

## ANTI-PATTERNS

- PREV/NEXT를 빈 링크로 남기지 않기
- `Invoked Interaction`을 자유 텍스트로만 쓰고 키를 잃어버리지 않기(검색/정합성 검증이 어려워짐)
