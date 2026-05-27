---
description: "CodeGraph MCP 사이드카 다각도 평가 프레임워크 — 7개 각도로 도입 효과를 객관적으로 측정하여 Go/No-Go 판단."
alwaysApply: true
---

# CodeGraph 도입 평가 프레임워크

## 개요

CodeGraph MCP 사이드카 도입의 실제 효과를 7개 각도에서 객관적으로 측정한다.
평가 결과는 2주 후 Go/No-Go 판단의 근거로 사용한다.

## 평가 각도

### 1. 탐색 속도 (Exploration Speed)

- **정의**: 새 파일/모듈 이해에 소요되는 시간
- **Before (도입 전)**: grep + read + LSP 조합으로 탐색. 평균 8~12분 소요 (에이전트 세션 로그 기준)
- **After (도입 후)**: `codegraph context` + `codegraph explore`로 탐색. 동일 질문 대비 시간 단축 목표
- **측정 방법**: 동일 질문에 대한 도달 시간 비교. 에이전트 세션 로그에서 첫 탐색 질의부터 정답 도달까지의 경과 시간 측정
- **개선 판정 기준**: 동일 탐색 작업 시 30% 이상 시간 단축

### 2. 호출 흐름 정확도 (Call Flow Accuracy)

- **정의**: 호출 경로 추적 결과의 정확도
- **Before (도입 전)**: 수동 grep + read로 호출 체인 추적. 간접 호출, 프로토콜 기반 호출 누락 빈번
- **After (도입 후)**: `codegraph trace` + `codegraph callers`로 자동 추적. 그래프 기반으로 간접 호출 포함
- **측정 방법**: 5개 이상 알려진 TCA 리듀서 호출 경로에 대한 정확도 (%) 측정
    - 예시 경로: Action -> Reducer -> Effect -> State
    - 예시 경로: View Action -> Scope Reducer -> Domain Reducer -> Network Effect
    - 예시 경로: View Action -> Helper Reducer -> Dependency -> Side Effect
- **개선 판정 기준**: 80% 이상 호출 경로 정확 캡처

### 3. 영향 분석 범위 (Impact Analysis Coverage)

- **정의**: 변경 영향 분석의 누락/과잉 비율
- **Before (도입 전)**: `macos_checks.py --changed` (파일 경로 기반, 정적 매핑)
- **After (도입 후)**: `codegraph impact <symbol>` (심볼 의존 그래프 기반)
- **측정 방법**: codegraph impact 결과 vs macos_checks.py 결과 비교
    - 누락된 파일 수: codegraph가 잡고 macos_checks가 놓친 경우
    - 과잉 포함된 파일 수: 관련없는 파일이 포함된 경우
- **개선 판정 기준**: macos_checks 대비 누락 0건, 과잉 20% 미만

### 4. 크로스 언어 추적 (Cross-Language Tracing)

- **정의**: Swift와 Python 간 참조/호출 추적 가능 여부
- **Before (도입 전)**: 수동으로 Swift API 호출 -> Python 엔드포인트 매핑. 담당자 문의 또는 코드 리뷰 의존
- **After (도입 후)**: `codegraph trace`로 Swift -> Python 경로 추적
- **측정 방법**: boundary crossing 쿼리 성공률 측정
    - Swift -> Python: SearchGateway -> search_router
    - Helper -> Backend: XPC service -> API endpoint
- **개선 판정 기준**: 50% 이상 크로스 언어 경로 추적 성공

### 5. 에이전트 워크플로 개선 (Agent Workflow Improvement)

- **정의**: CodeGraph 사용 세션 vs 미사용 세션의 효율성 비교
- **Before (도입 전)**: "이 리듀서가 어디서 호출되나?" 질의 시 grep(3회) + read(5회) = 약 8회 도구 호출
- **After (도입 후)**: `codegraph callers` 1회 호출로 동일 결과 획득
- **측정 방법**: 세션별 탐색 턴 수, 도구 호출 수 비교. 동일 탐색 작업 기준
- **개선 판정 기준**: 탐색 관련 도구 호출 수 40% 이상 감소

### 6. 유지비 (Maintenance Cost)

- **정의**: CodeGraph 운영에 필요한 리소스
- **Before (도입 전)**: 해당 없음 (신규 도입)
- **After (도입 후)**: 인덱싱, 갱신, 리소스 소비 측정
- **측정 방법**: 다음 항목 측정
    - 초기 인덱싱 시간: 현재 약 4초 (666 files)
    - Incremental 인덱싱 시간: 측정 필요
    - 디스크 사용량: 현재 약 27MB
    - 메모리 사용량: MCP 서버 실행 시 측정 필요
    - 갱신 주기: 코드 변경 후 reindex 필요 빈도
- **개선 판정 기준**: 유지비가 탐색/분석 이득을 초과하면 제거 대상

### 7. 토큰 수 절감 (Token Savings)

- **정의**: CodeGraph 사용으로 절감되는 에이전트 토큰 소비량
- **Before (도입 전)**: grep(3회) + read(5회) = 약 15k tokens로 "이 리듀서의 호출자" 탐색
- **After (도입 후)**: codegraph callers(1회) = 약 2k tokens로 동일 결과
- **측정 방법**: 동일 질문에 대해 CodeGraph 경로 vs 기존 경로의 총 토큰 수 비교
- **개선 판정 기준**: 탐색 작업 시 토큰 소비 50% 이상 절감

## 평가 시점

| 시점     | 일정          | 평가 내용                              |
| -------- | ------------- | -------------------------------------- |
| 1주일 후 | 초기 적응     | 탐색 속도, 호출 흐름 정확도, 토큰 절감 |
| 2주일 후 | Go/No-Go 판단 | 전체 7각도 종합 평가                   |
| 1개월 후 | 장기 검증     | 유지비, 워크플로 개선, 영향 분석 범위  |

## Go/No-Go 기준

### Go (유지)

- 7개 각도 중 **4개 이상** "개선" 판정
- 유지비가 이득을 초과하지 않음
- 기존 도구(SourceKit-LSP, boundary reviewer) 동작에 영향 없음

### No-Go (재평가 또는 제거)

- 7개 각도 중 **3개 이하** "개선" 판정
- 유지비가 이득을 초과
- 기존 도구와 충돌 발생

### 제거 절차

1. `just codegraph-clean`로 인덱스 삭제
2. `opencode.json`에서 codegraph MCP 항목 제거
3. `justfile`에서 codegraph 명령 제거
4. 본 가이드 파일 삭제

## 측정 기록 양식

각 평가 시점마다 다음 양식으로 기록한다:

```
### [각도명] -- [측정일]
- Before: [측정값]
- After: [측정값]
- 개선율: [X%]
- 판정: [개선 / 변화없음 / 악화]
- 비고: [추가 관찰사항]
```

## Must not

- 자동화된 벤치마크 하네스를 구현하지 않는다.
- 평가를 CI에 통합하지 않는다.
- 수동 인간 측정을 요구하지 않는다 (에이전트가 측정 가능한 항목만 포함).
