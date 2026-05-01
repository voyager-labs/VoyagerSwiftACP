# 네이밍 규칙

이 문서는 Voyager 문서 레포의 **폴더/파일 네이밍 규칙**만 정의합니다.

## 폴더 네이밍

- 기본: `CONSTANT_CASE` (대문자 + `_`)
    - 예: `03_INFORMATION_ARCHITECTURE/`, `04_FEATURE_INVENTORY/`
- 숫자 프리픽스가 필요한 경우(정렬 목적): `NN_CONSTANT_CASE/`
    - 예: `10_DESIGN/`

## 파일 네이밍

- 기본: `snake_case` + 확장자 소문자
    - 예: `core_flow.md`, `target_user.md`, `jobs_to_be_done.md`
- 고정 예외:
    - `README.md`: 대문자 유지(관습/표준)
    - `index.md`: 소문자(섹션 진입점/내비게이션용)
