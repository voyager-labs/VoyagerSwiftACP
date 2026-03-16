import AppKit
import ComposableArchitecture
import Foundation

/// NSPasteboard 관련 primitive 기능을 제공하는 Client
/// Domain semantics는 포함하지 않고 순수 pasteboard primitive만 노출합니다.
public struct PasteboardClient: Sendable {
    public var changeCount: @Sendable () -> Int
    public var clearContents: @Sendable () -> Void
    public var writeObjects: @Sendable ([any NSPasteboardWriting]) -> Bool
    public var readObjects:
        @Sendable (
            [any NSPasteboardReading.Type],
            [NSPasteboard.ReadingOptionKey: Any]?,
        ) -> [any NSPasteboardReading]?
    public var setString: @Sendable (String, NSPasteboard.PasteboardType) -> Bool
    public var string: @Sendable (NSPasteboard.PasteboardType) -> String?

    public nonisolated init(
        changeCount: @escaping @Sendable () -> Int,
        clearContents: @escaping @Sendable () -> Void,
        writeObjects: @escaping @Sendable ([any NSPasteboardWriting]) -> Bool,
        readObjects: @escaping @Sendable (
            [any NSPasteboardReading.Type],
            [NSPasteboard.ReadingOptionKey: Any]?,
        ) -> [any NSPasteboardReading]?,
        setString: @escaping @Sendable (String, NSPasteboard.PasteboardType) -> Bool,
        string: @escaping @Sendable (NSPasteboard.PasteboardType) -> String?,
    ) {
        self.changeCount = changeCount
        self.clearContents = clearContents
        self.writeObjects = writeObjects
        self.readObjects = readObjects
        self.setString = setString
        self.string = string
    }
}

extension PasteboardClient: DependencyKey {
    public nonisolated static var liveValue: PasteboardClient {
        nonisolated(unsafe) let pasteboard = NSPasteboard.general
        return PasteboardClient(
            changeCount: {
                pasteboard.changeCount
            },
            clearContents: {
                pasteboard.clearContents()
            },
            writeObjects: { objects in
                pasteboard.writeObjects(objects)
            },
            readObjects: { classes, options in
                pasteboard.readObjects(forClasses: classes, options: options) as? [any NSPasteboardReading]
            },
            setString: { string, type in
                pasteboard.setString(string, forType: type)
            },
            string: { type in
                pasteboard.string(forType: type)
            },
        )
    }

    public nonisolated static var testValue: PasteboardClient {
        PasteboardClient(
            changeCount: { 0 },
            clearContents: {},
            writeObjects: { _ in false },
            readObjects: { _, _ in nil },
            setString: { _, _ in false },
            string: { _ in nil },
        )
    }

    public nonisolated static var previewValue: PasteboardClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var pasteboardClient: PasteboardClient {
        get { self[PasteboardClient.self] }
        set { self[PasteboardClient.self] = newValue }
    }
}
