import ComposableArchitecture
import Foundation
import SwiftUI

@ObservableState
struct ContentPageNavigationState: Equatable {
    var navigationState: ContentPageNavigationRoute =
        .folder(SettingsDefaults.defaultTabPath())
    var titlePath: String = SettingsDefaults.defaultTabPath()
    var scrollPositions: [String: CGPoint] = [:]

    var backHistory: [ContentPageNavigationHistorySnapshot] = []
    var forwardHistory: [ContentPageNavigationHistorySnapshot] = []
    var pendingNavigation: ContentPageNavigationPending?

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

    mutating func seedInitialFolderPath(_ path: String) {
        navigationState = .folder(path)
        titlePath = path
    }

    mutating func appendBackHistory(_ entry: ContentPageNavigationHistorySnapshot) {
        backHistory.append(entry)
        trimHistory()
    }

    mutating func appendForwardHistory(_ entry: ContentPageNavigationHistorySnapshot) {
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

    func makeContentPageNavigationHistorySnapshot() -> ContentPageNavigationHistorySnapshot {
        ContentPageNavigationHistorySnapshot(navigationState: navigationState)
    }
}
