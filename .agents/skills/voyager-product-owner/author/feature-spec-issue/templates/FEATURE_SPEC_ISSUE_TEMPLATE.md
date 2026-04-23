## Pre-work contract

### Summary

> 이 이슈가 어떤 사용자 행동, surface, 또는 제품 계약을 고정하려는지 1~3문장으로 적는다.
> 상위 이슈의 전체 맥락을 길게 다시 설명하기보다, 이번 docs-first 이슈가 무엇을 먼저 잠그는지 바로 드러나게 쓴다.
> 구현 방법, 내부 구조, 기술 선택이 아니라 제품 판단의 중심을 적는다.

-

### Candidate capability

> 이번 스펙 정리를 통해 사용자 또는 시스템이 어떤 능력을 가져야 하는지 적는다.
> 구현 세부보다 user-visible behavior와 product contract 언어를 우선한다.
> 후보 capability와 이번 이슈에서 사실상 고정할 capability가 섞여 있다면 그 차이가 드러나게 쓴다.

-
-
-

### Product behavior to define

> 디자인 전에 정리되어야 하는 핵심 제품 판단을 적는다.
> 문서 목록이 아니라, 디자인과 개발이 같은 기준으로 움직이기 위해 필요한 behavior contract를 요약하는 자리다.

#### Reference products / patterns

> 단순 서비스명 나열이 아니라, 어떤 surface / interaction / information model을 참고하는지와 무엇은 가져오지 않을지를 함께 남긴다.
> 가능하면 각 `Reference`에는 실제로 연 페이지를 바로 열 수 있도록 Markdown 링크를 넣는다.
> 우선순위는 공식 제품 사이트 / 공식 도움말 / 공식 데모이며, Pinterest / Mobbin / Dribbble / Behance는 시각 참고가 필요할 때만 보조적으로 쓴다.

| Reference | What to borrow | What not to borrow |
| --------- | -------------- | ------------------ |
|           |                |                    |
|           |                |                    |

#### Core flow

> 시작 조건, 핵심 전개, 종료 결과를 3~5줄 안에서 적는다.
> happy path를 기본으로 하되, 이 기능의 성격을 바꾸는 핵심 분기점이 있으면 함께 적는다.

-
-
-

#### Main states

> 최소한 normal / loading / empty / error / unavailable 중 필요한 상태를 적는다.
> 상태 이름만 적지 말고, 그 상태에서 사용자에게 무엇이 보이고 무엇이 가능하거나 막히는지까지 남긴다.

| State | What the user sees / can do | Entry / recovery notes |
| ----- | --------------------------- | ---------------------- |
|       |                             |                        |
|       |                             |                        |
|       |                             |                        |

### Open questions

> 아직 제품 판단이 끝나지 않은 항목만 적는다.
> 실제로 남아 있는 판단 공백만 남기고, blocker인지 follow-up인지 드러나게 적는다.

-

## Handoff

> downstream issue가 바로 이어받을 수 있는 현재 판단, 남겨둘 쟁점, 주의할 경계를 짧게 정리한다.

### Design issue

- Current direction to carry forward:
- Design-owned details:
- Open points / watchouts:

### Development issue

- Current direction to carry forward:
- Defer to technical spec / implementation:
- Open points / watchouts:
