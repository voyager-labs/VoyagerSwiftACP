# META

이 디렉토리는 이 레포지토리를 **SSOT로 운영하기 위한 규칙/가이드**를 모아둡니다.

## 운영 원칙 (요약)

- **SSOT는 Git에 둔다**: 편집은 이 레포에서만 하고, Google Drive는 편집 채널로 사용하지 않습니다.
- **PR 우선(PR-first)**: 의미 있는 변경은 PR로 리뷰/추적 가능하게 남깁니다.
- **링크 규칙**: 레포 내부 참조는 상대경로 링크를 우선 사용합니다.
- **TSV는 사람+머신 SSOT**: 표는 GitHub에서 TSV를 그대로 읽고 리뷰하는 것을 전제로 합니다.
    - 빈 행 제거
    - 모든 행은 헤더와 동일한 컬럼 수 유지
    - 값 없음/해당 없음: `-`
    - 아직 작성 못함: `TBD`
    - AI 초안 표시(셀 맨 앞): `<<AI>>`
- **사용자 노출 UI 문구 예시는 영어를 기본으로 둡니다**: Voyager는 미국 대상 글로벌 앱으로 간주합니다.
    - 사용자에게 실제로 보이는 status name, button copy, label, CTA 예시는 기본적으로 영어로 작성합니다.
    - 한국어는 설명 문장에는 사용할 수 있지만, 사용자 노출 UI 라벨 예시에는 쓰지 않습니다.

## 문서 목록

- TSV 규칙: `META/tsv_rules.md`
- 스키마 포맷(확장): `META/schema_format.md`
- 네이밍 규칙: `META/naming_convention.md`
- FEATURE_SPECS 작성 규칙: `META/feature_specs_writing.md`
