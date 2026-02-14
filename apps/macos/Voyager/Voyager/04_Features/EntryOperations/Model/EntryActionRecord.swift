import Foundation

struct EntryActionRecord: Equatable, Identifiable, Sendable {
    enum ActionKind: String, Sendable {
        case rename
        case move
        case duplicate
        case paste
        case createFolder
        case createAlias
        case moveToTrash
        case putBack
        case setTags
    }

    struct Target: Equatable, Sendable {
        let beforePath: String?
        let afterPath: String?
        let beforeTags: [String]?
        let afterTags: [String]?

        nonisolated init(
            beforePath: String?,
            afterPath: String?,
            beforeTags: [String]? = nil,
            afterTags: [String]? = nil,
        ) {
            self.beforePath = beforePath
            self.afterPath = afterPath
            self.beforeTags = beforeTags
            self.afterTags = afterTags
        }
    }

    let id: UUID
    let actionKind: ActionKind
    let timestamp: Date
    let targets: [Target]

    nonisolated init(
        actionKind: ActionKind,
        targets: [Target],
        id: UUID = UUID(),
        timestamp: Date = Date(),
    ) {
        self.id = id
        self.actionKind = actionKind
        self.timestamp = timestamp
        self.targets = targets
    }
}
