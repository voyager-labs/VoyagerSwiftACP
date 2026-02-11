// TODO(ContentPageNavigation): 2차 네이밍 정리
// - 파일명 변경: FileManagerContentNavigationAction.swift -> ContentPageNavigationAction.swift
// - 타입명 변경:
//   - FileManagerContentNavigationAction -> ContentPageNavigationAction
//   - FileManagerContentNavigationDelegate -> ContentPageNavigationDelegate
// - 주의:
//   - 이 단계에서는 동작 변경 금지(로직 수정 금지). 네이밍만 정리한다.
import ComposableArchitecture
import Foundation

enum FileManagerContentNavigationDelegate: Equatable, Sendable {
    case applyContentPageHistory(ContentPageHistory)
    case navigateToState(FileManagerNavigationUtils.NavigationState)
    case logDAUNavigation(
        previous: FileManagerNavigationUtils.NavigationState,
        next: FileManagerNavigationUtils.NavigationState,
    )
    case resetComposer
}

@CasePathable
enum FileManagerContentNavigationAction: Equatable, Sendable {
    case goBack
    case goForward
    case goToHistoryIndex(Int, isBackHistory: Bool)
    case goToEnclosingDirectory
    case performNavigation(ContentPendingNavigation, currentSnapshot: ContentPageHistory)
    case showUnsavedNavigationAlert(ContentPendingNavigation)
    case unsavedNavigationAlertResponse(ContentPendingNavigation, CollectionNavigationChoice)
    case delegate(FileManagerContentNavigationDelegate)
}
