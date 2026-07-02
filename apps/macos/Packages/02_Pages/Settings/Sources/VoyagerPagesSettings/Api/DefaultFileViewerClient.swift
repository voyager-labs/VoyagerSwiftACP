import AppKit
import ComposableArchitecture
import CoreServices
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesEntry

public struct DefaultFileViewerClient: Sendable {
    /// 이 클라이언트가 "기본 뷰어"로 다루어야 할 앱의 bundle ID.
    /// 호스트 셸(`SettingsHost` 등)이 자신의 bundle ID로 오염되는 것을 막기 위해
    /// 기본값은 실제 Voyager 앱 bundle ID로 고정한다.
    public static let voyagerBundleID = "fm.voyager.Voyager"

    public var appBundleID: String
    public var diagnose: @Sendable () async -> DefaultFileViewerStatus
    public var setVoyagerAsDefault: @Sendable () async throws -> Void
    public var restoreFinder: @Sendable () async throws -> Void

    public init(
        appBundleID: String,
        diagnose: @escaping @Sendable () async -> DefaultFileViewerStatus,
        setVoyagerAsDefault: @escaping @Sendable () async throws -> Void,
        restoreFinder: @escaping @Sendable () async throws -> Void,
    ) {
        self.appBundleID = appBundleID
        self.diagnose = diagnose
        self.setVoyagerAsDefault = setVoyagerAsDefault
        self.restoreFinder = restoreFinder
    }
}

extension DefaultFileViewerClient: DependencyKey {
    nonisolated public static var liveValue: DefaultFileViewerClient {
        // ponytail: 호스트 셸 Bundle.main은 SettingsHost일 수 있어 실제 앱 ID를 고정.
        let appBundleID = Self.voyagerBundleID
        // ponytail: Settings Reducer는 EntryOpenClient를 직접 모르게.
        // folder default-app LS 작업은 EntryOpenClient.liveValue에 위임.
        let entryOpenClient = EntryOpenClient.liveValue
        let defaultsStore = DefaultFileViewerDefaultsStore.live
        return DefaultFileViewerClient(
            appBundleID: appBundleID,
            diagnose: { await DefaultFileViewerLive.diagnose(
                appBundleID: appBundleID,
                entryOpenClient: entryOpenClient,
                defaultsStore: defaultsStore,
            )
            },
            setVoyagerAsDefault: { try await DefaultFileViewerLive.setVoyagerAsDefault(
                appBundleID: appBundleID,
                entryOpenClient: entryOpenClient,
                defaultsStore: defaultsStore,
            )
            },
            restoreFinder: { try await DefaultFileViewerLive.restoreFinder(
                entryOpenClient: entryOpenClient,
                defaultsStore: defaultsStore,
            )
            },
        )
    }

    nonisolated public static var testValue: DefaultFileViewerClient {
        // fatalError 패턴 — EntryOpenClient L57-72 참고. mock 없이 호출되면 크래시.
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("DefaultFileViewerClient test dependency not set.")
        }
        return DefaultFileViewerClient(
            appBundleID: Self.voyagerBundleID,
            diagnose: { unimplemented() },
            setVoyagerAsDefault: { unimplemented() },
            restoreFinder: { unimplemented() },
        )
    }

    nonisolated public static var previewValue: DefaultFileViewerClient {
        DefaultFileViewerClient(
            appBundleID: voyagerBundleID,
            diagnose: { .finderIsDefault },
            setVoyagerAsDefault: {},
            restoreFinder: {},
        )
    }
}

public extension DependencyValues {
    var defaultFileViewerClient: DefaultFileViewerClient {
        get { self[DefaultFileViewerClient.self] }
        set { self[DefaultFileViewerClient.self] = newValue }
    }
}

struct DefaultFileViewerDefaultsStore {
    var read: @Sendable () -> String?
    var write: @Sendable (String) throws -> Void
    var delete: @Sendable () throws -> Void

    static let live = DefaultFileViewerDefaultsStore(
        read: { readDefaults(key: defaultFileViewerDefaultsKey) },
        write: { try writeDefaults(key: defaultFileViewerDefaultsKey, value: $0) },
        delete: { try deleteDefaults(key: defaultFileViewerDefaultsKey) },
    )

    func restore(_ value: String?) throws {
        if let value {
            try write(value)
        } else {
            try delete()
        }
    }
}

private let defaultFileViewerDefaultsKey = "NSFileViewer"
private let defaultFileViewerReadFailedValue = "__voyager_default_file_viewer_read_failed__"

