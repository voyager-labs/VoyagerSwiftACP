# API ↔ Component Mapping

## Endpoint Mapping

| API | Called By (Component/Reducer) | Request Source | Response Consumed By | UI States (LEE) | Notes |
| --- | --- | --- | --- | --- | --- |
| POST `/search` | `CommandDockView` → `DockReducer.submit` | `DockState.query`, `DockState.filters` | `ResultsList`(items), `ThreadHeader`(summary chips) | Loading → Results / Empty / Error | 디바운스(≈250–300ms). `timeout`/`500`는 `DockError.timeout/server`로 매핑 |
| GET `/collections` | `ThreadSidebar` → onAppear/refresh | n/a | `ThreadSidebar`(saved threads) | Loading → List / Error | 핀 고정은 클라 정렬 우선(서버 확장 여지) |
| POST `/collections` | `ThreadHeader.saveTapped`, `ThreadSidebar.newFromActive/rename` | name, query, filters[, id] | `ThreadSidebar`(insert/update), `ThreadHeader`(title/isSaved) | Busy → Success / Error | 정의만 저장(name/query/filters). id 없으면 생성, 있으면 업데이트 |
| POST `/index` | App-level Indexing Flow (Settings/Paths 패널 또는 명령) | paths, recursive, follow_symlinks | HUD/Toast(요약), Active Thread(후속 검색 결과) | Busy/Progress → Success / Error | 온보딩에서는 인덱싱 안내만 제공(VOY-111: placeholder). 실제 `/` kick-off 연동은 후속 이슈에서 수행 |

## Model Mapping

- UI `ThreadSummary` ↔ API `collections.item`
  - id ↔ `id`
  - title ↔ `name`
  - summary chips ↔ `query`/`filters`
  - lastUpdatedAt ↔ `updated_at`(도입 시)
  - isPinned: 클라 상태(백엔드 비영속; 서버 필드 도입 시 동기화 고려)

- UI `SearchResultItem` ↔ API `/search.items[]`
  - id: UUID(클라 생성) ↔ 조합(`path`+hash)
  - name ↔ `name`
  - path ↔ `path`
  - size ↔ `size`
  - modifiedAt ↔ `modified_at`
  - uti ↔ `uti`
  - score ↔ `score`

## Error Mapping → UI

| API Error | Example | UI Mapping |
| --- | --- | --- |
| 400 invalid filters | 잘못된 필터 키/값 | `DockError.invalidFilters` + 칩 하이라이트 |
| 500 server error | 예외 발생 | `DockError.server(msg)` + 재시도 버튼 |
| timeout | 네트워크 지연 | `DockError.timeout` + 안내/재시도 |
