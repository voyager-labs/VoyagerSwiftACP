// TODO(ContentPageNavigation): 2차 네이밍 정리
// - 파일명 변경: ContentPendingNavigation.swift -> ContentPageNavigationPending.swift
// - 타입명 변경:
//   - ContentPendingNavigation -> ContentPageNavigationPending
// - 주의:
//   - 이 단계에서는 동작 변경 금지(로직 수정 금지). 네이밍만 정리한다.
enum ContentPendingNavigation: Equatable, Sendable {
    case back
    case forward
    case history(index: Int, isBackHistory: Bool)
    case enclosingDirectory
}
