import AppKit
import ComposableArchitecture
import Foundation

public struct LoginURLClient: Sendable {
    public var openLoginURL: @Sendable (URL) -> Void

    public nonisolated init(openLoginURL: @escaping @Sendable (URL) -> Void) {
        self.openLoginURL = openLoginURL
    }
}

extension LoginURLClient: DependencyKey {
    public nonisolated static var liveValue: LoginURLClient {
        LoginURLClient { url in
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
    }

    public nonisolated static var testValue: LoginURLClient {
        LoginURLClient { _ in }
    }

    public nonisolated static var previewValue: LoginURLClient {
        LoginURLClient { _ in }
    }
}

public extension DependencyValues {
    nonisolated var loginURLClient: LoginURLClient {
        get { self[LoginURLClient.self] }
        set { self[LoginURLClient.self] = newValue }
    }
}
