import AppKit
import ComposableArchitecture
import CoreServices
import Foundation
import UniformTypeIdentifiers

public struct DefaultFileViewerClient: Sendable {
    public var diagnose: @Sendable () async -> DefaultFileViewerStatus
    public var setVoyagerAsDefault: @Sendable () async throws -> Void
    public var restoreFinder: @Sendable () async throws -> Void

    public init(
        diagnose: @escaping @Sendable () async -> DefaultFileViewerStatus,
        setVoyagerAsDefault: @escaping @Sendable () async throws -> Void,
        restoreFinder: @escaping @Sendable () async throws -> Void,
    ) {
        self.diagnose = diagnose
        self.setVoyagerAsDefault = setVoyagerAsDefault
        self.restoreFinder = restoreFinder
    }
}

extension DefaultFileViewerClient: DependencyKey {
    nonisolated public static var liveValue: DefaultFileViewerClient {
        DefaultFileViewerClient(
            diagnose: { await DefaultFileViewerLive.diagnose() },
            setVoyagerAsDefault: { try await DefaultFileViewerLive.setVoyagerAsDefault() },
            restoreFinder: { try await DefaultFileViewerLive.restoreFinder() },
        )
    }

    nonisolated public static var testValue: DefaultFileViewerClient {
        // fatalError 패턴 — EntryOpenClient L57-72 참고. mock 없이 호출되면 크래시.
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("DefaultFileViewerClient test dependency not set.")
        }
        return DefaultFileViewerClient(
            diagnose: { unimplemented() },
            setVoyagerAsDefault: { unimplemented() },
            restoreFinder: { unimplemented() },
        )
    }

    nonisolated public static var previewValue: DefaultFileViewerClient {
        DefaultFileViewerClient(
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

private enum DefaultFileViewerLive {
    static func diagnose() async -> DefaultFileViewerStatus {
        let nsFileViewer = UserDefaults.standard.string(forKey: "NSFileViewer")
        let lsHandlerBundleID: String? = {
            guard let url = LSCopyDefaultApplicationURLForContentType(
                UTType.folder.identifier as CFString,
                .all,
                nil,
            )?.takeRetainedValue() as URL? else { return nil }
            return Bundle(url: url)?.bundleIdentifier
        }()

        let ourBundleID = Bundle.main.bundleIdentifier ?? "fm.voyager.Voyager"

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

    static func setVoyagerAsDefault() async throws {
        let bundleID = Bundle.main.bundleIdentifier ?? "fm.voyager.Voyager"

        // 1단계: NSFileViewer write. 실패 시 throw, LSHandler 건너뜀.
        try writeDefaults(key: "NSFileViewer", value: bundleID)

        // 2단계: LSHandler set. 실패 시 partialWrite throw (NSFileViewer는 성공했으므로).
        let status = LSSetDefaultRoleHandlerForContentType(
            UTType.folder.identifier as CFString,
            .all,
            bundleID as CFString,
        )
        guard status == noErr else {
            throw DefaultFileViewerError.partialWrite(
                message: "NSFileViewer was set but LSHandler registration failed (OSStatus: \(status))",
            )
        }
    }

    static func restoreFinder() async throws {
        // 1단계: NSFileViewer delete (이미 없어도 에러 아님)
        deleteDefaults(key: "NSFileViewer")

        // 2단계: LSHandler → Finder
        let status = LSSetDefaultRoleHandlerForContentType(
            UTType.folder.identifier as CFString,
            .all,
            "com.apple.finder" as CFString,
        )
        guard status == noErr else {
            throw DefaultFileViewerError.systemError(
                "Failed to set Finder as LSHandler (OSStatus: \(status))",
            )
        }
    }

    /// `/usr/bin/defaults write -g <key> <value>` 동기 실행
    private static func writeDefaults(key: String, value: String) throws {
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
                throw DefaultFileViewerError.permissionDenied
            }
            throw DefaultFileViewerError.systemError("defaults write failed: \(errMsg)")
        }
    }

    /// `/usr/bin/defaults delete -g <key>` — 존재하지 않아도 에러 아님
    private static func deleteDefaults(key: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["delete", "-g", key]
        do { try process.run() } catch { return }
        process.waitUntilExit()
        // ponytail: terminationStatus != 0 (pair does not exist) → 정상, 무시
    }
}
