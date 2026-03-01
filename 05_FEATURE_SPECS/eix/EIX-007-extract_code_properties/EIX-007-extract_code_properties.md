# Extract Code Properties

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EIX-007-extract_code_properties |
| Interaction Type | background |
| Feature | Extract Code Properties |
| Category Key | EIX |
| Feature ID | EIX-007 |
| Status | 드래프트 |
| Summary | 코드 Entry에서 언어·주요 모듈/엔트리포인트·프레임워크·간단 요약 등 코드 관련 자동 프로퍼티를 추출해 Entry 프로퍼티로 저장 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 대상 Entry가 코드 계열 포맷으로 분류된 상태
- <<AI>> 코드 프로퍼티 추출 파이프라인이 활성화된 상태
- <<AI>> 대상 Entry를 읽을 수 있는 권한이 확보된 상태
## Edge Cases

- <<AI>> 파일이 매우 크거나 바이너리 포함으로 파싱 비용이 과도한 경우
- <<AI>> 언어 감지에 실패하거나 혼합 언어로 단일 언어로 분류하기 어려운 경우
- <<AI>> 코드가 생성물로 판단되어 제외 규칙에 의해 제외되는 경우

## Acceptance Criteria

- [ ] <<AI>> 대상 Entry가 코드 포맷인 상태일 때, 시스템이 추출을 수행하면, 언어·주요 모듈/엔트리포인트·간단 요약 등 자동 프로퍼티를 저장함.
- [ ] <<AI>> 코드가 변경된 상태일 때, 시스템이 재추출을 수행하면, 자동 프로퍼티 값을 최신 값으로 갱신함.
- [ ] <<AI>> 추출이 실패한 상태일 때, 시스템이 실패를 기록하면, 실패 항목을 재시도 가능 상태로 유지함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `89`
