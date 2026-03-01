# Open New Content Tab

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CTM-001-open_new_content_tab |
| Interaction Type | command |
| Feature | Handle Content Tab |
| Category Key | CTM |
| Feature ID | CTM-001 |
| Status | 준비 완료 |
| Summary | 해당 File Manager 내, 새 Session Content Tab을 추가 |
| Related Region | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu | FIle |
| Shortcut | ⌘T |

## Preconditions

- -
## Edge Cases

- -

## Acceptance Criteria

- [ ] <<AI>> 활성 File Manager Window가 있고 Content Tab 수가 최대값 미만일 때, 사용자가 해당 인터랙션을 호출하면, 해당 창의 Content Tab List 끝에 새 Session Content Tab이 생성되고 즉시 활성화됨.
- [ ] <<AI>> Content Tab 수가 최대 허용값에 도달한 상태에서 사용자가 해당 인터랙션을 호출하면, 새 탭이 생성되지 않고 탭 개수 제한에 대한 피드백을 표시함.
- [ ] <<AI>> 새로 생성된 Content Tab 초기 세션 로딩 중 오류가 발생한 상태에서 사용자가 해당 인터랙션을 호출하면, 탭 셸은 생성되지만 내용 영역에 오류 메시지를 표시하거나 탭 생성 자체를 롤백함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `193`
