import ComposableArchitecture
import Foundation
import VoyagerShared

public struct HelperFolderAccessClient: Sendable {
    public var checkAccess: @Sendable () async -> FolderAccessResult
    public var requestAccess: @Sendable () async -> FolderAccessResult

    public nonisolated init(
        checkAccess: @escaping @Sendable () async -> FolderAccessResult,
        requestAccess: @escaping @Sendable () async -> FolderAccessResult,
    ) {
        self.checkAccess = checkAccess
        self.requestAccess = requestAccess
    }
}

extension HelperFolderAccessClient: DependencyKey {
    public nonisolated static var liveValue: HelperFolderAccessClient {
        let resolver = HelperFolderAccessResolver()
        return HelperFolderAccessClient(
            checkAccess: {
                await resolver.resolve(mode: .check)
            },
            requestAccess: {
                await resolver.resolve(mode: .request)
            },
        )
    }

    public nonisolated static var testValue: HelperFolderAccessClient {
        let fallback = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        return HelperFolderAccessClient(
            checkAccess: { fallback },
            requestAccess: { fallback },
        )
    }

    public nonisolated static var previewValue: HelperFolderAccessClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var helperFolderAccessClient: HelperFolderAccessClient {
        get { self[HelperFolderAccessClient.self] }
        set { self[HelperFolderAccessClient.self] = newValue }
    }
}

private actor HelperFolderAccessResolver {
    fileprivate enum Mode: String {
        case check
        case request
    }

    private let fallbackResult = FolderAccessResult(
        desktop: .notGranted,
        documents: .notGranted,
        downloads: .notGranted,
    )

    private var waiters: [CheckedContinuation<FolderAccessResult, Never>] = []
    private var observer: NotificationObserver?
    private var timeoutTask: Task<Void, Never>?

    deinit {
        timeoutTask?.cancel()
        guard let observer else { return }
        Task { @MainActor in
            DistributedNotificationCenter.default().removeObserver(observer.token)
        }
    }

    fileprivate func resolve(mode: Mode) async -> FolderAccessResult {
        await ensureObserver()

        if waiters.isEmpty {
            await sendRequest(mode: mode)
            scheduleTimeout()
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func ensureObserver() async {
        guard observer == nil else { return }

        let token = await MainActor.run {
            let token = DistributedNotificationCenter.default().addObserver(
                forName: HelperFolderAccessContract.responseName,
                object: nil,
                queue: .main,
            ) { [weak self] notification in
                guard let self else { return }
                let result = Self.parseResult(from: notification.userInfo)
                Task {
                    await self.resolveAll(with: result ?? self.fallbackResult)
                }
            }
            return NotificationObserver(token: token)
        }

        observer = token
    }

    private func sendRequest(mode: Mode) async {
        await MainActor.run {
            DistributedNotificationCenter.default().post(
                name: HelperFolderAccessContract.requestName,
                object: nil,
                userInfo: [
                    HelperFolderAccessUserInfoKey.schemaVersion: 1,
                    HelperFolderAccessUserInfoKey.mode: mode.rawValue,
                ],
            )
        }
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await self?.resolveAll(with: self?.fallbackResult ?? FolderAccessResult(
                desktop: .notGranted,
                documents: .notGranted,
                downloads: .notGranted,
            ))
        }
    }

    private func resolveAll(with result: FolderAccessResult) {
        timeoutTask?.cancel()
        timeoutTask = nil

        guard !waiters.isEmpty else { return }
        let currentWaiters = waiters
        waiters.removeAll()
        currentWaiters.forEach { $0.resume(returning: result) }
    }

    private nonisolated static func parseResult(from userInfo: [AnyHashable: Any]?) -> FolderAccessResult? {
        guard let userInfo else { return nil }

        if let schemaVersion = parseInt(userInfo[HelperFolderAccessUserInfoKey.schemaVersion]), schemaVersion != 1 {
            return nil
        }

        guard
            let desktop = parsePermission(userInfo[HelperFolderAccessUserInfoKey.desktop]),
            let documents = parsePermission(userInfo[HelperFolderAccessUserInfoKey.documents]),
            let downloads = parsePermission(userInfo[HelperFolderAccessUserInfoKey.downloads])
        else {
            return nil
        }

        return FolderAccessResult(desktop: desktop, documents: documents, downloads: downloads)
    }

    private nonisolated static func parsePermission(_ value: Any?) -> FolderAccessPermission? {
        guard let rawValue = value as? String else { return nil }
        switch rawValue {
        case FolderAccessPermission.granted.rawValue:
            return .granted
        case FolderAccessPermission.notGranted.rawValue:
            return .notGranted
        default:
            return nil
        }
    }

    private nonisolated static func parseInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }
}

private struct NotificationObserver: @unchecked Sendable {
    let token: NSObjectProtocol
}