enum DefaultFileViewerLive {
    static func diagnose(
        appBundleID: String,
        entryOpenClient: EntryOpenClient,
        defaultsStore: DefaultFileViewerDefaultsStore = .live,
    ) async -> DefaultFileViewerStatus {
        let nsFileViewer = defaultsStore.read()
        let lsHandlerBundleID = await entryOpenClient.defaultApplication(.folder)?.bundleID

        let ourBundleID = appBundleID

        // AND 일치 원칙: NSFileViewer와 LSHandler가 모두 같은 앱이어야 해당 상태. 불일치 시 unknown.
        if nsFileViewer == ourBundleID && lsHandlerBundleID == ourBundleID {
            return .voyagerIsDefault
        }
        let nsIsFinder = nsFileViewer == nil || nsFileViewer == "com.apple.finder"
        let lsIsFinder = lsHandlerBundleID == nil || lsHandlerBundleID == "com.apple.finder"
        if nsIsFinder, lsIsFinder {
            return .finderIsDefault
        }
        if nsFileViewer == lsHandlerBundleID, let bid = nsFileViewer, bid != ourBundleID {
            return .otherIsDefault(appBundleID: bid, appDisplayName: appDisplayName(for: bid))
        }
        return .unknown
    }

    static func appDisplayName(for bundleID: String) -> String {
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?
            .takeRetainedValue() as? [URL],
            let url = urls.first
        else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    static func setVoyagerAsDefault(
        appBundleID: String,
        entryOpenClient: EntryOpenClient,
        defaultsStore: DefaultFileViewerDefaultsStore = .live,
    ) async throws {
        let bundleID = appBundleID
        let previousNSFileViewer = defaultsStore.read()

        // 1단계: NSFileViewer write. 실패 시 throw, LSHandler 건너뜀.
        try defaultsStore.write(bundleID)

        // 2단계: LSHandler set — EntryOpenClient에 위임. NSFileViewer는 이미 성공한 상태.
        do {
            try await entryOpenClient.setDefaultApp(.folder, bundleID)
        } catch {
            try rollbackNSFileViewer(defaultsStore, to: previousNSFileViewer, after: error)
            throw error
        }
    }

    static func restoreFinder(
        entryOpenClient: EntryOpenClient,
        defaultsStore: DefaultFileViewerDefaultsStore = .live,
    ) async throws {
        let previousNSFileViewer = defaultsStore.read()

        // 1단계: NSFileViewer delete. 실패(권한/디스크 등) 시 즉시 throw — LSHandler는 건너뛴다.
        // 키가 원래 없는 경우는 deleteDefaults 내부에서 정상으로 간주.
        try defaultsStore.delete()

        // 2단계: LSHandler → Finder — EntryOpenClient에 위임.
        do {
            try await entryOpenClient.setDefaultApp(.folder, "com.apple.finder")
        } catch {
            try rollbackNSFileViewer(defaultsStore, to: previousNSFileViewer, after: error)
            throw error
        }
    }

    private static func rollbackNSFileViewer(
        _ defaultsStore: DefaultFileViewerDefaultsStore,
        to value: String?,
        after originalError: Error,
    ) throws {
        do {
            try defaultsStore.restore(value)
        } catch {
            throw FileOpError.system(
                message: "Default file viewer update failed; rollback also failed: \(error)",
                suggestion: "Original error: \(originalError)",
            )
        }
    }
}

/// `/usr/bin/defaults read -g <key>` 동기 실행. 키가 없으면 Finder 기본 상태(nil)로 취급.
private func readDefaults(key: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["read", "-g", key]
    let pipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = pipe
    process.standardError = errorPipe
    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = try errorPipe.fileHandleForReading.readToEnd()
            let errMsg = String(data: errData ?? Data(), encoding: .utf8) ?? ""
            if errMsg.contains("does not exist") || errMsg.contains("Domain") { return nil }
            return defaultFileViewerReadFailedValue
        }
        let data = try pipe.fileHandleForReading.readToEnd()
        let value = String(data: data ?? Data(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    } catch {
        return defaultFileViewerReadFailedValue
    }
}

/// `/usr/bin/defaults write -g <key> <value>` 동기 실행
private func writeDefaults(key: String, value: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["write", "-g", key, value]
    let pipe = Pipe()
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let errData = try pipe.fileHandleForReading.readToEnd()
        let errMsg = String(data: errData ?? Data(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
        // Sandbox/permission 감지
        if errMsg.contains("Sandbox") || errMsg.contains("Operation not permitted") {
            throw FileOpError.system(message: "Permission denied: \(errMsg)")
        }
        throw FileOpError.system(message: "defaults write failed: \(errMsg)")
    }
}

/// `/usr/bin/defaults delete -g <key>`. 키가 원래 없는 경우는 정상 종료.
/// 그 외 실패(권한/디스크/CFPreferences)는 throw — writeDefaults와 대칭.
private func deleteDefaults(key: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["delete", "-g", key]
    let pipe = Pipe()
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus != 0 else { return }
    let errData = try pipe.fileHandleForReading.readToEnd()
    let errMsg = String(data: errData ?? Data(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
    // 정상 케이스: 키/도메인이 원래 없음 (이미 Finder 상태에서 복구 시도 등).
    if errMsg.contains("does not exist") || errMsg.contains("Domain") { return }
    // Sandbox/permission 감지
    if errMsg.contains("Sandbox") || errMsg.contains("Operation not permitted") {
        throw FileOpError.system(message: "Permission denied: \(errMsg)")
    }
    throw FileOpError.system(message: "defaults delete failed: \(errMsg)")
}
