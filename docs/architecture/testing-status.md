# 테스트 현황

- Backend: 아직 pytest 스위트 없음(가이드라인에 따라 `apps/backend/tests/` 하에 추가 권장)
- macOS: Unit/UI 테스트 번들이 존재. Dock 표시/키보드 포커스/백엔드 연결에 대한 케이스 확장 요망

### macOS UI 테스트 후보(정의)
- `testDisplaysDockToggleFocus`: Dock 표시/ESC 닫기 후 포커스 복귀 확인
- `testSearchResultsRendering`: `/search` 응답을 리스트/그리드로 표시하는 기본 흐름 확인

## 테스트 실행(제안)

- Backend: `cd apps/backend && uv run pytest` (테스트 추가 후)
- macOS: `xcodebuild test -scheme Voyager -project apps/macos/Voyager/Voyager.xcodeproj`
