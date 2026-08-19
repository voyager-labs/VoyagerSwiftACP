import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

extension WindowManagerFeature {
    func enqueueTopNavigationPersistence(
        _ request: WindowManagerTopNavigationPersistenceRequest,
        state: inout State,
    ) -> Effect<Action> {
        state.topNavigationPersistenceQueue.append(request)
        return startNextTopNavigationPersistenceIfNeeded(state: &state)
    }

    func startNextTopNavigationPersistenceIfNeeded(
        state: inout State,
    ) -> Effect<Action> {
        guard !state.isTopNavigationPersistenceInFlight,
              let request = state.topNavigationPersistenceQueue.first
        else { return .none }
        state.isTopNavigationPersistenceInFlight = true
        return runTopNavigationPersistence(request)
    }

    func runTopNavigationPersistence(
        _ request: WindowManagerTopNavigationPersistenceRequest,
    ) -> Effect<Action> {
        let client = contentTabPinnedRecordClient
        let defaults = userDefaultsClient
        return .run { send in
            let result: WindowManagerTopNavigationPersistenceResult
            do {
                result = try await Self.persistTopNavigation(request, client: client, defaults: defaults)
            } catch is CancellationError {
                result = Self.failedTopNavigationPersistence(request, failure: .cancelled)
            } catch let error as ContentTabPinnedRecordStoreLoadError {
                let failure: FileManagerTopNavigationArrangementLoadFailure = switch error {
                case .corruptUnavailable:
                    .corrupt
                case let .futureSchemaUnavailable(schemaVersion):
                    .unsupportedSchema(schemaVersion)
                }
                result = Self.failedTopNavigationPersistence(request, failure: .storeUnavailable(failure))
            } catch let error as ContentTabPinnedRecordPersistenceCommitError {
                let failure: FileManagerTopNavigationIntentFailure = switch error {
                case .superseded:
                    .superseded
                }
                result = Self.failedTopNavigationPersistence(request, failure: failure)
            } catch {
                result = Self.failedTopNavigationPersistence(request, failure: .save)
            }
            await send(.topNavigationPersistenceCompleted(result))
        }
    }

    nonisolated private static func persistTopNavigation(
        _ request: WindowManagerTopNavigationPersistenceRequest,
        client: ContentTabPinnedRecordClient,
        defaults: UserDefaultsClient,
    ) async throws -> WindowManagerTopNavigationPersistenceResult {
        switch request.operation {
        case let .move(source, destination, discoveredLocationIDs):
            let commit = try await client.moveTopNavigationItemCommitted(
                defaults,
                discoveredLocationIDs,
                source,
                destination,
            )
            return .init(
                request: request,
                terminal: .committed(commit),
                authoritativePinnedContentTabs: nil,
            )

        case let .movePinnedGroup(orderedIDs, destination, discoveredLocationIDs):
            let commit = try await client.moveTopNavigationPinnedGroupCommitted(
                defaults,
                discoveredLocationIDs,
                orderedIDs,
                destination,
            )
            return .init(
                request: request,
                terminal: .committed(commit),
                authoritativePinnedContentTabs: nil,
            )

        case .pinnedRecord:
            return try await persistedPinnedRecordResult(
                request,
                client: client,
                defaults: defaults,
            )

        case let .contentTabMove(_, mutation, discoveredLocationIDs):
            let committed = try await client.applyDurablePinnedBatchMutationCommitted(
                defaults,
                discoveredLocationIDs,
                mutation,
            )
            return .init(
                request: request,
                terminal: .committed(committed.topNavigation),
                authoritativePinnedContentTabs: ContentTabState.restoringPinnedRecords(
                    from: committed.store,
                ).state,
            )
        }
    }

    nonisolated private static func persistedPinnedRecordResult(
        _ request: WindowManagerTopNavigationPersistenceRequest,
        client: ContentTabPinnedRecordClient,
        defaults: UserDefaultsClient,
    ) async throws -> WindowManagerTopNavigationPersistenceResult {
        guard case let .pinnedRecord(source, persistenceRequest, discoveredLocationIDs) = request.operation else {
            throw ContentTabPinnedRecordPersistenceCommitError.superseded
        }
        let committed = try await persistPinnedRecord(
            source: source,
            request: persistenceRequest,
            discoveredLocationIDs: discoveredLocationIDs,
            client: client,
            defaults: defaults,
        )
        return .init(
            request: request,
            terminal: .committed(committed.topNavigation),
            authoritativePinnedContentTabs: ContentTabState.restoringPinnedRecords(from: committed.store).state,
        )
    }

