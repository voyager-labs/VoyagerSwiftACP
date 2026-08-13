import ComposableArchitecture
import Foundation

public struct AIProviderBootstrapResult: Equatable, Sendable {
    public let provider: AiProvider
    public let connectionState: ProviderConnectionState
    public let statusReason: ProviderStatusReason
    public let sourceCredential: StoredCredentialPayload?
    public let effectiveCredential: StoredCredentialPayload?

    public init(
        provider: AiProvider,
        connectionState: ProviderConnectionState,
        statusReason: ProviderStatusReason = .none,
        sourceCredential: StoredCredentialPayload? = nil,
        effectiveCredential: StoredCredentialPayload? = nil,
    ) {
        self.provider = provider
        self.connectionState = connectionState
        self.statusReason = statusReason
        self.sourceCredential = sourceCredential
        self.effectiveCredential = effectiveCredential
    }
}

public enum AIProviderBootstrapEvent: Sendable {
    case completed([AIProviderBootstrapResult])
    case verificationCompleted([AIProviderBootstrapResult])
    case connectionsFileUpdated(AIConnectionsFile)
    case failed
}

public enum AIProviderConnectionBootstrap {
    /// large_tuple 린트 위반을 피하려고 3-튜플 대신 사용하는 검증 대상 보조 타입.
    private struct VerifiableProvider {
        let catalogIndex: Int
        let provider: AiProvider
        let credential: StoredCredentialPayload
    }

    private enum PersistenceOutcome {
        case persisted(AIConnectionsFile)
        case unchanged
        case failed
    }

    public static func effect<Action: Sendable>(
        connectionsFileClient: AIConnectionsFileClient,
        verificationClient: AIProviderVerificationClient,
        mapEvent: @escaping @Sendable (AIProviderBootstrapEvent) -> Action?,
    ) -> Effect<Action> {
        .run { send in
            do {
                try await run(
                    connectionsFileClient: connectionsFileClient,
                    verificationClient: verificationClient,
                    mapEvent: mapEvent,
                    send: send,
                )
            } catch {
                guard !isCancellation(error) else { return }
                if let action = mapEvent(.failed) {
                    await send(action)
                }
            }
        }
    }

    public static func verificationResults(
        from file: AIConnectionsFile,
        verificationClient: AIProviderVerificationClient,
    ) async throws -> [AIProviderBootstrapResult] {
        // v1Catalog 순서를 복원하기 위해 인덱스와 함께 verifiable 항목을 사전 수집한다.
        let verifiable: [VerifiableProvider] = ProviderDescriptor.v1Catalog
            .enumerated()
            .compactMap { index, descriptor in
                guard let record = file.providers[descriptor.provider.rawValue],
                      shouldVerify(snapshotState: record.snapshot.lastKnownStatus),
                      let credential = record.credential
                else { return nil }
                return VerifiableProvider(
                    catalogIndex: index,
                    provider: descriptor.provider,
                    credential: credential,
                )
            }

        guard !verifiable.isEmpty else { return [] }

        // next()는 완료 순서로 반환하므로 (index, result) 튜플로 원래 순서를 추적한다.
        let collected: [(Int, AIProviderBootstrapResult)] = try await withThrowingTaskGroup(
            of: (Int, AIProviderBootstrapResult).self,
        ) { group in
            for entry in verifiable {
                group.addTask {
                    try await verify(entry, with: verificationClient)
                }
            }

            var pairs: [(Int, AIProviderBootstrapResult)] = []
            for try await pair in group {
                pairs.append(pair)
            }
            return pairs
        }

        // 완료 순서가 아니라 v1Catalog 원래 순서로 정렬하여 반환
        return collected.sorted(by: { $0.0 < $1.0 }).map(\.1)
    }

    public static func persistVerificationResults(
        _ results: [AIProviderBootstrapResult],
        file: AIConnectionsFile,
        connectionsFileClient: AIConnectionsFileClient,
    ) async -> AIConnectionsFile? {
        guard case let .persisted(file) = await persistenceOutcome(
            results,
            file: file,
            connectionsFileClient: connectionsFileClient,
        ) else { return nil }
        return file
    }

