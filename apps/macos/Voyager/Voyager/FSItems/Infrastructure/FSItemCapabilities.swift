import ComposableArchitecture
import Foundation

public struct FSItemCapabilities: Equatable, Sendable {
    public var supportsDefaultAppManagement: Bool

    public nonisolated init(supportsDefaultAppManagement: Bool = true) {
        self.supportsDefaultAppManagement = supportsDefaultAppManagement
    }
}

extension FSItemCapabilities: DependencyKey {
    public nonisolated static var liveValue: FSItemCapabilities { FSItemCapabilities() }
    public nonisolated static var testValue: FSItemCapabilities { FSItemCapabilities() }
    public nonisolated static var previewValue: FSItemCapabilities { FSItemCapabilities() }
}

public extension DependencyValues {
    nonisolated var fsItemCapabilities: FSItemCapabilities {
        get { self[FSItemCapabilities.self] }
        set { self[FSItemCapabilities.self] = newValue }
    }
}
