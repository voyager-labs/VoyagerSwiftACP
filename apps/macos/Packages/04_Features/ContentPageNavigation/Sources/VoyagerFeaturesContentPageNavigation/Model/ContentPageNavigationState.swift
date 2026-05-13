import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerEntitiesAppPreferences

@ObservableState
public struct ContentPageNavigationState: Equatable {
    public init() {}

    public var navigationState: ContentPageNavigationRoute =
        .folder(SettingsDefaults.defaultTabPath())
    public var titlePath: String = SettingsDefaults.defaultTabPath()
    public var scrollPositions: [String: CGPoint] = [:]

    public var backHistory: [ContentPageNavigationHistorySnapshot] = []
    public var forwardHistory: [ContentPageNavigationHistorySnapshot] = []
    public var pendingNavigation: ContentPageNavigationPending?

    public var currentPath: String {
        switch navigationState {
        case let .folder(path):
            path
        case .recents:
            "Recents"
        case let .tags(tagName):
            tagName
        case .computer:
            ""
        case let .collection(navigation):
            switch navigation.kind {
            case .temporary:
                "New Collection"
            case let .file(_, name):
                name
            }
        }
    }

    public var canGoBack: Bool {
        !backHistory.isEmpty
    }

    public var canGoForward: Bool {
        !forwardHistory.isEmpty
    }

    public var canGoToEnclosingDirectory: Bool {
        enclosingDirectoryPath != nil
    }

    public var enclosingDirectoryPath: String? {
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

    public mutating func seedInitialFolderPath(_ path: String) {
        navigationState = .folder(path)
        titlePath = path
    }

    public mutating func appendBackHistory(_ entry: ContentPageNavigationHistorySnapshot) {
        backHistory.append(entry)
        trimHistory()
    }

    public mutating func appendForwardHistory(_ entry: ContentPageNavigationHistorySnapshot) {
        forwardHistory.append(entry)
        trimHistory()
    }

    public mutating func trimHistory() {
        if backHistory.count > 10 {
            backHistory.removeFirst(backHistory.count - 10)
        }
        if forwardHistory.count > 10 {
            forwardHistory.removeFirst(forwardHistory.count - 10)
        }
    }

    public func makeContentPageNavigationHistorySnapshot() -> ContentPageNavigationHistorySnapshot {
        ContentPageNavigationHistorySnapshot(navigationState: navigationState)
    }
}
