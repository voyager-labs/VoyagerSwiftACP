# Extract Image Properties

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EIX-009-extract_image_properties |
| Interaction Type | background |
| Feature | Extract Image Properties |
| Category Key | EIX |
| Feature ID | EIX-009 |
| Status | 아이디어 |
| Summary | 이미지·스크린샷 Entry에서 UI 캡처 여부, 그래프/차트/화이트보드 여부, 캡션·설명 등 이미지 관련 자동 프로퍼티를 추출해 Entry 프로퍼티로 저장 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 대상 Entry가 이미지·스크린샷 계열 포맷으로 분류된 상태
- <<AI>> 이미지 프로퍼티 추출 파이프라인이 활성화된 상태
- <<AI>> 대상 Entry를 읽을 수 있는 권한이 확보된 상태
## Edge Cases

- <<AI>> 이미지 파일이 손상되었거나 디코딩이 실패하는 경우
- <<AI>> 파일 용량·해상도가 매우 커서 다운샘플링이 필요한 경우
- <<AI>> HEIC 등 특정 코덱/포맷 지원이 제한되는 환경인 경우

## Acceptance Criteria

- [ ] <<AI>> 대상 Entry가 이미지 포맷인 상태일 때, 시스템이 추출을 수행하면, UI 캡처 여부·그래프/차트 여부·캡션/설명 등 자동 프로퍼티를 저장함.
- [ ] <<AI>> 추출이 완료된 상태일 때, 사용자가 해당 Entry를 검색하면, 추출된 프로퍼티 기반 조건으로 필터링할 수 있게 함.
- [ ] <<AI>> 추출이 실패한 상태일 때, 시스템이 실패를 기록하면, 실패 항목을 오류 상세에서 확인 가능하게 함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `91`
