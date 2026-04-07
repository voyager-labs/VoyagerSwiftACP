# Split Content Pane Vertically/Horizontally

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EVM-003-split_content_pane_vertically_horizontally |
| Interaction Type | command |
| Feature | Split Content Pane |
| Category Key | EVM |
| Feature ID | EVM-003 |
| Status | 기획 완료 |
| Summary | <<AI>> 현재 Content Pane을 수직 또는 수평으로 분할하여 두 개의 독립 뷰를 동시에 표시합니다 |
| Related Region | file_manager_window.content_pane |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> Content Pane이 표시 상태.
- <<AI>> 분할을 위한 최소 폭/높이가 확보된 상태.
- <<AI>> 현재 Pane에 치명적 오류/모달 진행 중이 아닌 상태.
## Edge Cases

- <<AI>> 창/레이아웃이 너무 작아 두 Pane 최소 크기를 충족하지 못하는 경우.
- <<AI>> Sidebar/Inspector가 넓게 열려 있어 분할 후 각 Pane 최소 폭을 만족하지 못하는 경우.
- <<AI>> 현재 페이지가 렌더링 대기/오류로 분할 직후 동일 콘텐츠 동기화가 지연되는 경우.

## Acceptance Criteria

- [ ] <<AI>> 사용자가 인터랙션을 호출하면 Content Pane이 지정한 방향(수직/수평)으로 즉시 두 Pane으로 분할됨.
- [ ] <<AI>> 기본으로 두 Pane는 동일 페이지를 독립 스크롤로 표시하고, 중앙 디바이더가 생성됨.
- [ ] <<AI>> 포커스는 새로 생성된 Pane로 전환되고 키보드 네비게이션이 해당 Pane에 라우팅됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `34`
