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

    func clear() {
        entry = nil
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
