---
updated: 2026-05-13
status: canonical
---

# Business Model and Pricing

## Revenue Model

운영 모델은 지속 무료 플랜이 아니라, 낮은 유료 진입가의 `Core License`에서 시작해 구독형 반복 매출로 확대하는 구조다. 재무 모델의 모든 사용자는 먼저 `$5 Core License`를 구매한 유료 고객으로 본다.

| Revenue component | Product / charge item |           Price | Billing        | Role                                                                 |
| ----------------- | --------------------- | --------------: | -------------- | -------------------------------------------------------------------- |
| 1회 구매 라이선스 | Core License          | $5/사용자 + tax | 1회 결제       | 핵심 파일 관리 기능 잠금 해제, 초기 결제 의향과 가격 저항 검증       |
| 구독 플랜         | Basic                 |     $5/월 + tax | 월 구독        | 사용자의 기존 AI 구독 또는 API 키를 Voyager 파일 맥락에 연결         |
| 구독 플랜         | Go                    |    $10/월 + tax | 월 구독        | 자사 제공 클라우드 AI 모델을 통해 API 키 없이 AI 파일 관리 경험 제공 |
| 유료 애드온       | Automation            |    +$5/월 + tax | 월 구독 애드온 | 콜렉션 대상 트리거 기반 작업 실행 자동화 제공                        |

연간 결제를 제공하는 경우 Basic과 Automation은 $48/년, Go는 $96/년으로 두며 월간 가격 대비 20% 할인을 적용한다.

## Pricing Strategy

- 초기 사업화는 Core License 1회 결제, Basic/Go 구독, Automation 애드온 업셀의 순서로 검증한다.
- Core License는 구독 플랜명이 아니라 첫 유료 진입 상품이다.
- 무료 사용량 확대보다 초기 유료 결제 의향 검증에 집중한다.
- 2026-06 paid launch에서는 누적 대기열 281명을 초기 Core License 전환 분모로 사용하고, base case 전환율은 8%로 둔다.
- 2026-09부터 직접 Core buyer acquisition을 시작하는 base case를 사용한다.
- 기존 파일 관리 도구의 $20-$40 내외 가격대보다 낮은 진입 가격으로 초기 구매 저항을 낮춘다.
- Basic은 Voyager가 AI 모델 사용량을 재판매하는 구조가 아니라, 사용자가 보유한 AI 구독 또는 API provider를 Voyager 파일 맥락에 연결하는 workflow layer로 표현한다.
- Go는 Voyager가 hosted AI 또는 credit plan을 실제로 제공할 때만 사용한다.
- Automation은 반복 업무 비중이 높고 자동화 효용을 명확히 체감하는 사용자층에 업셀한다.

## Tax and Checkout Policy

- 가격 표시는 tax-exclusive 기준으로 운영한다.
- 외부 가격 표기에서는 `$5 + tax`처럼 세전 기준을 명확히 표시한다.
- 세금은 checkout에서 별도 계산·가산한다.
- 세금 포함 총액을 $5에 맞추는 표현은 사용하지 않는다.

## Trial Policy

- 지속 `Free plan`은 만들지 않는다.
- KPI/재무 시나리오에는 free trial, free tier, free user signup을 포함하지 않는다.
- 무료 체험을 제공하더라도 기간 제한 trial로 표현한다.
- 장기 기본값은 `14-day Full Suite Trial`이다.
- trial 범위는 Core app access, Basic/Codex-provider connector, Automation을 함께 포함한다.
- AI 모델 사용량은 기본 포함하지 않는다. 사용자는 본인 Codex 계정 또는 API key를 연결한다.
- hosted AI를 제공하는 경우에만 Go 또는 credit plan 문구로 분리한다.

## Source Metadata

| Claim group          | Source                    | Link                                                                                                                     | Accessed   |
| -------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ---------- |
| KPI/financial model  | KPI 시나리오 Google Sheet | <https://docs.google.com/spreadsheets/d/1tycxZVzEsjNCqiDC8-vUWoaz5x5HHkiAAqACt8CenCI/edit?gid=1628028603#gid=1628028603> | 2026-05-13 |
| Burn/runway scenario | Burn Rate & Runway Model  | <https://docs.google.com/spreadsheets/d/1Xt2XmugGbPPKq28JWZsKnv2aaoHQZa7AKKWwS1jNU5I/edit?gid=0#gid=0>                   | 2026-05-13 |
