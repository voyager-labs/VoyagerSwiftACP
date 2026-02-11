// TODO(ContentPageNavigation): 2차 네이밍 정리
// - 파일명 변경: ContentPageHistory.swift -> ContentPageNavigationHistorySnapshot.swift
// - 타입명 변경:
//   - ContentPageHistory -> ContentPageNavigationHistorySnapshot
// - 관련 심볼 변경:
//   - composerState -> composerSnapshot (검토)
// - 주의:
//   - 이 단계에서는 동작 변경 금지(로직 수정 금지). 네이밍만 정리한다.
struct ContentPageHistory: Equatable {
    let navigationState: FileManagerNavigationUtils.NavigationState
    let composerState: ComposerFeature.State
}
