import AppKit
import Dispatch
import Foundation
import UniformTypeIdentifiers

enum FileManagerTopNavigationReorderBoundaryOwner: String, Codable, Equatable {
    case topNavigation
    case unpinnedContentTabs
}

struct FileManagerTopNavigationReorderDragScopeID: Hashable, Codable {
    let rawValue: UUID
    let boundaryOwner: FileManagerTopNavigationReorderBoundaryOwner

    init(boundaryOwner: FileManagerTopNavigationReorderBoundaryOwner = .unpinnedContentTabs) {
        rawValue = UUID()
        self.boundaryOwner = boundaryOwner
    }

    init(
        rawValue: UUID,
        boundaryOwner: FileManagerTopNavigationReorderBoundaryOwner = .unpinnedContentTabs,
    ) {
        self.rawValue = rawValue
        self.boundaryOwner = boundaryOwner
    }
}

struct FileManagerTopNavigationReorderDragPayload: Codable, Equatable {
    let sourceID: FileManagerTopNavigationItemID
    let dragScopeID: FileManagerTopNavigationReorderDragScopeID
}

struct FileManagerTopNavigationReorderDragSourceConfiguration {
    let payload: FileManagerTopNavigationReorderDragPayload
    let movePayload: ContentTabDragPayload?
    let sessionStore: FileManagerTopNavigationReorderLocalSessionStore
    let prepareMovePayload: (@MainActor () -> ContentTabDragPayload?)?
    let onMovePayloadDidBegin: (@MainActor (ContentTabDragPayload) -> Void)?
    let onMovePayloadDidEnd: (@MainActor (UUID) -> Void)?

    init(
        payload: FileManagerTopNavigationReorderDragPayload,
        sessionStore: FileManagerTopNavigationReorderLocalSessionStore,
        movePayload: ContentTabDragPayload? = nil,
        prepareMovePayload: (@MainActor () -> ContentTabDragPayload?)? = nil,
        onMovePayloadDidBegin: (@MainActor (ContentTabDragPayload) -> Void)? = nil,
        onMovePayloadDidEnd: (@MainActor (UUID) -> Void)? = nil,
    ) {
        self.payload = payload
        self.movePayload = movePayload
        self.sessionStore = sessionStore
        self.prepareMovePayload = prepareMovePayload
        self.onMovePayloadDidBegin = onMovePayloadDidBegin
        self.onMovePayloadDidEnd = onMovePayloadDidEnd
    }
}

enum FileManagerTopNavigationReorderDragSourceError: Error {
    case movePayloadPreparationRejected
}

extension UTType {
    static let fileManagerTopNavigationReorder = UTType(
        exportedAs: "fm.voyager.content-tab-reorder",
        conformingTo: .data,
    )

    static let fileManagerTopNavigationReorderLocal = UTType(
        exportedAs: "fm.voyager.content-tab-reorder.local",
        conformingTo: .data,
    )
}

extension NSPasteboard.PasteboardType {
    static let fileManagerTopNavigationReorder = Self(UTType.fileManagerTopNavigationReorder.identifier)
    static let fileManagerTopNavigationReorderLocal = Self(UTType.fileManagerTopNavigationReorderLocal.identifier)
    static let contentTabMove = Self(ContentTabDragPayload.contentType.identifier)
}

struct FileManagerTopNavigationReorderLocalToken: Equatable {
    let rawValue: UUID

    var data: Data {
        Data(rawValue.uuidString.utf8)
    }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    init?(data: Data) {
        guard let value = String(data: data, encoding: .utf8),
              let uuid = UUID(uuidString: value),
              value == uuid.uuidString
        else {
            return nil
        }
        rawValue = uuid
    }
}

@MainActor
final class FileManagerTopNavigationReorderLocalSessionStore {
    struct Entry: Equatable {
        let token: FileManagerTopNavigationReorderLocalToken
        let payload: FileManagerTopNavigationReorderDragPayload
        let issuedAtNanoseconds: UInt64
        let expiresAtNanoseconds: UInt64
    }

    nonisolated static let defaultTimeToLiveNanoseconds: UInt64 = 60_000_000_000

    /// process-local 공유 session store. 같은 process의 서로 다른 창 사이 drag에서
    /// source가 begin한 token을 target boundary drop destination이 consume할 수 있게 한다.
    /// 이 공유 store가 foreign explicit drop의 token match/replay 보증을 가능하게 한다.
    static let shared = FileManagerTopNavigationReorderLocalSessionStore()

    private let timeToLiveNanoseconds: UInt64
    private let nowNanoseconds: @MainActor () -> UInt64

    private(set) var entry: Entry?

