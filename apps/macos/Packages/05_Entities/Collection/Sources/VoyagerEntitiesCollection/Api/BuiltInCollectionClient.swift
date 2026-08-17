import ComposableArchitecture
import Foundation
import VoyagerShared

public struct BuiltInCollectionDescriptor: Equatable, Sendable {
    public let identity: BuiltInCollectionIdentity
    public let packageURL: URL

    public init(identity: BuiltInCollectionIdentity, packageURL: URL) {
        self.identity = identity
        self.packageURL = packageURL
    }
}

public enum BuiltInCollectionEnsureItemResult: Equatable, Sendable {
    case ready(BuiltInCollectionDescriptor)
    case deferred
    case failed
}

public struct BuiltInCollectionEnsureReport: Equatable, Sendable {
    public let recents: BuiltInCollectionEnsureItemResult
    public let allTags: BuiltInCollectionEnsureItemResult

    public init(
        recents: BuiltInCollectionEnsureItemResult,
        allTags: BuiltInCollectionEnsureItemResult,
    ) {
        self.recents = recents
        self.allTags = allTags
    }
}

public struct BuiltInCollectionClient: Sendable {
    public var ensureAll: @Sendable (
        _ recentsContext: CollectionContext,
        _ allTagsContext: CollectionContext?,
    ) async -> BuiltInCollectionEnsureReport

    public init(
        ensureAll: @escaping @Sendable (
            _ recentsContext: CollectionContext,
            _ allTagsContext: CollectionContext?,
        ) async -> BuiltInCollectionEnsureReport,
    ) {
        self.ensureAll = ensureAll
    }
}

extension BuiltInCollectionClient: DependencyKey {
    public static let liveValue: BuiltInCollectionClient = {
        let coordinator = BuiltInCollectionEnsureCoordinator()
        return BuiltInCollectionClient(
            ensureAll: { recentsContext, allTagsContext in
                @Dependency(\.collectionFileClient)
                var collectionFileClient
                @Dependency(\.collectionMetricClient)
                var collectionMetricClient
                @Dependency(\.date)
                var date
                @Dependency(\.fileManagerClient)
                var fileManagerClient

                do {
                    return try await coordinator.run {
                        let dependencies = InvocationDependencies(
                            collectionFileClient: collectionFileClient,
                            fileManagerClient: fileManagerClient,
                            metricsClient: collectionMetricClient,
                            now: date.now,
                        )
                        return await ensureBuiltInCollections(
                            recentsContext: recentsContext,
                            allTagsContext: allTagsContext,
                            dependencies: dependencies,
                        )
                    }
                } catch {
                    return BuiltInCollectionEnsureReport(recents: .failed, allTags: .failed)
                }
            },
        )
    }()

    public static let testValue = BuiltInCollectionClient(
        ensureAll: { _, _ in
            BuiltInCollectionEnsureReport(recents: .failed, allTags: .failed)
        },
    )
}

public extension DependencyValues {
    var builtInCollectionClient: BuiltInCollectionClient {
        get { self[BuiltInCollectionClient.self] }
        set { self[BuiltInCollectionClient.self] = newValue }
    }
}

private extension BuiltInCollectionClient {
    enum ExistingPackageState {
        case healthy
        case missing
        case corrupt
        case stale(createdAt: Date)
    }

    enum EnsureError: Error {
        case invalidCanonicalCondition
        case postSaveVerificationFailed
        case rootPreparationFailed
    }

    struct InvocationDependencies {
        let collectionFileClient: CollectionFileClient
        let fileManagerClient: FileManagerClient
        let metricsClient: CollectionMetricClient
        let now: Date
    }

    struct EnsureDependencies {
        let collectionFileClient: CollectionFileClient
        let fileManagerClient: FileManagerClient
        let metricsClient: CollectionMetricClient
        let now: Date
        let applicationSupportURL: URL
        let managedRootURL: URL
    }

    static func ensureBuiltInCollections(
        recentsContext: CollectionContext,
        allTagsContext: CollectionContext?,
        dependencies invocation: InvocationDependencies,
    ) async -> BuiltInCollectionEnsureReport {
        invocation.metricsClient.logMetric("built_in_collection_ensure_started")
        let dependencies: EnsureDependencies
        do {
            dependencies = try prepareEnsureDependencies(invocation)
        } catch {
            logFailure(for: .recents, metricsClient: invocation.metricsClient)
            logFailure(for: .allTags, metricsClient: invocation.metricsClient)
            return .init(recents: .failed, allTags: .failed)
        }

        let recents = await ensureItem(
            identity: .recents,
            context: recentsContext,
            dependencies: dependencies,
        )
        let allTags: BuiltInCollectionEnsureItemResult
        if let allTagsContext {
            allTags = await ensureItem(
                identity: .allTags,
                context: allTagsContext,
                dependencies: dependencies,
            )
        } else {
            dependencies.metricsClient.logMetric(
                "built_in_collection_item_deferred",
                tags: metricTags(for: .allTags, outcome: "deferred"),
            )
            allTags = .deferred
        }
        return .init(recents: recents, allTags: allTags)
    }

