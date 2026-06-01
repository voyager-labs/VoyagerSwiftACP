# Docs AGENTS

## Scope

`docs/`는 두 가지 문서 레인과 legacy reference를 가진다.

- `canonical/`: 문서 submodule이 제공하는 제품, 비즈니스, 웹사이트, 그로스 SSOT.
- `canonical/ENGINEERING/`: canonical submodule이 소유하는 active engineering 지식 베이스.
- `legacy/`: 재구성 이전 앱 문서를 감사/이관 전까지 보관하는 reference-only 영역.

## Rules

- active engineering 문서 작업은 `docs/canonical/ENGINEERING/**`에 작성한다.
- `docs/legacy/**`는 기본적으로 읽기 전용 reference로 취급한다. 레거시 페이지를 확장하기보다 유효한 내용을 `docs/canonical/ENGINEERING/**`로 이관한다.
- 새로운 기술 결정, 런타임 흐름, 구현 노트, 코드/테스트 topology 문서는 `docs/canonical/ENGINEERING/**`에 둔다.
- 제품 정책과 사용자-facing 기능 진실은 `docs/canonical/PRODUCT/**`에 둔다. Engineering 문서는 canonical 내용을 복제하지 않고 링크한다.
- 레거시 페이지를 이동하거나 대체하면 `docs/index.md`와 active 문서의 로컬 링크를 함께 갱신한다.

## Verification

- docs-only 변경은 상대 링크와 이동된 경로를 검증한다.
- 문서가 코드 경로를 언급하면 active guidance로 취급하기 전에 해당 경로가 여전히 존재하는지 확인한다.
