import AppKit
import ComposableArchitecture
import CoreServices
import Foundation
import UniformTypeIdentifiers

public struct DefaultFileViewerClient: Sendable {
    /// 이 클라이언트가 "기본 뷰어"로 다루어야 할 앱의 bundle ID.
    /// 호스트 셸(`SettingsHost` 등)이 자신의 bundle ID로 오염되는 것을 막기 위해
    /// `Bundle.main` 해석은 `liveValue`에서 한 번만 수행하고, 이후 클로저는 이 값을 참조.
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
        // ponytail: Page 패키지 내부 로직이 Bundle.main을 직접 해석하지 않도록
        // liveValue에서만 한 번 읽어 클로저에 주입. 호스트 셸에서 override 시 다른 값 사용 가능.
        let appBundleID = Bundle.main.bundleIdentifier ?? "fm.voyager.Voyager"
        return DefaultFileViewerClient(
            appBundleID: appBundleID,
            diagnose: { await DefaultFileViewerLive.diagnose(appBundleID: appBundleID) },
            setVoyagerAsDefault: { try await DefaultFileViewerLive.setVoyagerAsDefault(appBundleID: appBundleID) },
            restoreFinder: { try await DefaultFileViewerLive.restoreFinder() },
        )
    }

    nonisolated public static var testValue: DefaultFileViewerClient {
        // fatalError 패턴 — EntryOpenClient L57-72 참고. mock 없이 호출되면 크래시.
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("DefaultFileViewerClient test dependency not set.")
        }
        return DefaultFileViewerClient(
            appBundleID: "fm.voyager.Voyager",
            diagnose: { unimplemented() },
            setVoyagerAsDefault: { unimplemented() },
            restoreFinder: { unimplemented() },
        )
    }

    nonisolated public static var previewValue: DefaultFileViewerClient {
        DefaultFileViewerClient(
            appBundleID: "fm.voyager.Voyager",
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
    static func diagnose(appBundleID: String) async -> DefaultFileViewerStatus {
        let nsFileViewer = UserDefaults.standard.string(forKey: "NSFileViewer")
        let lsHandlerBundleID: String? = {
            guard let url = LSCopyDefaultApplicationURLForContentType(
                UTType.folder.identifier as CFString,
                .all,
                nil,
            )?.takeRetainedValue() as URL? else { return nil }
            return Bundle(url: url)?.bundleIdentifier
        }()

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

    static func setVoyagerAsDefault(appBundleID: String) async throws {
        let bundleID = appBundleID

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
        // 1단계: NSFileViewer delete. 실패(권한/디스크 등) 시 즉시 throw — LSHandler는 건너뛴다.
        // 키가 원래 없는 경우는 deleteDefaults 내부에서 정상으로 간주.
        try deleteDefaults(key: "NSFileViewer")

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

    /// `/usr/bin/defaults delete -g <key>`. 키가 원래 없는 경우는 정상 종료.
    /// 그 외 실패(권한/디스크/CFPreferences)는 throw — writeDefaults와 대칭.
    private static func deleteDefaults(key: String) throws {
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
            throw DefaultFileViewerError.permissionDenied
        }
        throw DefaultFileViewerError.systemError("defaults delete failed: \(errMsg)")
    }
}