    static func prepareEnsureDependencies(
        _ invocation: InvocationDependencies,
    ) throws -> EnsureDependencies {
        guard let applicationSupportURL = invocation.fileManagerClient.urlsForDirectory(
            .applicationSupportDirectory,
            .userDomainMask,
        ).first else {
            throw EnsureError.rootPreparationFailed
        }
        let rootURL = BuiltInCollectionIdentity.canonicalRootURL(
            applicationSupportURL: applicationSupportURL,
        )
        _ = try BuiltInCollectionManagedPathPolicy.validateManagedRoot(
            rootURL,
            applicationSupportURL: applicationSupportURL,
            fileManagerClient: invocation.fileManagerClient,
        )
        try invocation.fileManagerClient.createDirectory(rootURL, true, nil)
        let managedRootURL = try BuiltInCollectionManagedPathPolicy.validateManagedRoot(
            rootURL,
            applicationSupportURL: applicationSupportURL,
            fileManagerClient: invocation.fileManagerClient,
        )
        return EnsureDependencies(
            collectionFileClient: invocation.collectionFileClient,
            fileManagerClient: invocation.fileManagerClient,
            metricsClient: invocation.metricsClient,
            now: invocation.now,
            applicationSupportURL: applicationSupportURL,
            managedRootURL: managedRootURL,
        )
    }

    static func ensureItem(
        identity: BuiltInCollectionIdentity,
        context: CollectionContext,
        dependencies: EnsureDependencies,
    ) async -> BuiltInCollectionEnsureItemResult {
        let packageURL = identity.canonicalPackageURL(
            applicationSupportURL: dependencies.applicationSupportURL,
        )
        let descriptor = BuiltInCollectionDescriptor(identity: identity, packageURL: packageURL)

        do {
            try BuiltInCollectionManagedPathPolicy.validateManagedPackage(
                packageURL,
                managedRootURL: dependencies.managedRootURL,
                fileManagerClient: dependencies.fileManagerClient,
            )
            let state = try await existingPackageState(
                identity: identity,
                packageURL: packageURL,
                context: context,
                dependencies: dependencies,
            )
            if case .healthy = state {
                dependencies.metricsClient.logMetric(
                    "built_in_collection_item_ensured",
                    tags: metricTags(for: identity, outcome: "ensured"),
                )
                return .ready(descriptor)
            }
            return try await repairItem(
                identity: identity,
                packageURL: packageURL,
                context: context,
                state: state,
                dependencies: dependencies,
            )
        } catch {
            logFailure(for: identity, metricsClient: dependencies.metricsClient)
            return .failed
        }
    }

    static func repairItem(
        identity: BuiltInCollectionIdentity,
        packageURL: URL,
        context: CollectionContext,
        state: ExistingPackageState,
        dependencies: EnsureDependencies,
    ) async throws -> BuiltInCollectionEnsureItemResult {
        let createdAt: Date = switch state {
        case .healthy, .missing, .corrupt:
            dependencies.now
        case let .stale(createdAt):
            createdAt
        }
        let canonicalFile = try makeCanonicalFile(
            identity: identity,
            context: context,
            createdAt: createdAt,
            updatedAt: dependencies.now,
        )
        try BuiltInCollectionManagedPathPolicy.validateManagedPackage(
            packageURL,
            managedRootURL: dependencies.managedRootURL,
            fileManagerClient: dependencies.fileManagerClient,
        )
        try await dependencies.collectionFileClient.save(canonicalFile, packageURL)
        try BuiltInCollectionManagedPathPolicy.validateManagedPackage(
            packageURL,
            managedRootURL: dependencies.managedRootURL,
            fileManagerClient: dependencies.fileManagerClient,
        )
        let verified = try await dependencies.collectionFileClient.load(packageURL).file
        guard hasCanonicalDefinition(
            verified,
            identity: identity,
            canonicalFile: canonicalFile,
        ) else {
            throw EnsureError.postSaveVerificationFailed
        }

        let metricName = switch state {
        case .healthy, .missing:
            "built_in_collection_item_ensured"
        case .corrupt, .stale:
            "built_in_collection_item_repaired"
        }
        let outcome = switch state {
        case .healthy, .missing: "ensured"
        case .corrupt, .stale: "repaired"
        }
        dependencies.metricsClient.logMetric(
            metricName,
            tags: metricTags(for: identity, outcome: outcome),
        )
        return .ready(.init(identity: identity, packageURL: packageURL))
    }

