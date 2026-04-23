# Example Feature-Spec PR Body

This example is based on the `main...voy-235` snapshot reviewed on 2026-04-20.
It is intentionally broader than an ideal single-issue PR, so it is useful as a reference for tone and paragraph shape, not as a claim that this branch is perfectly scoped for the template.

## Example Output

```md
<!-- Recommended PR title: `[VOY-XXX] {title}` -->

## Intent

Linear 이슈: [VOY-XXX](https://linear.app/...)

이 PR은 chat 기반 기능 스펙을 기존 CDA 분류에서 CBW 분류로 다시 묶고, 그에 맞는 interaction spec, category-level contract, flow, 카탈로그 참조를 함께 정리하기 위한 변경입니다. 이번 변경에서는 request lifecycle, request context, response resolution, provider/model selection, conversation session 다섯 범위를 사용자 흐름 기준으로 다시 나누고, 리뷰 기준점도 CBW 번들 중심으로 맞춥니다.

## Spec Delta

### CBW interaction spec 번들

기존 CDA 계열은 의도 해석 중심으로 쪼개져 있어서 현재 chat UX와 리뷰 단위가 잘 맞지 않았습니다. 이번 PR에서는 이를 `CBW-001`부터 `CBW-005`까지의 사용자 흐름 기준 번들로 다시 정리하고, 각 interaction spec과 category-level contract, flow 문서를 함께 맞췄습니다. 리뷰어는 개별 스펙 텍스트보다 어떤 사용자 흐름을 어떤 단위로 잠갔는지를 중심으로 보면 됩니다.

- 근거: `PRODUCT/04_FEATURE_INVENTORY/FEATURE_CATEGORIES/data.tsv`, `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`, `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`, `PRODUCT/05_FEATURE_SPECS/cbw/contracts/`, `PRODUCT/05_FEATURE_SPECS/cbw/flows/`
- 남겨둔 범위: execution-heavy intent와 LATER 범위는 이번 PR에서 닫지 않았습니다.
- 관련 ids / keys: `CBW`, `CBW-001`, `CBW-002`, `CBW-003`, `CBW-004`, `CBW-005`

### CBW contract / flow 번들

기존 CDA 시나리오 문서만으로는 요청 실행, provider/model 전환, session 복원처럼 여러 interaction에 걸친 공통 규칙을 한 번에 리뷰하기 어려웠습니다. 이번 PR에서는 category-level contract와 flow 문서를 추가해 request lifecycle, request context, provider/model selection, session continuity 규칙을 interaction spec 바깥의 공유 기준으로 끌어올렸습니다. 리뷰어는 개별 interaction 문장보다 어떤 규칙이 contract와 flow로 승격되었는지를 중심으로 보면 됩니다.

- 근거: `PRODUCT/05_FEATURE_SPECS/cbw/contracts/request_lifecycle.toml`, `PRODUCT/05_FEATURE_SPECS/cbw/contracts/request_context_contract.toml`, `PRODUCT/05_FEATURE_SPECS/cbw/contracts/provider_selection_contract.toml`, `PRODUCT/05_FEATURE_SPECS/cbw/contracts/model_selection_contract.toml`, `PRODUCT/05_FEATURE_SPECS/cbw/contracts/chat_session_contract.toml`, `PRODUCT/05_FEATURE_SPECS/cbw/flows/`
- 남겨둔 범위: execution-heavy intent나 tool-specific flow는 이번 PR에서 다루지 않았습니다.
- 관련 ids / keys: `request_lifecycle`, `request_context_contract`, `provider_selection_contract`, `model_selection_contract`, `chat_session_contract`, `contextual_chat_request_flow`, `chat_provider_model_selection_flow`, `request_context_management_flow`, `chat_session_restore_flow`

### CBW 카탈로그 정돈

카테고리 이름과 generated index가 여전히 CDA 구조를 기준으로 남아 있으면, 새 spec 번들과 inventory를 함께 읽을 때 리뷰 맥락이 쉽게 끊깁니다. 이번 PR에서는 `FEATURE_CATEGORIES`, `FEATURES`, `INTERACTIONS`, `PRODUCT/05_FEATURE_SPECS/index.md`를 CBW 기준으로 동기화해 파일 구조와 카탈로그가 같은 story를 가리키도록 정리했습니다. 리뷰어는 spec 파일만 보지 말고 카탈로그 명칭과 링크 구조가 새 번들과 일관되게 맞는지도 함께 보면 됩니다.

- 근거: `PRODUCT/04_FEATURE_INVENTORY/FEATURE_CATEGORIES/data.tsv`, `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`, `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- 남겨둔 범위: CBW 외 다른 category의 naming cleanup은 이번 PR에 포함하지 않았습니다.
- 관련 ids / keys: `CBW`, `FEATURE_CATEGORIES`, `FEATURES`, `INTERACTIONS`

## Validation Evidence

- `git log --oneline main..HEAD`로 PR narrative를 commit history 기준으로 정리했습니다.
- `git diff --stat main...HEAD`와 주요 diff를 기준으로 변경 축을 수동 리뷰했습니다.
- 자동 검증은 이 예시 작성 시점에는 실행하지 않았습니다.
```
