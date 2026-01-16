import ComposableArchitecture
import Foundation

public struct EntryCapabilities: Equatable, Sendable {
    public var supportsDefaultAppManagement: Bool

    public nonisolated init(supportsDefaultAppManagement: Bool = true) {
        self.supportsDefaultAppManagement = supportsDefaultAppManagement
    }
}

extension EntryCapabilities: DependencyKey {
    public nonisolated static var liveValue: EntryCapabilities { EntryCapabilities() }
    public nonisolated static var testValue: EntryCapabilities { EntryCapabilities() }
    public nonisolated static var previewValue: EntryCapabilities { EntryCapabilities() }
}

public extension DependencyValues {
    nonisolated var entryCapabilities: EntryCapabilities {
        get { self[EntryCapabilities.self] }
        set { self[EntryCapabilities.self] = newValue }
    }
}
