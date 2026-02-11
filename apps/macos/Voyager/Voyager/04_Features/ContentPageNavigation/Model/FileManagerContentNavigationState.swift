// TODO(ContentPageNavigation): 2차 네이밍 정리
// - 파일명 변경: FileManagerContentNavigationState.swift -> ContentPageNavigationState.swift
// - 타입명 변경:
//   - FileManagerContentNavigationState -> ContentPageNavigationState
// - 주의:
//   - 이 단계에서는 동작 변경 금지(로직 수정 금지). 네이밍만 정리한다.
import ComposableArchitecture
import Foundation
import SwiftUI

@ObservableState
struct FileManagerContentNavigationState: Equatable {
    var navigationState: FileManagerNavigationUtils.NavigationState =
        .folder(SettingsDefaults.defaultTabPath())
    var titlePath: String = SettingsDefaults.defaultTabPath()
    var scrollPositions: [String: CGPoint] = [:]

    var backHistory: [ContentPageHistory] = []
    var forwardHistory: [ContentPageHistory] = []
    var pendingNavigation: ContentPendingNavigation?

    var currentPath: String {
        switch navigationState {
        case let .folder(path):
            path
        case .recents:
            "Recents"
        case let .tags(tagName):
            tagName
        case .computer:
            "" // Will be computed in View using navigationClient
        case let .collection(navigation):
            switch navigation.kind {
            case .temporary:
                "New Collection"
            case let .file(_, name):
                name
            }
        }
    }

    var canGoBack: Bool {
        !backHistory.isEmpty
    }

    var canGoForward: Bool {
        !forwardHistory.isEmpty
    }

    var canGoToEnclosingDirectory: Bool {
        enclosingDirectoryPath != nil
    }

    var enclosingDirectoryPath: String? {
        switch navigationState {
        case let .folder(path):
            let url = URL(fileURLWithPath: path)
            let parent = url.deletingLastPathComponent()
            guard parent.path != path, path != "/" else { return nil }
            return parent.path

        case let .collection(navigation):
            guard case let .file(url, _) = navigation.kind else { return nil }
            return url.deletingLastPathComponent().path

        case .recents, .tags, .computer:
            return nil
        }
    }

    mutating func navigateToFolder(_ path: String, composer: inout ComposerFeature.State) {
        let previousPath = currentPath
        let snapshot = makeContentPageHistory(composer: composer)
        composer = .init()
        appendBackHistory(snapshot)
        forwardHistory = []
        navigationState = .folder(path)

        if composer.isPresented,
           !composer.scopes.isEmpty,
           composer.scopes[0] == previousPath
        {
            composer.scopes[0] = path
        }
    }

    mutating func navigate(
        to navigationState: FileManagerNavigationUtils.NavigationState,
        composer: inout ComposerFeature.State,
    ) {
        let snapshot = makeContentPageHistory(composer: composer)
        composer = .init()
        appendBackHistory(snapshot)
        forwardHistory = []
        self.navigationState = navigationState
    }

    mutating func appendBackHistory(_ entry: ContentPageHistory) {
        backHistory.append(entry)
        trimHistory()
    }

    mutating func appendForwardHistory(_ entry: ContentPageHistory) {
        forwardHistory.append(entry)
        trimHistory()
    }

    mutating func trimHistory() {
        if backHistory.count > 10 {
            backHistory.removeFirst(backHistory.count - 10)
        }
        if forwardHistory.count > 10 {
            forwardHistory.removeFirst(forwardHistory.count - 10)
        }
    }

    func makeContentPageHistory(composer: ComposerFeature.State) -> ContentPageHistory {
        ContentPageHistory(
            navigationState: navigationState,
            composerState: composer,
        )
    }
}
