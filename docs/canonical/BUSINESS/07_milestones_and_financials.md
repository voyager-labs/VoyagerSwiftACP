---
updated: 2026-05-15
status: canonical
---

# Milestones and Financials

## Stage Plan

| Period            | Stage          | Goal                                                     |
| ----------------- | -------------- | -------------------------------------------------------- |
| 2026-06           | 출시·검증 준비 | 대기열 등록 관심 유저의 Core License 유료 전환 검증 준비 |
| 2026-07 ~ 2026-12 | 출시·검증      | Core License 구매와 Basic 추가 구독 검증                 |
| 2027-01 ~ 2027-12 | 성장           | Core License 구매자 유입을 늘려 유료 고객 기반 확대      |
| 2028-01 이후      | 확장           | 구독 매출 확대와 자동화 기반 락인 강화                   |

## Detailed Execution Milestones

| Period            | Stage                   | Goal                                                           |
| ----------------- | ----------------------- | -------------------------------------------------------------- |
| 2026-06           | 라이선스 판매 기반 구축 | Core License 판매 체계 구축 및 첫 유료 고객 확보               |
| 2026-07 ~ 2026-08 | MVP 공개 및 구독 검증   | AI 채팅 포함 MVP 공개 후 Basic 구독 전환 의향과 사용·결제 검증 |
| 2026-08 ~ 2026-09 | 사용·결제 지표 개선     | 활성화율, 리텐션, 결제 전환율 개선 및 유료 고객 확보           |
| 2026-09 ~ 2026-11 | 자동화 애드온 도입      | Automation의 지불의사, 사용 빈도, 추가 결제 전환율 검증        |
| 2026-08 ~ 2026-12 | Pre-seed 투자유치 추진  | 초기 매출과 사용·결제 지표 업데이트 기반 3억 원 투자유치 추진  |
| 2026-12 ~ 2027-03 | 상위 구독 모델 확장     | 자사 제공 AI 구독 모델 전환과 수익성 검증                      |
| 2026-04 ~ 2027-06 | 사용 사례 확산          | 파일 관리 자동화와 AI 워크플로 사례 콘텐츠화                   |
| 2027-05 ~ 2027-12 | Seed 라운드 준비        | MRR, 유지율, 애드온·상위 플랜 전환율 기반 Seed 투자유치 준비   |
| 2028-01 이후      | 미국 시장 진입 준비     | 미국 투자자 미팅, 현지 법인 설립, 진출 일정 검토               |

## License and Subscription Scenario

| Period  | Cumulative purchasers | Subscription rate | Subscribers |          MRR | Net revenue, license + subscription |
| ------- | --------------------: | ----------------: | ----------: | -----------: | ----------------------------------: |
| 2026-06 |                    22 |                 - |           - |            - |                            ₩143,264 |
| 2026-12 |                   597 |             15.2% |          91 |     ₩626,383 |                          ₩2,243,231 |
| 2027-06 |                 3,978 |             21.9% |         873 |   ₩7,031,585 |                         ₩19,168,991 |
| 2027-12 |                17,067 |             22.7% |       3,878 |  ₩33,660,318 |                         ₩76,817,552 |
| 2028-06 |                42,403 |             20.0% |       8,494 |  ₩76,292,621 |                        ₩163,710,661 |
| 2028-12 |                88,272 |             18.9% |      16,650 | ₩151,151,339 |                        ₩325,637,018 |

## Scenario Definitions

- `Cumulative purchasers`는 누적 Core License 구매자다.
- 모델은 free signup, free tier, free trial user를 포함하지 않는다.
- `MRR`은 월말 구독 반복매출만 의미하며 Core License 1회 매출은 제외한다.
- `Net revenue, license + subscription`은 Core License 1회 매출과 Basic/Go/Automation 구독 순매출을 합산한 월간 순매출이다.
- Product gross margin은 결제와 MoR 수수료 차감 후 80% base case를 둔다. AI/infra COGS는 별도 COGS 모델 연결 전까지 시나리오 가정으로 관리한다.

## ARPPU Assumptions

- Basic plan $5 비중: 85%.
- Automation plan $10 비중: 15%.
- 월 결제 한정 ARPPU: ₩8,625, 약 $5.75.
- 연간 결제 20% 할인 제공 시 결제 비중: 80%.
- 연간 결제 할인 반영 ARPPU: ₩8,115, 약 $5.41.

## Growth Assumptions

- 2026-06 paid launch는 2026-05 기준 누적 대기열 281명을 prelaunch stock으로 사용한다.
- base case는 prelaunch stock의 8%가 Core License로 전환한다고 본다.
- 2026-09부터 직접 Core buyer acquisition을 시작하며, base case CAC는 Core buyer 1명당 $25다.
- Raycast의 초기 DAU 성장 구간을 참고하되, marketing mode에서는 해당 성장률의 80%를 Core buyer 성장률 가정으로 사용한다.
- active user에서 WAU로의 환산 비율은 base case 40%다.
- 월 subscription churn은 초기 30%에서 후기 18%로 완화되는 시나리오를 사용한다.

## Scenario Assumptions

- `License and Subscription Scenario`를 Core License 결정 이후의 주 재무 시나리오로 사용한다.
- 계획 환율은 USD/KRW 1,480원을 기준으로 둔다. 다른 환율 가정을 사용할 경우 별도 표기한다.

## Source Metadata

| Claim group                       | Source                    | Link                                                                                                                     | Accessed   |
| --------------------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ---------- |
| License and subscription scenario | KPI 시나리오 Google Sheet | <https://docs.google.com/spreadsheets/d/1tycxZVzEsjNCqiDC8-vUWoaz5x5HHkiAAqACt8CenCI/edit?gid=1628028603#gid=1628028603> | 2026-05-13 |
| Funnel inputs                     | Voyager KPI Sheet         | <https://docs.google.com/spreadsheets/d/1R0nd0so_5Eg7o9aGQI560oy89WhWEb4w6m6K0fqbh5A/edit?gid=0#gid=0>                   | 2026-05-13 |
