# Engineering Docs

Voyager 앱 레포의 active engineering 문서 진입점이다.

## Principles

- 제품 동작과 UX 정책은 `../canonical/PRODUCT/`에 둔다.
- Engineering 문서는 구현, 런타임 흐름, 기술 결정, 테스트 topology, 운영상 결과를 설명한다.
- Category 디렉터리는 canonical `feature_category` key를 사용한다.
- Interaction-level product spec은 링크하고, engineering 문서로 미러링하지 않는다.

## Product categories

- [FMW](./FMW/index.md) — File Manager Window
- [EVM](./EVM/index.md) — Entry View Management
- [EOP](./EOP/index.md) — Entry Operations
- [EIX](./EIX/index.md) — Entry Indexing
- [RCL](./RCL/index.md) — Retrieval Collection
- [CEP](./CEP/index.md) — Custom Entry Properties
- [CBW](./CBW/index.md) — Chat-based Workflows
- [CTM](./CTM/index.md) — Content Tab Management
- [SET](./SET/index.md) — User Settings
- [CMP](./CMP/index.md) — Command Palette
- [ONB](./ONB/index.md) — Onboard
- [EAU](./EAU/index.md) — Entry Automation
- [ERL](./ERL/index.md) — Entry Relations
- [ATI](./ATI/index.md) — AI Tool Integration
- [UPR](./UPR/index.md) — User Profile
- [ESI](./ESI/index.md) — External Storage Integration
- [MFB](./MFB/index.md) — Modern File Browsing
- [ACM](./ACM/index.md) — Augmented Context Menu

## Shared engineering areas

- `shared/` — 여러 category에 걸치는 공통 기술 관심사.
- `platform/` — platform-level 구현 guidance.
