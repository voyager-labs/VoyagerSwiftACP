# Duplicate Content Tab

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CTM-001-duplicate_content_tab |
| Interaction Type | command |
| Feature | Handle Content Tab |
| Category Key | CTM |
| Feature ID | CTM-001 |
| Status | 준비 완료 |
| Summary | 해당 Content Tab을 동일한 상태의 Content Tab으로 복제해 추가 |
| Related Region | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu | File |
| Shortcut | ⌘D |

## Preconditions

- 복제할 Content Tab이 지장된 상태
## Edge Cases

- 복제 대상 탭에 저장되지 않은 변경 사항이 있는 경우

## Acceptance Criteria

- [ ] <<AI>> 복제할 Content Tab이 활성 상태이고 세션 상태가 유효할 때, 사용자가 해당 인터랙션을 호출하면, 대상 탭과 동일한 상태의 새 Content Tab이 바로 오른쪽에 생성되고 활성화됨.
- [ ] <<AI>> 복제 대상 탭에 저장되지 않은 변경 사항이 있는 상태에서 사용자가 해당 인터랙션을 호출하면, 현재 메모리 상 상태를 기준으로 복제 탭이 생성되며 둘 다 동일한 내용을 표시함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `200`
