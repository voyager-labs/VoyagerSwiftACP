import CoreTransferable
import Foundation
import UniformTypeIdentifiers

public struct ContentTabDragPayload: Codable, Hashable, Sendable, Transferable {
    public static let legacySchemaVersion = 1
    public static let supportedSchemaVersion = 2
    public static let contentType = UTType(
        exportedAs: "com.voyager.app.content-tab-drag-payload",
        conformingTo: .json,
    )

    public let schemaVersion: Int
    public let operationID: UUID?
    public let sourceWindowID: UUID
    public let initiatingTabID: ContentTabID
    public let orderedTabIDs: [ContentTabID]

    public var tabID: ContentTabID {
        initiatingTabID
    }

    public init(
        schemaVersion: Int,
        sourceWindowID: UUID,
        tabID: ContentTabID,
        operationID: UUID = UUID(),
    ) {
        self.schemaVersion = schemaVersion
        self.operationID = schemaVersion == Self.supportedSchemaVersion ? operationID : nil
        self.sourceWindowID = sourceWindowID
        initiatingTabID = tabID
        orderedTabIDs = [tabID]
    }

    public init(
        operationID: UUID,
        sourceWindowID: UUID,
        initiatingTabID: ContentTabID,
        orderedTabIDs: [ContentTabID],
    ) {
        schemaVersion = Self.supportedSchemaVersion
        self.operationID = operationID
        self.sourceWindowID = sourceWindowID
        self.initiatingTabID = initiatingTabID
        self.orderedTabIDs = orderedTabIDs
    }

    public static func isSupported(schemaVersion: Int) -> Bool {
        schemaVersion == legacySchemaVersion || schemaVersion == supportedSchemaVersion
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case operationID
        case sourceWindowID
        case tabID
        case initiatingTabID
        case orderedTabIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        sourceWindowID = try container.decode(UUID.self, forKey: .sourceWindowID)

        switch schemaVersion {
        case Self.legacySchemaVersion:
            let tabID = try container.decode(ContentTabID.self, forKey: .tabID)
            operationID = nil
            initiatingTabID = tabID
            orderedTabIDs = [tabID]
        case Self.supportedSchemaVersion:
            operationID = try container.decode(UUID.self, forKey: .operationID)
            initiatingTabID = try container.decode(ContentTabID.self, forKey: .initiatingTabID)
            orderedTabIDs = try container.decode([ContentTabID].self, forKey: .orderedTabIDs)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported Content Tab drag payload schema",
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sourceWindowID, forKey: .sourceWindowID)

        switch schemaVersion {
        case Self.legacySchemaVersion:
            try container.encode(initiatingTabID, forKey: .tabID)
        case Self.supportedSchemaVersion:
            try container.encode(operationID, forKey: .operationID)
            try container.encode(initiatingTabID, forKey: .initiatingTabID)
            try container.encode(orderedTabIDs, forKey: .orderedTabIDs)
        default:
            throw EncodingError.invalidValue(
                schemaVersion,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported Content Tab drag payload schema",
                ),
            )
        }
    }
}

public struct ContentTabDragSnapshot: Equatable, Sendable {
    public enum Lifecycle: Equatable, Sendable {
        case prepared
        case inFlight
        case awaitingPayload
    }

    public let operationID: UUID
    public let sourceWindowID: UUID
    public let initiatingTabID: ContentTabID
    public let orderedTabIDs: [ContentTabID]
    public var lifecycle: Lifecycle

    public init(
        operationID: UUID,
        sourceWindowID: UUID,
        initiatingTabID: ContentTabID,
        orderedTabIDs: [ContentTabID],
        lifecycle: Lifecycle = .prepared,
    ) {
        self.operationID = operationID
        self.sourceWindowID = sourceWindowID
        self.initiatingTabID = initiatingTabID
        self.orderedTabIDs = orderedTabIDs
        self.lifecycle = lifecycle
    }

    public var payload: ContentTabDragPayload {
        ContentTabDragPayload(
            operationID: operationID,
            sourceWindowID: sourceWindowID,
            initiatingTabID: initiatingTabID,
            orderedTabIDs: orderedTabIDs,
        )
    }

    public func matches(_ payload: ContentTabDragPayload) -> Bool {
        payload.schemaVersion == ContentTabDragPayload.supportedSchemaVersion
            && payload.operationID == operationID
            && payload.sourceWindowID == sourceWindowID
            && payload.initiatingTabID == initiatingTabID
            && payload.orderedTabIDs == orderedTabIDs
            && orderedTabIDs.contains(initiatingTabID)
    }

