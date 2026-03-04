# Import Smart Folder as Collection

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-002-import_smart_folder_as_collection |
| Interaction Type | command |
| Feature | Manage Retrieval Collections |
| Category Key | RCL |
| Feature ID | RCL-002 |
| Status | 아이디어 |
| Summary | Finder Smart Folder 조건을 파싱해 콜렉션 파일로 생성 |
| Related Region | settings_window |
| Menu | - |
| Shortcut | - |

## Preconditions

- 파일 읽기/파싱 권한이 확보된 상태
## Edge Cases

- `.savedSearch` 파싱에 실패하는 경우

## Acceptance Criteria

- [ ] 파일 읽기/파싱 권한이 확보된 상태일 때, 사용자가 해당 인터랙션을 호출하면, .savedSearch 조건을 파싱해 콜렉션 파일으로 지정한 위치에 생성함
- [ ] 사용자가 임포트를 시도했을 때, .savedSearch 파싱에 실패한다면, 콜렉션 파일을 생성하지 않고 실패 피드백을 표시함

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `130`
