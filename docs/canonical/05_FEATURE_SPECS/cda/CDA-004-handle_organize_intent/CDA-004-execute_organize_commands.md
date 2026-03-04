# Execute Organize Commands

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CDA-004-execute_organize_commands |
| Interaction Type | background |
| Feature | Handle Organize Intent |
| Category Key | CDA |
| Feature ID | CDA-004 |
| Status | 기획 완료 |
| Summary | 승인된 정돈 명령을 실제 파일 시스템에 적용 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 처리 중인 Message가 Organize Intent를 포함하는 상태
- <<AI>> 승인된 Organize Commands 목록이 존재함
- <<AI>> 대상 entry에 대한 파일 시스템 및 콜렉션 쓰기 권한이 있음
- <<AI>> 파일 시스템과 관련 서비스가 정상 동작 중임
## Edge Cases

- <<AI>> 일부 명령만 성공하고 일부 명령이 실패하는 부분 성공 상황이 발생하는 경우
- <<AI>> 파일 시스템 잠금 또는 동시 접근으로 인해 일시적으로 실패하는 경우
- <<AI>> 되돌릴 수 없는 작업(예: 영구 삭제)이 포함된 경우

## Acceptance Criteria

- [ ] <<AI>> 승인된 Organize Commands 목록이 존재하는 상태일 때, 시스템이 Execute Organize Commands 인터랙션을 실행하면, 각 명령이 파일 시스템과 콜렉션에 순차적으로 적용됨.
- [ ] <<AI>> 일부 명령만 성공하고 일부 명령이 실패한 상태일 때, 시스템이 Execute Organize Commands 인터랙션을 완료하면, 성공·실패 여부와 이유가 개별 명령 단위로 기록됨.
- [ ] <<AI>> 되돌릴 수 없는 작업이 포함된 상태일 때, 시스템이 Execute Organize Commands 인터랙션을 실행하면, 사전 확인을 통과한 명령만 실행되고 확인되지 않은 명령은 실행되지 않음.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `167`