    public static func initialResults(from file: AIConnectionsFile) -> [AIProviderBootstrapResult] {
        ProviderDescriptor.v1Catalog.map { descriptor in
            let record = file.providers[descriptor.provider.rawValue]
            return initialResult(for: descriptor.provider, record: record)
        }
    }

    public static func initialResult(
        for provider: AiProvider,
        record: ProviderRecordFile?,
    ) -> AIProviderBootstrapResult {
        guard let record else {
            return AIProviderBootstrapResult(
                provider: provider,
                connectionState: .notVerified,
                statusReason: .none,
            )
        }

        guard record.credential != nil else {
            return AIProviderBootstrapResult(
                provider: provider,
                connectionState: .notVerified,
                statusReason: .missingCredential,
            )
        }

        switch record.snapshot.lastKnownStatus {
        case .disconnecting, .disconnected:
            return AIProviderBootstrapResult(
                provider: provider,
                connectionState: .disconnected,
                statusReason: .none,
            )
        case .connectInProgress:
            return AIProviderBootstrapResult(
                provider: provider,
                connectionState: .notVerified,
                statusReason: .none,
            )
        case .notVerified, .checkingStatus, .connected, .connectionFailed, .unavailable:
            return AIProviderBootstrapResult(
                provider: provider,
                connectionState: .checkingStatus,
                statusReason: .none,
            )
        }
    }

    public static func shouldVerify(snapshotState: ProviderConnectionState) -> Bool {
        switch snapshotState {
        case .connectInProgress, .disconnecting, .disconnected:
            false
        case .notVerified, .checkingStatus, .connected, .connectionFailed, .unavailable:
            true
        }
    }

    public static func verifiedResult(
        for provider: AiProvider,
        verification: AiProviderVerificationResult,
        sourceCredential: StoredCredentialPayload? = nil,
        effectiveCredential: StoredCredentialPayload? = nil,
    ) -> AIProviderBootstrapResult {
        switch verification {
        case .valid:
            AIProviderBootstrapResult(
                provider: provider,
                connectionState: .connected,
                statusReason: .none,
                sourceCredential: sourceCredential,
                effectiveCredential: effectiveCredential,
            )
        case let .invalid(reason):
            AIProviderBootstrapResult(
                provider: provider,
                connectionState: reason == .providerUnsupportedInBuild ? .unavailable : .connectionFailed,
                statusReason: reason,
                sourceCredential: sourceCredential,
                effectiveCredential: effectiveCredential,
            )
        case .networkError:
            AIProviderBootstrapResult(
                provider: provider,
                connectionState: .connectionFailed,
                statusReason: .networkUnavailable,
                sourceCredential: sourceCredential,
                effectiveCredential: effectiveCredential,
            )
        case .unsupportedProvider:
            AIProviderBootstrapResult(
                provider: provider,
                connectionState: .unavailable,
                statusReason: .providerUnsupportedInBuild,
                sourceCredential: sourceCredential,
                effectiveCredential: effectiveCredential,
            )
        }
    }

    public static func updatedConnectionsFile(
        verificationSourceFile: AIConnectionsFile,
        latestFile: AIConnectionsFile,
        applying results: [AIProviderBootstrapResult],
    ) -> AIConnectionsFile? {
        var providers = latestFile.providers
        var didUpdate = false

        for result in results {
            let providerKey = result.provider.rawValue
            guard let sourceRecord = verificationSourceFile.providers[providerKey],
                  var record = providers[providerKey],
                  record.credential != nil,
                  record.credential == result.sourceCredential ?? sourceRecord.credential
            else { continue }

            let lastErrorCode: ProviderStatusReason = result.connectionState == .connected ? .none : result.statusReason
            let credential = result.effectiveCredential ?? record.credential
            let credentialDidChange = record.credential != credential
            let snapshotDidChange = record.snapshot.lastKnownStatus != result.connectionState
                || record.snapshot.lastErrorCode != lastErrorCode
            guard credentialDidChange || snapshotDidChange else { continue }

            let snapshot = if snapshotDidChange {
                ProviderSnapshotFile(
                    lastKnownStatus: result.connectionState,
                    lastVerifiedAtMs: result.connectionState == .connected ? latestFile.updatedAtMs : nil,
                    lastErrorCode: lastErrorCode,
                )
            } else {
                record.snapshot
            }

            record = ProviderRecordFile(
                providerId: record.providerId,
                authMethod: record.authMethod,
                credential: credential,
                snapshot: snapshot,
                provenance: record.provenance,
            )
            providers[providerKey] = record
            didUpdate = true
        }

        guard didUpdate else { return nil }
        return AIConnectionsFile(
            schemaVersion: latestFile.schemaVersion,
            updatedAtMs: latestFile.updatedAtMs,
            lastUsedProviderId: latestFile.lastUsedProviderId,
            lastUsedAtMs: latestFile.lastUsedAtMs,
            providers: providers,
        )
    }

