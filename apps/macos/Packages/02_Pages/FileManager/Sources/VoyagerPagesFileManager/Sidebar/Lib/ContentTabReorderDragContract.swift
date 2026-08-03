import AppKit
import Dispatch
import Foundation
import UniformTypeIdentifiers

struct ContentTabReorderDragScopeID: Hashable, Codable {
    let rawValue: UUID

    init() {
        rawValue = UUID()
    }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

struct ContentTabReorderDragPayload: Codable, Equatable {
    let sourceID: ContentTabID
    let dragScopeID: ContentTabReorderDragScopeID
}

struct ContentTabReorderDragSourceConfiguration {
    let payload: ContentTabReorderDragPayload?
    let movePayload: ContentTabDragPayload?
    let sessionStore: ContentTabReorderLocalSessionStore

    init(
        payload: ContentTabReorderDragPayload,
        sessionStore: ContentTabReorderLocalSessionStore,
        movePayload: ContentTabDragPayload? = nil,
    ) {
        self.payload = payload
        self.movePayload = movePayload
        self.sessionStore = sessionStore
    }

    init(
        movePayload: ContentTabDragPayload,
        sessionStore: ContentTabReorderLocalSessionStore,
    ) {
        payload = nil
        self.movePayload = movePayload
        self.sessionStore = sessionStore
    }
}

extension UTType {
    static let contentTabReorder = UTType(
        exportedAs: "fm.voyager.content-tab-reorder",
        conformingTo: .data,
    )

    static let contentTabReorderLocal = UTType(
        exportedAs: "fm.voyager.content-tab-reorder.local",
        conformingTo: .data,
    )
}

extension NSPasteboard.PasteboardType {
    static let contentTabReorder = Self(UTType.contentTabReorder.identifier)
    static let contentTabReorderLocal = Self(UTType.contentTabReorderLocal.identifier)
    static let contentTabMove = Self(ContentTabDragPayload.contentType.identifier)
}

struct ContentTabReorderLocalToken: Equatable {
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
final class ContentTabReorderLocalSessionStore {
    struct Entry: Equatable {
        let token: ContentTabReorderLocalToken
        let payload: ContentTabReorderDragPayload
        let issuedAtNanoseconds: UInt64
        let expiresAtNanoseconds: UInt64
    }

    nonisolated static let defaultTimeToLiveNanoseconds: UInt64 = 60_000_000_000

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
        payload: ContentTabReorderDragPayload,
        token: ContentTabReorderLocalToken = ContentTabReorderLocalToken(rawValue: UUID()),
    ) -> ContentTabReorderLocalToken {
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

    func consume(token: ContentTabReorderLocalToken) -> ContentTabReorderDragPayload? {
        guard let entry,
              entry.token == token,
              nowNanoseconds() < entry.expiresAtNanoseconds
        else {
            return nil
        }
        self.entry = nil
        return entry.payload
    }

    func clear(token: ContentTabReorderLocalToken) {
        guard entry?.token == token else { return }
        entry = nil
    }

    func clear() {
        entry = nil
    }
}

final class ContentTabReorderPasteboardWriter: NSObject, NSPasteboardWriting {
    let token: ContentTabReorderLocalToken?

    private let reorderPayloadData: Data?
    private let movePayloadData: Data?
    private let sessionStore: ContentTabReorderLocalSessionStore

    @MainActor
    convenience init(
        payload: ContentTabReorderDragPayload,
        sessionStore: ContentTabReorderLocalSessionStore,
        token: ContentTabReorderLocalToken = ContentTabReorderLocalToken(rawValue: UUID()),
    ) throws {
        try self.init(
            configuration: ContentTabReorderDragSourceConfiguration(
                payload: payload,
                sessionStore: sessionStore,
            ),
            token: token,
        )
    }

    @MainActor
    init(
        configuration: ContentTabReorderDragSourceConfiguration,
        token: ContentTabReorderLocalToken = ContentTabReorderLocalToken(rawValue: UUID()),
    ) throws {
        reorderPayloadData = try configuration.payload.map(JSONEncoder().encode)
        movePayloadData = try configuration.movePayload.map(JSONEncoder().encode)
        sessionStore = configuration.sessionStore
        if let payload = configuration.payload {
            self.token = sessionStore.begin(payload: payload, token: token)
        } else {
            self.token = nil
        }
        super.init()
    }

    func writableTypes(for _: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types: [NSPasteboard.PasteboardType] = []
        if reorderPayloadData != nil {
            types.append(contentsOf: [.contentTabReorder, .contentTabReorderLocal])
        }
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
        case .contentTabReorder:
            reorderPayloadData
        case .contentTabReorderLocal:
            token?.data
        case .contentTabMove:
            movePayloadData
        default:
            nil
        }
    }

    @MainActor
    func cleanupOwnedToken() {
        guard let token else { return }
        sessionStore.clear(token: token)
    }
}

enum ContentTabReorderItemProviderFactory {
    @MainActor
    static func makeProvider(
        payload: ContentTabReorderDragPayload,
        sessionStore: ContentTabReorderLocalSessionStore,
        token: ContentTabReorderLocalToken = ContentTabReorderLocalToken(rawValue: UUID()),
    ) throws -> NSItemProvider {
        let payloadData = try JSONEncoder().encode(payload)
        let localToken = sessionStore.begin(payload: payload, token: token)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.contentTabReorder.identifier,
            visibility: .all,
        ) { completion in
            completion(payloadData, nil)
            return completedProgress()
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.contentTabReorderLocal.identifier,
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