    public static func normalizedDisplayedOrder(
        _ displayedOrderedTabIDs: [ContentTabID],
        sourceTabIDs: Set<ContentTabID>,
    ) -> [ContentTabID] {
        var seen: Set<ContentTabID> = []
        return displayedOrderedTabIDs.filter { tabID in
            sourceTabIDs.contains(tabID) && seen.insert(tabID).inserted
        }
    }

    public static func frozenOrderedTabIDs(
        initiatingTabID: ContentTabID,
        selectedTabIDs: Set<ContentTabID>,
        displayedOrderedTabIDs: [ContentTabID],
        sourceTabIDs: Set<ContentTabID>,
    ) -> [ContentTabID]? {
        guard sourceTabIDs.contains(initiatingTabID) else { return nil }
        let normalizedOrderedIDs = normalizedDisplayedOrder(
            displayedOrderedTabIDs,
            sourceTabIDs: sourceTabIDs,
        )
        let normalizedSelectedIDs = normalizedOrderedIDs.filter(selectedTabIDs.contains)
        guard selectedTabIDs.contains(initiatingTabID),
              normalizedSelectedIDs.contains(initiatingTabID)
        else {
            return [initiatingTabID]
        }
        return normalizedSelectedIDs
    }
}

public struct ContentTabMoveTarget: Equatable, Sendable {
    public let windowID: UUID
    public let displayTitle: String
    public let availableSlots: Int
    public let replaceablePinnedTabIDs: Set<ContentTabID>

    public var acceptsNewTabs: Bool {
        availableSlots > 0
    }

    public init(
        windowID: UUID,
        displayTitle: String,
        availableSlots: Int = .max,
        replaceablePinnedTabIDs: Set<ContentTabID> = [],
    ) {
        self.windowID = windowID
        self.displayTitle = displayTitle
        self.availableSlots = max(0, availableSlots)
        self.replaceablePinnedTabIDs = replaceablePinnedTabIDs
    }

    public init(
        windowID: UUID,
        displayTitle: String,
        acceptsNewTabs: Bool,
        replaceablePinnedTabIDs: Set<ContentTabID> = [],
    ) {
        self.init(
            windowID: windowID,
            displayTitle: displayTitle,
            availableSlots: acceptsNewTabs ? .max : 0,
            replaceablePinnedTabIDs: replaceablePinnedTabIDs,
        )
    }

    public func accepts(tabID: ContentTabID) -> Bool {
        accepts(orderedTabIDs: [tabID])
    }

    public func accepts(orderedTabIDs: [ContentTabID]) -> Bool {
        let uniqueTabIDs = Set(orderedTabIDs)
        guard !orderedTabIDs.isEmpty, uniqueTabIDs.count == orderedTabIDs.count else {
            return false
        }
        let replacementCount = uniqueTabIDs.intersection(replaceablePinnedTabIDs).count
        return orderedTabIDs.count - replacementCount <= availableSlots
    }
}

public struct ContentTabMoveRequest: Equatable, Sendable {
    public let operationID: UUID
    public let requestID: UUID
    public let sourceWindowID: UUID
    public let initiatingTabID: ContentTabID
    public let orderedTabIDs: [ContentTabID]
    public let targetWindowID: UUID

    public var tabID: ContentTabID {
        initiatingTabID
    }

    public init(
        operationID: UUID,
        requestID: UUID,
        sourceWindowID: UUID,
        initiatingTabID: ContentTabID,
        orderedTabIDs: [ContentTabID],
        targetWindowID: UUID,
    ) {
        self.operationID = operationID
        self.requestID = requestID
        self.sourceWindowID = sourceWindowID
        self.initiatingTabID = initiatingTabID
        self.orderedTabIDs = orderedTabIDs
        self.targetWindowID = targetWindowID
    }

    public init(
        requestID: UUID,
        sourceWindowID: UUID,
        tabID: ContentTabID,
        targetWindowID: UUID,
    ) {
        self.init(
            operationID: requestID,
            requestID: requestID,
            sourceWindowID: sourceWindowID,
            initiatingTabID: tabID,
            orderedTabIDs: [tabID],
            targetWindowID: targetWindowID,
        )
    }
}

public struct FileManagerWindowContentTabMovePending: Equatable, Sendable {
    public enum Lifecycle: Equatable, Sendable {
        case prepared
        case inFlight
    }

    public let request: ContentTabMoveRequest
    public var lifecycle: Lifecycle

    public init(
        request: ContentTabMoveRequest,
        lifecycle: Lifecycle = .prepared,
    ) {
        self.request = request
        self.lifecycle = lifecycle
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

    static func availableTargets(
        _ targets: [ContentTabMoveTarget],
        currentWindowID: UUID?,
        orderedTabIDs: [ContentTabID],
    ) -> [ContentTabMoveTarget] {
        targets.filter { target in
            target.windowID != currentWindowID && target.accepts(orderedTabIDs: orderedTabIDs)
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