    static func existingPackageState(
        identity: BuiltInCollectionIdentity,
        packageURL: URL,
        context: CollectionContext,
        dependencies: EnsureDependencies,
    ) async throws -> ExistingPackageState {
        guard dependencies.fileManagerClient.fileExists(packageURL.path) else {
            return .missing
        }

        do {
            let loaded = try await dependencies.collectionFileClient.load(packageURL).file
            let canonicalFile = try makeCanonicalFile(
                identity: identity,
                context: context,
                createdAt: loaded.createdAt,
                updatedAt: loaded.updatedAt,
            )
            if hasCanonicalDefinition(
                loaded,
                identity: identity,
                canonicalFile: canonicalFile,
            ) {
                return .healthy
            }
            return .stale(createdAt: loaded.createdAt)
        } catch {
            return .corrupt
        }
    }

    static func makeCanonicalFile(
        identity: BuiltInCollectionIdentity,
        context: CollectionContext,
        createdAt: Date,
        updatedAt: Date,
    ) throws -> VoyagerCollectionFile {
        try VoyagerCollectionFile(
            schemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
            id: identity.rawValue,
            name: identity.collectionName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            query: context.query,
            scopes: context.scopes,
            excludedScopes: context.excludedScopes,
            includeSubfolders: context.includeSubfolders,
            includeDirectories: context.includeDirectories,
            conditions: persistedConditions(from: context.conditions),
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )
    }

    static func persistedConditions(from conditions: [Condition]) throws -> [CollectionCondition] {
        try conditions.map { condition in
            guard condition.isExecutionReady,
                  let operation = condition.operation
            else {
                throw EnsureError.invalidCanonicalCondition
            }
            if operation.valueContract.count == .fixed(0) {
                return CollectionCondition(
                    propertyKey: condition.property.key,
                    operatorCode: operation.code,
                )
            }
            guard condition.values != nil,
                  let encodedValue = ConditionCodec.encode(condition: condition)
            else {
                throw EnsureError.invalidCanonicalCondition
            }
            return CollectionCondition(
                propertyKey: condition.property.key,
                operatorCode: operation.code,
                value: encodedValue,
            )
        }
    }

    static func hasCanonicalDefinition(
        _ file: VoyagerCollectionFile,
        identity: BuiltInCollectionIdentity,
        canonicalFile: VoyagerCollectionFile,
    ) -> Bool {
        file.schemaVersion == CollectionFileSchemaVersion.definitionOnlyCurrent
            && file.id == identity.rawValue
            && file.name == identity.collectionName
            && file.query == canonicalFile.query
            && file.scopes == canonicalFile.scopes
            && file.excludedScopes == canonicalFile.excludedScopes
            && file.includeSubfolders == canonicalFile.includeSubfolders
            && file.includeDirectories == canonicalFile.includeDirectories
            && file.conditions == canonicalFile.conditions
            && file.snapshot == nil
            && file.snapshotMeta == nil
    }

    static func metricTags(
        for identity: BuiltInCollectionIdentity,
        outcome: String,
    ) -> [String: String] {
        ["identity": identity.rawValue, "outcome": outcome]
    }

    static func logFailure(
        for identity: BuiltInCollectionIdentity,
        metricsClient: CollectionMetricClient,
    ) {
        metricsClient.logMetric(
            "built_in_collection_item_failed",
            tags: metricTags(for: identity, outcome: "failed"),
        )
    }
}

actor BuiltInCollectionEnsureCoordinator {
    private typealias WaiterContinuation = CheckedContinuation<Void, any Error>

    private struct Waiter {
        let id: Int
        let continuation: WaiterContinuation
    }

    private var isRunning = false
    private var nextWaiterID = 0
    private var waiters: [Waiter] = []

    var queuedOperationCount: Int {
        waiters.count
    }

    func run<T: Sendable>(_ operation: @Sendable () async -> T) async throws -> T {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if !isRunning {
            isRunning = true
            return
        }

        let waiterID = nextWaiterID
        nextWaiterID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: WaiterContinuation) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: waiterID, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
    }

    private func cancelWaiter(_ waiterID: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release() {
        guard !waiters.isEmpty else {
            isRunning = false
            return
        }
        waiters.removeFirst().continuation.resume()
    }
}