    private static func persistenceOutcome(
        _ results: [AIProviderBootstrapResult],
        file: AIConnectionsFile,
        connectionsFileClient: AIConnectionsFileClient,
    ) async -> PersistenceOutcome {
        guard !Task.isCancelled else { return .failed }
        let mutationResult: AiConnectionMutationResult?
        if let atomicUpdate = connectionsFileClient.atomicUpdate {
            mutationResult = try? await atomicUpdate { latestFile in
                updatedConnectionsFile(
                    verificationSourceFile: file,
                    latestFile: latestFile,
                    applying: results,
                ) ?? latestFile
            }
        } else {
            guard let latestFile = try? await connectionsFileClient.load() else { return .failed }
            guard let updatedFile = updatedConnectionsFile(
                verificationSourceFile: file,
                latestFile: latestFile,
                applying: results,
            ) else { return .unchanged }
            mutationResult = try? await connectionsFileClient.save(updatedFile)
        }
        switch mutationResult {
        case let .success(savedFile), let .partialSuccess(savedFile, _):
            return .persisted(savedFile)
        case .fileSystemError, nil:
            return .failed
        }
    }

    private static func run<Action: Sendable>(
        connectionsFileClient: AIConnectionsFileClient,
        verificationClient: AIProviderVerificationClient,
        mapEvent: @escaping @Sendable (AIProviderBootstrapEvent) -> Action?,
        send: Send<Action>,
    ) async throws {
        let file = try await connectionsFileClient.load()
        if let action = mapEvent(.completed(initialResults(from: file))) {
            await send(action)
        }

        let results = try await verificationResults(from: file, verificationClient: verificationClient)
        guard !results.isEmpty, !Task.isCancelled else { return }

        let persistence = await persistenceOutcome(
            results,
            file: file,
            connectionsFileClient: connectionsFileClient,
        )
        guard !Task.isCancelled else { return }
        switch persistence {
        case let .persisted(savedFile):
            if let action = mapEvent(.connectionsFileUpdated(savedFile)) {
                await send(action)
            }
        case .unchanged:
            break
        case .failed:
            return
        }
        guard !Task.isCancelled else { return }
        if let action = mapEvent(.verificationCompleted(results)) {
            await send(action)
        }
    }

    private static func verify(
        _ entry: VerifiableProvider,
        with verificationClient: AIProviderVerificationClient,
    ) async throws -> (Int, AIProviderBootstrapResult) {
        let outcome: AiProviderVerificationOutcome
        do {
            outcome = if let verifyWithCredential = verificationClient.verifyWithCredential {
                try await verifyWithCredential(entry.provider, entry.credential)
            } else {
                await AiProviderVerificationOutcome(
                    result: verificationClient.verify(entry.provider, entry.credential),
                    sourceCredential: entry.credential,
                    effectiveCredential: entry.credential,
                )
            }
        } catch {
            guard !isCancellation(error) else { throw CancellationError() }
            outcome = AiProviderVerificationOutcome(
                result: .networkError,
                sourceCredential: entry.credential,
                effectiveCredential: entry.credential,
            )
        }
        let result = verifiedResult(
            for: entry.provider,
            verification: outcome.result,
            sourceCredential: outcome.sourceCredential,
            effectiveCredential: outcome.effectiveCredential,
        )
        return (entry.catalogIndex, result)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