    nonisolated private static func persistPinnedRecord(
        source: FileManagerPinnedRecordPersistenceSource,
        request: ContentTabPinnedRecordPersistenceRequest,
        discoveredLocationIDs: [String],
        client: ContentTabPinnedRecordClient,
        defaults: UserDefaultsClient,
    ) async throws -> ContentTabPinnedRecordPersistenceCommit {
        guard case .selectedPin = source else {
            return try await client.applyPersistenceMutationCommitted(
                defaults,
                discoveredLocationIDs,
                request.mutation,
            )
        }
        let disposition = try await client.applyPersistenceMutationCommittedGuarded(
            request.context.generation,
            defaults,
            discoveredLocationIDs: discoveredLocationIDs,
            mutation: request.mutation,
        ) {
            try request.validateCurrentIntent()
        }
        guard case let .applied(commit) = disposition else {
            throw ContentTabPinnedRecordPersistenceCommitError.superseded
        }
        return commit
    }

    nonisolated private static func failedTopNavigationPersistence(
        _ request: WindowManagerTopNavigationPersistenceRequest,
        failure: FileManagerTopNavigationIntentFailure,
    ) -> WindowManagerTopNavigationPersistenceResult {
        .init(
            request: request,
            terminal: .failed(failure),
            authoritativePinnedContentTabs: nil,
        )
    }

    func completeTopNavigationPersistence(
        _ result: WindowManagerTopNavigationPersistenceResult,
        state: inout State,
    ) -> Effect<Action> {
        guard state.isTopNavigationPersistenceInFlight,
              state.topNavigationPersistenceQueue.first == result.request
        else { return .none }
        state.topNavigationPersistenceQueue.removeFirst()
        state.isTopNavigationPersistenceInFlight = false

        if case .contentTabMove = result.request.operation {
            return completeCorrelatedContentTabMovePersistence(result, state: &state)
        }

        let shouldPublishCommit = shouldPublishTopNavigationCommit(result, state: state)
        let bootstrapLifecycle: (cancel: Effect<Action>, restart: Effect<Action>) = if case .committed = result
            .terminal, shouldPublishCommit
        {
            invalidateAndRestartDefaultWindowBootstrapForTopNavigationChange(state: &state)
        } else {
            (.none, .none)
        }

        var effects: [Effect<Action>] = []
        effects.append(bootstrapLifecycle.cancel)
        if case let .committed(commit) = result.terminal, shouldPublishCommit {
            effects.append(fanOutCommittedTopNavigationSnapshot(
                commit,
                authoritativePinnedContentTabs: result.authoritativePinnedContentTabs,
                state: state,
            ))
        }
        if let sourceTerminal = topNavigationSourceTerminalEffect(result, state: state) {
            effects.append(sourceTerminal)
        }
        effects.append(.merge(
            finalizeDeferredWindowClosuresWithoutPendingPersistence(state: &state),
            startNextTopNavigationPersistenceIfNeeded(state: &state),
            bootstrapLifecycle.restart,
        ))
        return .concatenate(effects)
    }

    func shouldPublishTopNavigationCommit(
        _ result: WindowManagerTopNavigationPersistenceResult,
        state: State,
    ) -> Bool {
        guard case let .pinnedRecord(_, request, _) = result.request.operation,
              let source = state.windows[id: result.request.sourceWindowID]?.window
        else { return true }
        return source.contentTabs.isCurrentPinnedRecordPersistenceIntent(
            tabID: request.tabID,
            intentID: request.context.intentID,
        )
    }

    func fanOutCommittedTopNavigationSnapshot(
        _ commit: FileManagerTopNavigationCommit,
        authoritativePinnedContentTabs: ContentTabState?,
        state: State,
        excludingWindowIDs: Set<State.WindowID> = [],
    ) -> Effect<Action> {
        committedTopNavigationFanOut(
            commit,
            authoritativePinnedContentTabs: authoritativePinnedContentTabs,
            to: state.windows.ids.filter { !state.closingWindowIDs.contains($0) && !excludingWindowIDs.contains($0) },
            state: state,
        )
    }

    func committedTopNavigationSnapshotEffects(
        for windowIDs: [State.WindowID],
        commit: FileManagerTopNavigationCommit,
        authoritativePinnedContentTabs: ContentTabState?,
        state: State,
    ) -> Effect<Action> {
        committedTopNavigationFanOut(
            commit,
            authoritativePinnedContentTabs: authoritativePinnedContentTabs,
            to: windowIDs,
            state: state,
        )
    }

