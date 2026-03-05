# Analyze Custom Property Usage

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CEP-002-analyze_custom_property_usage |
| Interaction Type | background |
| Feature | Define Custom Property Schema |
| Category Key | CEP |
| Feature ID | CEP-002 |
| Status | 아이디어 |
| Summary | <<AI>> 워크스페이스 전체를 스캔해 각 사용자 프로퍼티 스키마가 어디에서 얼마나 사용되는지 사용 현황을 분석한다. |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 워크스페이스가 로드되어 엔트리 메타데이터에 접근 가능한 상태
- <<AI>> 사용 현황 분석 작업이 실행 중이지 않은 상태
## Edge Cases

- <<AI>> 대상 엔트리 수가 많아 분석 시간이 길어지는 경우
- <<AI>> 일부 스토리지의 엔트리에 접근할 수 없어 부분 분석만 가능한 경우
- <<AI>> 분석 중 스키마가 변경되어 결과가 일시적으로 불일치하는 경우

## Acceptance Criteria

- [ ] <<AI>> 워크스페이스가 로드된 상태일 때, 시스템이 분석 작업을 시작하면, 스키마별 사용 현황(엔트리 수, 참조 위치 등)을 계산해 저장함.
- [ ] <<AI>> 분석이 완료된 상태일 때, 사용자가 스키마 리스트 화면을 열면, 각 스키마 행에 최신 사용 현황을 표시함.
- [ ] <<AI>> 부분 분석만 가능한 상태일 때, 시스템이 결과를 저장하면, 계산된 부분 결과와 접근 실패 사유를 함께 표시함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `183`
