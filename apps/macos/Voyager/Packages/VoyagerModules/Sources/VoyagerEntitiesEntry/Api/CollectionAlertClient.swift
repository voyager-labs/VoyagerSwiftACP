import ComposableArchitecture

public struct CollectionAlertClient: Sendable {
    public var showUnsavedNavigationAlert: @Sendable () async -> CollectionNavigationChoice
    public var showCollectionOpenErrorAlert: @Sendable (_ title: String, _ message: String) async -> Void

    public init(
        showUnsavedNavigationAlert: @escaping @Sendable () async -> CollectionNavigationChoice,
        showCollectionOpenErrorAlert: @escaping @Sendable (_ title: String, _ message: String) async -> Void,
    ) {
        self.showUnsavedNavigationAlert = showUnsavedNavigationAlert
        self.showCollectionOpenErrorAlert = showCollectionOpenErrorAlert
    }
}

extension CollectionAlertClient: DependencyKey {
    public static let liveValue: CollectionAlertClient = .init(
        showUnsavedNavigationAlert: { .cancel },
        showCollectionOpenErrorAlert: { _, _ in },
    )

    public nonisolated(unsafe) static var testValue: CollectionAlertClient = .init(
        showUnsavedNavigationAlert: { .cancel },
        showCollectionOpenErrorAlert: { _, _ in },
    )
}

extension CollectionAlertClient: TestDependencyKey {}

public extension DependencyValues {
    var collectionAlertClient: CollectionAlertClient {
        get { self[CollectionAlertClient.self] }
        set { self[CollectionAlertClient.self] = newValue }
    }
}
