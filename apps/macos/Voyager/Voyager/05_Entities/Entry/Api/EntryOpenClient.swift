import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

public struct EntryOpenClient: Sendable {
    public var open: @Sendable (URL, OpenKind) async throws -> Void
    public var setDefaultApp: @Sendable (UTType, String) async throws -> Void
    public var quickLook: @Sendable (URL) async throws -> Void
    public var quickLookFiles: @Sendable ([URL]) async throws -> Void
    public var openFinderInfo: @Sendable ([URL]) async throws -> Void
    public var shareItems: @Sendable ([URL], CGPoint?) async throws -> Void
    public var performService: @Sendable (String, [URL]) async throws -> Void
    public var revealInFinder: @Sendable ([URL]) async throws -> Void
    public var applicationsForFile: @Sendable (URL) async -> [ApplicationInfo]
    public var defaultApplication: @Sendable (UTType) async -> ApplicationInfo?
    public var trashDirectoryPath: @Sendable () -> String?

    public nonisolated init(
        open: @escaping @Sendable (URL, OpenKind) async throws -> Void,
        setDefaultApp: @escaping @Sendable (UTType, String) async throws -> Void,
        quickLook: @escaping @Sendable (URL) async throws -> Void,
        quickLookFiles: @escaping @Sendable ([URL]) async throws -> Void,
        openFinderInfo: @escaping @Sendable ([URL]) async throws -> Void,
        shareItems: @escaping @Sendable ([URL], CGPoint?) async throws -> Void,
        performService: @escaping @Sendable (String, [URL]) async throws -> Void,
        revealInFinder: @escaping @Sendable ([URL]) async throws -> Void,
        applicationsForFile: @escaping @Sendable (URL) async -> [ApplicationInfo],
        defaultApplication: @escaping @Sendable (UTType) async -> ApplicationInfo?,
        trashDirectoryPath: @escaping @Sendable () -> String?,
    ) {
        self.open = open
        self.setDefaultApp = setDefaultApp
        self.quickLook = quickLook
        self.quickLookFiles = quickLookFiles
        self.openFinderInfo = openFinderInfo
        self.shareItems = shareItems
        self.performService = performService
        self.revealInFinder = revealInFinder
        self.applicationsForFile = applicationsForFile
        self.defaultApplication = defaultApplication
        self.trashDirectoryPath = trashDirectoryPath
    }
}

extension EntryOpenClient: DependencyKey {
    public nonisolated static var liveValue: EntryOpenClient {
        EntryOpenClient(
            open: EntrySystemPrimitives.liveOpen,
            setDefaultApp: EntrySystemPrimitives.liveSetDefaultApp,
            quickLook: EntrySystemPrimitives.liveQuickLook,
            quickLookFiles: EntrySystemPrimitives.liveQuickLookFiles,
            openFinderInfo: EntrySystemPrimitives.liveOpenFinderInfo,
            shareItems: EntrySystemPrimitives.liveShareItems,
            performService: EntrySystemPrimitives.livePerformService,
            revealInFinder: EntrySystemPrimitives.liveRevealInFinder,
            applicationsForFile: EntrySystemPrimitives.liveApplicationsForFile,
            defaultApplication: EntrySystemPrimitives.liveDefaultApplication,
            trashDirectoryPath: EntrySystemPrimitives.liveTrashDirectoryPath,
        )
    }

    public nonisolated static var testValue: EntryOpenClient {
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("EntryOpenClient test dependency not set.")
        }
        return EntryOpenClient(
            open: { _, _ in unimplemented() },
            setDefaultApp: { _, _ in unimplemented() },
            quickLook: { _ in unimplemented() },
            quickLookFiles: { _ in unimplemented() },
            openFinderInfo: { _ in unimplemented() },
            shareItems: { _, _ in unimplemented() },
            performService: { _, _ in unimplemented() },
            revealInFinder: { _ in unimplemented() },
            applicationsForFile: { _ in unimplemented() },
            defaultApplication: { _ in unimplemented() },
            trashDirectoryPath: { nil },
        )
    }

    public nonisolated static var previewValue: EntryOpenClient {
        let previewInfo = ApplicationInfo(
            id: "com.apple.preview",
            name: "Preview",
            bundleID: "com.apple.preview",
        )
        let chromeInfo = ApplicationInfo(id: "com.google.Chrome", name: "Google Chrome", bundleID: "com.google.Chrome")
        let otherInfo = ApplicationInfo(id: "other", name: "Other…", bundleID: nil)

        return EntryOpenClient(
            open: { _, _ in },
            setDefaultApp: { _, _ in },
            quickLook: { _ in },
            quickLookFiles: { _ in },
            openFinderInfo: { _ in },
            shareItems: { _, _ in },
            performService: { _, _ in },
            revealInFinder: { _ in },
            applicationsForFile: { _ async in
                [previewInfo, chromeInfo, otherInfo]
            },
            defaultApplication: { _ async in
                previewInfo
            },
            trashDirectoryPath: { nil },
        )
    }
}

public extension DependencyValues {
    nonisolated var entryOpenClient: EntryOpenClient {
        get { self[EntryOpenClient.self] }
        set { self[EntryOpenClient.self] = newValue }
    }
}
