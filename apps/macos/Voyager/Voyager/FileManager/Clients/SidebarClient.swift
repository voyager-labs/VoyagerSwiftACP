import ComposableArchitecture
import Foundation

struct SidebarClient: Sendable {
    var computerName: @Sendable () -> String
    var loadRecentItems: @Sendable (Bool) async -> [Entry]
    var loadFilesWithTag: @Sendable (String, Bool) async -> [Entry]

    nonisolated init(
        computerName: @escaping @Sendable () -> String,
        loadRecentItems: @escaping @Sendable (Bool) async -> [Entry],
        loadFilesWithTag: @escaping @Sendable (String, Bool) async -> [Entry],
    ) {
        self.computerName = computerName
        self.loadRecentItems = loadRecentItems
        self.loadFilesWithTag = loadFilesWithTag
    }
}

extension SidebarClient: DependencyKey {
    nonisolated static var liveValue: SidebarClient {
        nonisolated(unsafe) let fileManager = FileManager.default
        return SidebarClient(
            computerName: {
                fileManager.displayName(atPath: "/")
            },
            loadRecentItems: { showHidden in
                await SidebarUtils.loadRecentItems(showHidden: showHidden)
            },
            loadFilesWithTag: { tagName, showHidden in
                await SidebarUtils.loadFilesWithTag(tagName, showHidden: showHidden)
            },
        )
    }

    nonisolated static var testValue: SidebarClient {
        SidebarClient(
            computerName: { "" },
            loadRecentItems: { _ in [] },
            loadFilesWithTag: { _, _ in [] },
        )
    }

    nonisolated static var previewValue: SidebarClient {
        SidebarClient(
            computerName: { "" },
            loadRecentItems: { _ in [] },
            loadFilesWithTag: { _, _ in [] },
        )
    }
}

extension DependencyValues {
    nonisolated var sidebarClient: SidebarClient {
        get { self[SidebarClient.self] }
        set { self[SidebarClient.self] = newValue }
    }
}
