# Seprated Splited Content Pane

## Metadata

| Field            | Value                                                                                           |
| ---------------- | ----------------------------------------------------------------------------------------------- |
| Interaction ID   | EVM-003-seprated_splited_content_pane                                                           |
| Interaction Type | command                                                                                         |
| Feature          | Split Content Pane                                                                              |
| Category Key     | EVM                                                                                             |
| Feature ID       | EVM-003                                                                                         |
| Status           | 기획 완료                                                                                       |
| Summary          | <<AI>> 두 분할 Pane의 세션/네비게이션을 분리하여 서로 다른 페이지/경로를 독립적으로 탐색합니다. |
| Related Region   | file_manager_window.content_pane                                                                |
| Menu             | -                                                                                               |
| Shortcut         | -                                                                                               |

## Preconditions

- <<AI>> Content Pane이 분할 상태.
- <<AI>> 각 Pane의 히스토리/세션을 개별로 유지할 수 있는 상태.

## Edge Cases

- <<AI>> 한 Pane에서 접근 불가 경로/네트워크 끊김 발생 시 해당 Pane만 오류/안내를 표시하고 다른
  Pane은 정상 유지.
- <<AI>> 동일 리소스에 대한 동시 편집/잠금 충돌이 발생할 수 있는 경우.

## Acceptance Criteria

- [ ] <<AI>> 사용자가 인터랙션을 호출하면 두 Pane의 세션/네비게이션이 분리되어 각 Pane에서 서로 다른
      페이지/경로를 독립적으로 탐색 가능함.
- [ ] <<AI>> 각 Pane의 히스토리는 별도로 기록되며, 링크/열기 등 액션은 현재 포커스 Pane에만 적용됨.
- [ ] <<AI>> 한 Pane의 오류는 다른 Pane의 표시/조작에 영향을 주지 않음.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `36`
