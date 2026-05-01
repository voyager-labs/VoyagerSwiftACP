# META AGENTS

## OVERVIEW

이 디렉토리는 레포 운영 규칙(SSOT/TSV/스키마/네이밍)을 정의합니다.

## WHERE TO LOOK

| 주제        | 문서                        | 노트                                          |
| ----------- | --------------------------- | --------------------------------------------- |
| META 진입점 | `META/README.md`            | 운영 원칙 요약 + 문서 목록                    |
| TSV 규칙    | `META/tsv_rules.md`         | 빈 행 금지, 컬럼 수 고정, `-`/`TBD`, `<<AI>>` |
| 스키마 포맷 | `META/schema_format.md`     | `required`만 사용, `ref`로 참조 관계 기술     |
| 네이밍      | `META/naming_convention.md` | 폴더/파일 네이밍 룰                           |

## CONVENTIONS

- META 문서는 "규칙의 정본"만 둡니다.
    - 원칙/정의/예시를 여기에 고정
    - 반복되는 설명은 루트 `README.md`나 섹션 `index.md`에는 최소만

## ANTI-PATTERNS

- 규칙을 여러 파일에 중복 정의하지 않기(업데이트 시 불일치가 생김)
- TSV 규칙을 예외로 두고 데이터 파일에만 암묵적으로 적용하지 않기(반드시 문서로 남기기)
