# Extract Video Properties

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EIX-011-extract_video_properties |
| Interaction Type | background |
| Feature | Extract Video Propeties |
| Category Key | EIX |
| Feature ID | EIX-011 |
| Status | 아이디어 |
| Summary | 비디오 Entry에서 화면 타입(스크린캐스트/발표/회의 등)·길이·핵심 구간 요약·주요 키워드 등 비디오 관련 자동 프로퍼티를 추출해 Entry 프로퍼티로 저장 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 대상 Entry가 비디오 계열 포맷으로 분류된 상태
- <<AI>> 비디오 프로퍼티 추출 파이프라인이 활성화된 상태
- <<AI>> 대상 Entry를 읽을 수 있는 권한이 확보된 상태
## Edge Cases

- <<AI>> 비디오 파일이 손상되었거나 코덱 지원 문제로 디코딩이 실패하는 경우
- <<AI>> 길이가 매우 길어 전사·요약·구간 추출을 분할 처리해야 하는 경우
- <<AI>> 오디오 트랙이 없거나 품질이 낮아 전사가 불완전한 경우

## Acceptance Criteria

- [ ] <<AI>> 대상 Entry가 비디오 포맷인 상태일 때, 시스템이 추출을 수행하면, 화면 타입·길이·핵심 구간 요약·키워드 등 자동 프로퍼티를 저장함.
- [ ] <<AI>> 추출이 완료된 상태일 때, 사용자가 해당 Entry를 검색하면, 추출된 프로퍼티 기반 조건으로 필터링할 수 있게 함.
- [ ] <<AI>> 추출이 실패한 상태일 때, 시스템이 실패를 기록하면, 실패 항목을 오류 상세에서 확인 가능하게 함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `93`
