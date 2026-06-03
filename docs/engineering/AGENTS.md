# Engineering Docs AGENTS

## Scope

`docs/engineering/`은 Voyager 앱 레포의 active 기술 지식 베이스다.

Engineering 문서는 `docs/canonical/PRODUCT/**`에 정의된 제품 동작을 이 레포가 어떻게 구현, 검증, 운영하는지 설명한다.

## Directory model

- `docs/engineering/<CATEGORY>/`를 기본 소유 단위로 사용한다.
- `<CATEGORY>`는 `PRODUCT/04_FEATURE_INVENTORY/FEATURE_CATEGORIES.category_key`와 일치해야 한다.
- Category 문서는 여러 `feature_id`와 `interaction_id`를 함께 참조할 수 있다.
- `PRODUCT/05_FEATURE_SPECS/**`를 interaction-level engineering 파일로 미러링하지 않는다.

각 category는 필요할 때 아래 하위 디렉터리를 사용한다.

- `concerns/` — category 안에서 반복되는 durable engineering 관심사 지도.
- `flows/` — 현재 유효한 런타임 시퀀스와 cross-boundary 동작.
- `decisions/` — ADR 스타일의 누적 의사결정 기록.
- `implementation/` — 현재 코드 경계, 패키지 topology, 테스트 topology, 검증 노트.

한 product category가 단독으로 소유하지 않는 공통 내용은 `docs/engineering/shared/` 또는 `docs/engineering/platform/<platform>/`에 둔다.

## Required traceability

Index가 아닌 모든 engineering 문서는 `Product traceability` 섹션을 포함해야 한다.

- Category key
- Primary features, 해당 시
- Related features, 해당 시
- Interaction IDs, 해당 시
- Canonical contract, flow, feature spec, IA row 링크

Canonical ID와 경로를 사용하고, `docs/canonical/PRODUCT/**`의 긴 acceptance criteria를 재서술하지 않는다.

## Decision records

`decisions/` 아래 파일은 누적 기록이다.

- `0001-auth-session-storage.md` 같은 번호 기반 파일명을 사용한다.
- `Status`, `Date`, `Context`, `Decision`, `Consequences`, `Alternatives considered`, `Product traceability`를 포함한다.
- accepted history를 조용히 삭제하거나 덮어쓰지 않는다.
- 결정이 바뀌면 이전 record를 `Superseded`로 표시하고 새 record로 링크한다.

## Legacy policy

- `docs/legacy/**`는 명시적 감사/이관 작업이 아닌 한 reference-only다.
- legacy 파일을 확장하기보다 유효한 내용을 category-owned engineering 문서로 추출한다.

## Verification

- Active engineering 문서가 참조하는 canonical path와 code path가 존재하는지 확인한다.
- 링크는 repository-local 상대 링크를 사용한다.
- docs-only 변경에는 build가 필요하지 않으며, 링크/경로 검증 결과를 보고한다.
