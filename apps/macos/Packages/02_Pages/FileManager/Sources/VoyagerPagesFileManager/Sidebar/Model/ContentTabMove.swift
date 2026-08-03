import CoreTransferable
import Foundation
import UniformTypeIdentifiers

public struct ContentTabDragPayload: Codable, Hashable, Sendable, Transferable {
    public static let supportedSchemaVersion = 1
    public static let contentType = UTType(
        exportedAs: "com.voyager.app.content-tab-drag-payload",
        conformingTo: .json,
    )

    public let schemaVersion: Int
    public let sourceWindowID: UUID
    public let tabID: ContentTabID

    public init(
        schemaVersion: Int,
        sourceWindowID: UUID,
        tabID: ContentTabID,
    ) {
        self.schemaVersion = schemaVersion
        self.sourceWindowID = sourceWindowID
        self.tabID = tabID
    }

    public static func isSupported(schemaVersion: Int) -> Bool {
        schemaVersion == supportedSchemaVersion
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}

public struct ContentTabMoveTarget: Equatable, Sendable {
    public let windowID: UUID
    public let displayTitle: String
    public let acceptsNewTabs: Bool
    public let replaceablePinnedTabIDs: Set<ContentTabID>

    public init(
        windowID: UUID,
        displayTitle: String,
        acceptsNewTabs: Bool = true,
        replaceablePinnedTabIDs: Set<ContentTabID> = [],
    ) {
        self.windowID = windowID
        self.displayTitle = displayTitle
        self.acceptsNewTabs = acceptsNewTabs
        self.replaceablePinnedTabIDs = replaceablePinnedTabIDs
    }

    public func accepts(tabID: ContentTabID) -> Bool {
        acceptsNewTabs || replaceablePinnedTabIDs.contains(tabID)
    }
}

public struct ContentTabMoveRequest: Equatable, Sendable {
    public let requestID: UUID
    public let sourceWindowID: UUID
    public let tabID: ContentTabID
    public let targetWindowID: UUID

    public init(
        requestID: UUID,
        sourceWindowID: UUID,
        tabID: ContentTabID,
        targetWindowID: UUID,
    ) {
        self.requestID = requestID
        self.sourceWindowID = sourceWindowID
        self.tabID = tabID
        self.targetWindowID = targetWindowID
    }
}

public struct ContentTabMoveFailurePresentation: Equatable, Sendable {
    public enum Category: Equatable, Sendable, CaseIterable {
        case unavailable
        case capacity
        case busy
        case generic
    }

    public let requestID: UUID
    public let category: Category

    public init(requestID: UUID, category: Category) {
        self.requestID = requestID
        self.category = category
    }
}

enum ContentTabMoveProjection {
    static let dropZoneIdentifier = "content-tabs-drop-zone"

    static func availableTargets(
        _ targets: [ContentTabMoveTarget],
        currentWindowID: UUID?,
        tabID: ContentTabID? = nil,
    ) -> [ContentTabMoveTarget] {
        targets.filter { target in
            guard target.windowID != currentWindowID else { return false }
            guard let tabID else { return true }
            return target.accepts(tabID: tabID)
        }
    }

    static func rowIdentifier(tabID: ContentTabID) -> String {
        "content-tab-\(tabID.rawValue)"
    }

    static func menuIdentifier(tabID: ContentTabID) -> String {
        "content-tab-move-menu-\(tabID.rawValue)"
    }

    static func targetIdentifier(tabID: ContentTabID, windowID: UUID) -> String {
        "content-tab-move-target-\(tabID.rawValue)-\(windowID.uuidString)"
    }

    static func progressIdentifier(tabID: ContentTabID) -> String {
        "content-tab-move-progress-\(tabID.rawValue)"
    }
}
