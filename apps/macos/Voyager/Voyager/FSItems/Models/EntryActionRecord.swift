import Foundation

struct EntryActionRecord: Equatable, Identifiable, Sendable {
    enum ActionKind: String, Sendable {
        case rename
        case move
        case duplicate
        case paste
        case createFolder
        case moveToTrash
        case putBack
    }

    struct Target: Equatable, Sendable {
        let beforePath: String?
        let afterPath: String?

        // swiftlint:disable:next unneeded_synthesized_initializer
        nonisolated init(beforePath: String?, afterPath: String?) {
            self.beforePath = beforePath
            self.afterPath = afterPath
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
