---
name: pr-review
description: 변경 diff/PR을 품질, 보안, 테스트, 리스크 관점으로 구조화해서 리뷰합니다.
compatibility: opencode
metadata:
  workflow: review
  output: review
---

이 스킬은 PR(또는 로컬 diff)을 빠르게 리뷰하고 "리뷰 코멘트를 바로 남길 수 있는 형태"로 정리하는 워크플로우입니다.

## 목표

- Blocker/High/Medium/Low/Nit로 우선순위 분류
- 문제 지적만 하지 않고, 가능하면 대안/패치 방향까지 제안
- 테스트/롤백/리스크를 명확히 적는다

## 워크플로우

1) 의도 파악

- PR 설명/이슈 링크가 있으면 먼저 읽고, 없으면 diff에서 목적을 1-2문장으로 요약한다.

2) 변경 범위 요약

- 변경 파일/모듈을 기준으로 기능적 영향 범위를 나눈다.
- API/데이터 모델/마이그레이션/UX 변경 여부를 체크한다.

3) 체크리스트 기반 리뷰

- Correctness: 경계 조건, 에러 처리, nil/optional, 동시성, 상태 불일치
- Security: 입력 검증, authz/authn, 시크릿 노출, 경로/SQL 인젝션, 권한
- Performance: N+1, 불필요한 I/O, 캐시/배치, UI 렌더링 비용
- Maintainability: 책임 분리, 네이밍, 중복, 과도한 추상화
- Tests: 회귀 테스트/스냅샷/통합 테스트, 실패 시 디버깅 가능성
- Docs/UX: 사용자 영향, 문서/가이드 업데이트 필요성

4) 코멘트 작성

- 각 코멘트는 "문제" + "왜 문제인지" + "대안"을 포함한다.
- 파일 경로/식별자(함수/타입/엔드포인트)를 같이 적는다.

5) 검증/리스크

- 변경으로 인해 깨질 수 있는 플로우를 2-3개 나열한다.
- 필요한 테스트/수동 QA를 제안한다.

## 출력 형식

- TL;DR 3줄
- Findings: Blocker/High/Medium/Low/Nit 순서로 항목화
- Tests/QA: 어떤 커맨드/플로우를 확인해야 하는지
- Risk: 롤백/플래그/마이그레이션 주의점(있으면)