    init(
        timeToLiveNanoseconds: UInt64 = defaultTimeToLiveNanoseconds,
        nowNanoseconds: @escaping @MainActor () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        },
    ) {
        self.timeToLiveNanoseconds = timeToLiveNanoseconds
        self.nowNanoseconds = nowNanoseconds
    }

    @discardableResult
    func begin(
        payload: FileManagerTopNavigationReorderDragPayload,
        token: FileManagerTopNavigationReorderLocalToken = FileManagerTopNavigationReorderLocalToken(rawValue: UUID()),
    ) -> FileManagerTopNavigationReorderLocalToken {
        let issuedAtNanoseconds = nowNanoseconds()
        let addition = issuedAtNanoseconds.addingReportingOverflow(timeToLiveNanoseconds)
        entry = Entry(
            token: token,
            payload: payload,
            issuedAtNanoseconds: issuedAtNanoseconds,
            expiresAtNanoseconds: addition.overflow ? .max : addition.partialValue,
        )
        return token
    }

    func consume(token: FileManagerTopNavigationReorderLocalToken) -> FileManagerTopNavigationReorderDragPayload? {
        guard let entry, entry.token == token else { return nil }
        guard nowNanoseconds() < entry.expiresAtNanoseconds else {
            self.entry = nil
            return nil
        }
        self.entry = nil
        return entry.payload
    }

    func clear(token: FileManagerTopNavigationReorderLocalToken) {
        guard entry?.token == token else { return }
        entry = nil
    }

    func clear() {
        entry = nil
    }
}

final class FileManagerTopNavigationReorderPasteboardWriter: NSObject, NSPasteboardWriting {
    let token: FileManagerTopNavigationReorderLocalToken

    private let reorderPayloadData: Data
    private let movePayloadData: Data?
    private let sessionStore: FileManagerTopNavigationReorderLocalSessionStore
    private let moveOperationID: UUID?
    private let onMovePayloadDidEnd: (@MainActor (UUID) -> Void)?
    private var didEndMovePayload = false

    @MainActor
    convenience init(
        payload: FileManagerTopNavigationReorderDragPayload,
        sessionStore: FileManagerTopNavigationReorderLocalSessionStore,
        token: FileManagerTopNavigationReorderLocalToken = FileManagerTopNavigationReorderLocalToken(rawValue: UUID()),
    ) throws {
        try self.init(
            configuration: FileManagerTopNavigationReorderDragSourceConfiguration(
                payload: payload,
                sessionStore: sessionStore,
            ),
            token: token,
        )
    }

    @MainActor
    init(
        configuration: FileManagerTopNavigationReorderDragSourceConfiguration,
        token: FileManagerTopNavigationReorderLocalToken = FileManagerTopNavigationReorderLocalToken(rawValue: UUID()),
    ) throws {
        let resolvedMovePayload = configuration.prepareMovePayload?() ?? configuration.movePayload
        if configuration.prepareMovePayload != nil, resolvedMovePayload == nil {
            throw FileManagerTopNavigationReorderDragSourceError.movePayloadPreparationRejected
        }

        reorderPayloadData = try JSONEncoder().encode(configuration.payload)
        movePayloadData = try resolvedMovePayload.map(JSONEncoder().encode)
        sessionStore = configuration.sessionStore
        moveOperationID = resolvedMovePayload?.operationID
        onMovePayloadDidEnd = configuration.onMovePayloadDidEnd
        self.token = sessionStore.begin(payload: configuration.payload, token: token)
        super.init()
        if let resolvedMovePayload {
            configuration.onMovePayloadDidBegin?(resolvedMovePayload)
        }
    }

    func writableTypes(for _: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types: [NSPasteboard.PasteboardType] = [
            .fileManagerTopNavigationReorder,
            .fileManagerTopNavigationReorderLocal,
        ]
        if movePayloadData != nil {
            types.append(.contentTabMove)
        }
        return types
    }

    func writingOptions(
        forType _: NSPasteboard.PasteboardType,
        pasteboard _: NSPasteboard,
    ) -> NSPasteboard.WritingOptions {
        []
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileManagerTopNavigationReorder:
            reorderPayloadData
        case .fileManagerTopNavigationReorderLocal:
            token.data
        case .contentTabMove:
            movePayloadData
        default:
            nil
        }
    }

    @MainActor
    func cleanupOwnedToken() {
        sessionStore.clear(token: token)
        guard !didEndMovePayload, let moveOperationID else { return }
        didEndMovePayload = true
        onMovePayloadDidEnd?(moveOperationID)
    }
}

enum FileManagerTopNavigationReorderItemProviderFactory {
    @MainActor
    static func makeProvider(
        payload: FileManagerTopNavigationReorderDragPayload,
        sessionStore: FileManagerTopNavigationReorderLocalSessionStore,
        token: FileManagerTopNavigationReorderLocalToken = FileManagerTopNavigationReorderLocalToken(rawValue: UUID()),
    ) throws -> NSItemProvider {
        let payloadData = try JSONEncoder().encode(payload)
        let localToken = sessionStore.begin(payload: payload, token: token)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileManagerTopNavigationReorder.identifier,
            visibility: .all,
        ) { completion in
            completion(payloadData, nil)
            return completedProgress()
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileManagerTopNavigationReorderLocal.identifier,
            visibility: .ownProcess,
        ) { completion in
            completion(localToken.data, nil)
            return completedProgress()
        }
        return provider
    }

    private static func completedProgress() -> Progress {
        let progress = Progress(totalUnitCount: 1)
        progress.completedUnitCount = 1
        return progress
    }
}