    func committedTopNavigationSnapshotAction(
        for windowID: State.WindowID,
        commit: FileManagerTopNavigationCommit,
        authoritativePinnedContentTabs: ContentTabState?,
        state: State,
    ) -> FileManagerWindowAction? {
        guard let window = state.windows[id: windowID]?.window else { return nil }
        if window.lastConfirmedTopNavigationCommitRevision.map({ commit.revision >= $0 }) != false {
            return .applyCommittedTopNavigationSnapshot(
                order: commit.order,
                revision: commit.revision,
                authoritativePinnedContentTabs: authoritativePinnedContentTabs,
            )
        }
        return .applyExternalCommittedTopNavigationOrder(
            commit.order,
            revision: commit.revision,
        )
    }

    func topNavigationSourceTerminalEffect(
        _ result: WindowManagerTopNavigationPersistenceResult,
        state: State,
    ) -> Effect<Action>? {
        let sourceWindowID = result.request.sourceWindowID
        guard let sourceWindow = state.windows[id: sourceWindowID]?.window,
              !state.closingWindowIDs.contains(sourceWindowID)
        else { return nil }

        switch result.request.operation {
        case .move, .movePinnedGroup:
            return .send(.windows(.element(
                id: sourceWindowID,
                action: .window(.internal(.topNavigationIntentCompleted(
                    token: result.request.token,
                    terminal: result.terminal,
                ))),
            )))

        case let .pinnedRecord(source, request, _):
            guard sourceWindow.contentTabs.tabs[id: request.tabID] != nil else { return nil }
            return .send(.windows(.element(
                id: sourceWindowID,
                action: .window(.internal(.pinnedRecordPersistenceCompleted(
                    token: result.request.token,
                    source: source,
                    request: request,
                    terminal: result.terminal,
                ))),
            )))

        case .contentTabMove:
            return nil
        }
    }

    func persistTopNavigationMove(
        sourceWindowID: State.WindowID,
        token: FileManagerTopNavigationOperationToken,
        source: FileManagerTopNavigationItemID,
        destination: FileManagerTopNavigationMoveDestination,
        discoveredLocationIDs: [String],
    ) -> Effect<Action> {
        let client = contentTabPinnedRecordClient
        let defaults = userDefaultsClient
        return .run { send in
            let terminal: FileManagerTopNavigationIntentTerminal
            do {
                let commit = try await client.moveTopNavigationItemCommitted(
                    defaults,
                    discoveredLocationIDs,
                    source,
                    destination,
                )
                terminal = .committed(commit)
            } catch is CancellationError {
                terminal = .failed(.cancelled)
            } catch let error as ContentTabPinnedRecordStoreLoadError {
                let failure: FileManagerTopNavigationArrangementLoadFailure = switch error {
                case .corruptUnavailable:
                    .corrupt
                case let .futureSchemaUnavailable(schemaVersion):
                    .unsupportedSchema(schemaVersion)
                }
                terminal = .failed(.storeUnavailable(failure))
            } catch {
                terminal = .failed(.save)
            }
            await send(.topNavigationMovePersistenceCompleted(
                sourceWindowID: sourceWindowID,
                token: token,
                terminal: terminal,
            ))
        }
    }

    func completeTopNavigationMovePersistence(
        sourceWindowID: State.WindowID,
        token: FileManagerTopNavigationOperationToken,
        terminal: FileManagerTopNavigationIntentTerminal,
        state: State,
    ) -> Effect<Action> {
        var effects: [Effect<Action>] = []
        if state.windows[id: sourceWindowID] != nil {
            effects.append(.send(.windows(.element(
                id: sourceWindowID,
                action: .window(.internal(.topNavigationIntentCompleted(
                    token: token,
                    terminal: terminal,
                ))),
            ))))
        }
        if case let .committed(commit) = terminal {
            effects.append(committedTopNavigationFanOut(
                commit,
                authoritativePinnedContentTabs: nil,
                to: state.windows.ids.filter { $0 != sourceWindowID && !state.closingWindowIDs.contains($0) },
                state: state,
            ))
        }
        return .merge(effects)
    }

    func committedTopNavigationFanOut(
        _ commit: FileManagerTopNavigationCommit,
        authoritativePinnedContentTabs: ContentTabState?,
        to windowIDs: [State.WindowID],
        state: State,
    ) -> Effect<Action> {
        .merge(windowIDs.compactMap { windowID in
            guard let action = committedTopNavigationSnapshotAction(
                for: windowID,
                commit: commit,
                authoritativePinnedContentTabs: authoritativePinnedContentTabs,
                state: state,
            ) else { return nil }
            return .send(.windows(.element(id: windowID, action: .window(action))))
        })
    }
}
