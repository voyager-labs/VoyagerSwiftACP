# Adjust File Manager Window Size

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | FMW-001-adjust_file_manager_window_size |
| Interaction Type | input |
| Feature | Control File Manager Window |
| Category Key | FMW |
| Feature ID | FMW-001 |
| Status | 배포 완료 |
| Summary | File Manager 창의 Width/Hegith를 최소-최대 범위 내에서 조정 |
| Related Region | file_manager_window |
| Menu | - |
| Shortcut | - |

## Preconditions

- -
## Edge Cases

- 사용자가 창 크기를 최소 허용 크기보다 더 작게 드래그하려는 경우
- 사용자가 창 크기를 최대 허용 크기보다 더 크게 드래그하려는 경우

## Acceptance Criteria

- [ ] 사용자가 해당 File Manager Window의 Size를 줄이려고 할 때, 최소 너비와 높이 이하로 줄이려고 하는 경우, 창 크기는 최소값에서 멈추고 더 작게 줄어들지 않음
- [ ] 사용자가 해당 File Manager Window의 Size를 늘리려고 할 때, 현재 위치한 데크스탑의 너비와 높이 이상 늘이려고 하는 경우, 창 크기는 데스크탑의 가장자리에서 멈추고 더 이상 늘지 않음
- [ ] Sidebar가 표시 상태일 때, Content Pane의 너비가 Sidebar의 너비에 도달하는 경우, Hide Sidebar 인터랙션을 호출함

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `9`
