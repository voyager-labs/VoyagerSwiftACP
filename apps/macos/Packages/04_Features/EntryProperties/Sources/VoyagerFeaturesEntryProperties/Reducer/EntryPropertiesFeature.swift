import ComposableArchitecture
import Foundation
import VoyagerEntryCoreClient

@Reducer
public struct EntryPropertiesFeature: Sendable {
    public typealias State = EntryPropertiesState
    public typealias Action = EntryPropertiesAction

    @Dependency(\.entryPropertiesClient)
    var client

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action.kind {
            case let .selectionChanged(selection):
                let interruptedExecution = state.activePhase == .executing
                let interruptedReadBack = state.activePhase == .applied
                let interruptedReadBackProposal = state.readBackProposal ?? state.appliedProposal
                let preservedPendingReadBack = state.pendingReadBack
                state.generation &+= 1
                state.selection = selection
                state.capabilityReport = nil
                state.targetSnapshot = nil
                state.proposal = nil
                state.appliedProposal = nil
                state.pendingReadBack = preservedPendingReadBack
                state.readBackProposal = nil
                state.canonicalResult = nil
                state.activePhase = nil
                if interruptedExecution {
                    let outcome = EntryPropertiesOutcome.propertyChangeRejected(.ambiguousExecution)
                    state.status = .ambiguous
                    state.lastOutcome = outcome
                    return .merge(
                        .cancel(id: CancelID.flow),
                        .send(.init(kind: .outcome(outcome))),
                    )
                }
                if interruptedReadBack, let interruptedReadBackProposal {
                    state.pendingReadBack = interruptedReadBackProposal
                    let outcome = EntryPropertiesOutcome.propertyChangeAppliedUnverified(
                        interruptedReadBackProposal.snapshot,
                    )
                    state.status = .idle
                    state.lastOutcome = outcome
                    return .merge(
                        .cancel(id: CancelID.flow),
                        .send(.init(kind: .outcome(outcome))),
                    )
                }
                state.status = .idle
                state.lastOutcome = nil
                return .cancel(id: CancelID.flow)

            case .discoverCapabilities, .reconnect:
                guard state.activePhase != .executing, state.activePhase != .applied else {
                    return rejectBusy(&state)
                }
                state.generation &+= 1
                let generation = state.generation
                let selection = state.selection
                state.activePhase = .discovering
                state.status = .discovering
                state.capabilityReport = nil
                state.targetSnapshot = nil
                state.proposal = nil
                state.canonicalResult = nil
                let client = client
                return .run { send in
                    let result: Result<EntryPropertiesDiscovery, EntryPropertiesFailure>
                    do {
                        // EPR-006 requires catalog-first recovery. Assignment reads must never race it.
                        let catalog = try await client.loadCatalog(selection)
                        let assignments = try await client.loadAssignments(selection, catalog)
                        let request = EntryPropertiesCapabilityRequest(
                            selection: selection,
                            catalog: catalog,
                            assignments: assignments,
                        )
                        let capabilities = try await client.discoverCapabilities(request)
                        guard let catalogVersion = capabilities.catalogVersion ?? catalog.version else {
                            throw EntryPropertiesFailure.unavailable
                        }
                        let snapshot = EntryPropertiesTargetSnapshot(
                            reconcilingTargets: selection.targets,
                            propertyID: selection.propertyID,
                            catalogVersion: catalogVersion,
                            canonicalRevision: assignments.canonicalRevision,
                            definitionRevision: catalog.definitionRevision,
                            valueKind: catalog.valueKind,
                            cardinality: catalog.cardinality,
                            assignmentRevisions: assignments.values.map {
                                .init(target: $0.target, revision: $0.revision)
                            },
                        )
                        result = .success(EntryPropertiesDiscovery(snapshot: snapshot, capabilities: capabilities))
                    } catch {
                        result = .failure(mappedFailure(error))
                    }
                    await send(.init(kind: .discoveryCompleted(generation, result)))
                }
                .cancellable(id: CancelID.flow, cancelInFlight: true)

            case let .discoveryCompleted(generation, result):
                guard generation == state.generation, state.activePhase == .discovering else { return .none }
                state.activePhase = nil
                switch result {
                case let .success(discovery):
                    state.targetSnapshot = discovery.snapshot
                    state.capabilityReport = discovery.capabilities
                    state.status = .ready
                    return emit(&state, .capabilitiesDiscovered(discovery.capabilities))
                case let .failure(failure):
                    return reject(&state, failure)
                }

            case let .prepare(intent):
                guard state.activePhase == nil else { return rejectBusy(&state) }
                guard let snapshot = state.targetSnapshot,
                      let capabilities = state.capabilityReport
                else { return reject(&state, .stale) }
                guard capabilities.capability(for: .changeValue) == .supported else {
                    return reject(&state, .unsupported)
                }
                guard snapshot.targets.count == 1 || capabilities.supportsMultipleTargets else {
                    return reject(&state, .unsupported)
                }
                let generation = state.generation
                state.activePhase = .preparing
                state.status = .preparing
                state.proposal = nil
                let client = client
                let request = EntryPropertiesPrepareRequest(snapshot: snapshot, intent: intent)
                return .run { send in
                    let result: Result<EntryPropertiesProposal, EntryPropertiesFailure>
                    do {
                        result = try await .success(client.prepare(request))
                    } catch {
                        result = .failure(mappedFailure(error))
                    }
                    await send(.init(kind: .prepareCompleted(generation, result)))
                }
                .cancellable(id: CancelID.flow, cancelInFlight: false)

            case let .prepareCompleted(generation, result):
                guard generation == state.generation, state.activePhase == .preparing else { return .none }
                state.activePhase = nil
                switch result {
                case let .success(proposal):
                    guard proposal.snapshot == state.targetSnapshot else { return reject(&state, .stale) }
                    guard proposal.validation.isValid else {
                        return reject(&state, proposal.validation.failure ?? .validation)
                    }
                    state.proposal = proposal
                    state.status = .prepared
                    return emit(&state, .propertyChangePrepared(proposal))
                case let .failure(failure):
                    return reject(&state, failure)
                }

            case let .execute(confirmed):
                guard state.activePhase == nil else { return rejectBusy(&state) }
                guard let proposal = state.proposal,
                      proposal.snapshot == state.targetSnapshot
                else { return reject(&state, .stale) }
                guard state.capabilityReport?.capability(for: .changeValue) == .supported else {
                    return reject(&state, .unsupported)
                }
                guard !proposal.requiresConfirmation || confirmed else {
                    return reject(&state, .confirmationRequired)
                }
                let generation = state.generation
                state.activePhase = .executing
                state.status = .executing
                let client = client
                return .run { send in
                    let result: Result<EntryPropertiesExecutionReceipt, EntryPropertiesFailure>
                    do {
                        result = try await .success(client.execute(proposal))
                    } catch {
                        result = .failure(mappedExecutionFailure(error))
                    }
                    await send(.init(kind: .executeCompleted(generation, result)))
                }
                .cancellable(id: CancelID.flow, cancelInFlight: false)

            case let .executeCompleted(generation, result):
                guard generation == state.generation, state.activePhase == .executing else { return .none }
                state.activePhase = nil
                switch result {
                case let .success(receipt):
                    guard let proposal = state.proposal, receipt.snapshot == proposal.snapshot else {
                        return reject(&state, .conflict)
                    }
                    state.appliedProposal = proposal
                    state.status = .applied
                    let outcomeEffect = emit(&state, .propertyChangeApplied(receipt.snapshot))
                    return .merge(outcomeEffect, readBackEffect(state: &state, proposal: proposal))
                case .failure(.ambiguousExecution):
                    state.status = .ambiguous
                    state.lastOutcome = .propertyChangeRejected(.ambiguousExecution)
                    return .send(.init(kind: .outcome(.propertyChangeRejected(.ambiguousExecution))))
                case let .failure(failure):
                    return reject(&state, failure)
                }

            case .retryReadBack:
                guard state.activePhase == nil else { return rejectBusy(&state) }
                if let proposal = state.pendingReadBack {
                    return readBackEffect(state: &state, proposal: proposal)
                }
                guard state.status == .appliedUnverified,
                      let proposal = state.appliedProposal
                else { return reject(&state, .stale) }
                return readBackEffect(state: &state, proposal: proposal)

            case let .readBackCompleted(generation, result):
                guard generation == state.generation, state.activePhase == .applied else { return .none }
                state.activePhase = nil
                let proposal = state.readBackProposal ?? state.appliedProposal
                let isPendingReadBack = state.pendingReadBack == proposal
                state.readBackProposal = nil
                guard let proposal else { return reject(&state, .stale) }
                let currentSelection = snapshotMatchesSelection(proposal.snapshot, selection: state.selection)
                if isPendingReadBack, currentSelection {
                    state.pendingReadBack = nil
                }
                switch result {
                case let .success(canonicalResult):
                    guard canonicalResultMatchesProposal(canonicalResult, proposal: proposal) else {
                        if currentSelection {
                            state.appliedProposal = proposal
                            state.status = .appliedUnverified
                        } else {
                            state.pendingReadBack = proposal
                        }
                        return emit(&state, .propertyChangeAppliedUnverified(proposal.snapshot))
                    }
                    if currentSelection {
                        state.appliedProposal = proposal
                        state.canonicalResult = canonicalResult
                        state.status = .verified
                    } else {
                        state.pendingReadBack = nil
                    }
                    return emit(&state, .propertyChangeVerified(canonicalResult))
                case .failure:
                    if currentSelection {
                        state.appliedProposal = proposal
                        state.status = .appliedUnverified
                    } else {
                        state.pendingReadBack = proposal
                    }
                    return emit(&state, .propertyChangeAppliedUnverified(proposal.snapshot))
                }

            case .cancel:
                state.generation &+= 1
                let cancellationEffect: Effect<Action> = .cancel(id: CancelID.flow)
                var cancellationOutcomeEffect: Effect<Action> = .none
                if state.activePhase == .executing {
                    state.status = .ambiguous
                    cancellationOutcomeEffect = emit(
                        &state,
                        .propertyChangeRejected(.ambiguousExecution),
                    )
                } else if state.activePhase == .applied {
                    let proposal = state.readBackProposal ?? state.appliedProposal
                    state.readBackProposal = nil
                    if let proposal, snapshotMatchesSelection(proposal.snapshot, selection: state.selection) {
                        state.appliedProposal = proposal
                        state.status = .appliedUnverified
                        cancellationOutcomeEffect = emit(
                            &state,
                            .propertyChangeAppliedUnverified(proposal.snapshot),
                        )
                    } else if let proposal {
                        state.appliedProposal = nil
                        state.pendingReadBack = proposal
                        state.status = .idle
                        cancellationOutcomeEffect = emit(
                            &state,
                            .propertyChangeAppliedUnverified(proposal.snapshot),
                        )
                    } else {
                        state.status = .idle
                    }
                } else {
                    state.status = .idle
                }
                state.activePhase = nil
                return .merge(cancellationEffect, cancellationOutcomeEffect)

            case let .outcome(outcome):
                state.lastOutcome = outcome
                return .none
            }
        }
    }

    private func readBackEffect(
        state: inout State,
        proposal: EntryPropertiesProposal,
    ) -> Effect<Action> {
        let snapshot = proposal.snapshot
        let generation = state.generation
        state.activePhase = .applied
        state.readBackProposal = proposal
        let client = client
        return .run { send in
            let result: Result<EntryPropertiesCanonicalResult, EntryPropertiesFailure>
            do {
                result = try await .success(client.readBack(.init(snapshot: snapshot)))
            } catch {
                result = .failure(mappedFailure(error))
            }
            await send(.init(kind: .readBackCompleted(generation, result)))
        }
        .cancellable(id: CancelID.flow, cancelInFlight: false)
    }

    private func emit(_ state: inout State, _ outcome: EntryPropertiesOutcome) -> Effect<Action> {
        state.lastOutcome = outcome
        return .send(.init(kind: .outcome(outcome)))
    }

    private func rejectBusy(_ state: inout State) -> Effect<Action> {
        let outcome = EntryPropertiesOutcome.propertyChangeRejected(.busy)
        state.lastOutcome = outcome
        return .send(.init(kind: .outcome(outcome)))
    }

    private func reject(_ state: inout State, _ failure: EntryPropertiesFailure) -> Effect<Action> {
        state.activePhase = nil
        switch failure {
        case .conflict:
            state.status = .rejected(.conflict)
            state.lastOutcome = .propertyChangeConflict
            return .send(.init(kind: .outcome(.propertyChangeConflict)))
        case .unsupported:
            state.status = .rejected(.unsupported)
            state.lastOutcome = .propertyChangeUnsupported
            return .send(.init(kind: .outcome(.propertyChangeUnsupported)))
        default:
            state.status = .rejected(failure)
            state.lastOutcome = .propertyChangeRejected(failure)
            return .send(.init(kind: .outcome(.propertyChangeRejected(failure))))
        }
    }

    private enum CancelID: Hashable {
        case flow
    }

    private func canonicalResultMatchesProposal(
        _ result: EntryPropertiesCanonicalResult,
        proposal: EntryPropertiesProposal,
    ) -> Bool {
        guard result.snapshot == proposal.snapshot,
              result.values.count == proposal.differences.count
        else { return false }
        var valuesByTarget: [EntryPropertiesTarget: EntryPropertiesCanonicalValue] = [:]
        for canonicalValue in result.values {
            guard valuesByTarget.updateValue(canonicalValue, forKey: canonicalValue.target) == nil else {
                return false
            }
        }
        return proposal.differences.allSatisfy { difference in
            valuesByTarget[difference.target]?.value == difference.after
        }
    }

    private func snapshotMatchesSelection(
        _ snapshot: EntryPropertiesTargetSnapshot,
        selection: EntryPropertiesSelection,
    ) -> Bool {
        snapshot.targets == selection.targets && snapshot.propertyID == selection.propertyID
    }
}

func mappedFailure(_ error: any Error) -> EntryPropertiesFailure {
    if let failure = error as? EntryPropertiesFailure {
        return failure
    }
    guard let clientError = error as? EntryCoreClientError else { return .unavailable }
    switch clientError {
    case let .server(code):
        switch code {
        case .conflict:
            return .conflict
        case .unsupported, .unknownMethod:
            return .unsupported
        case .permissionDenied:
            return .authorization
        case .requestTooLarge, .invalidRequest, .invalidPath, .invalidSelector, .contextMismatch,
             .scopeTooLarge, .invalidPageToken, .propertyNotFound, .responseTooLarge:
            return .validation
        case .mountNotFound, .sourceNotFound, .sourceUnavailable, .sourceDeleted, .entryNotFound,
             .adapterFailure, .internalError:
            return .unavailable
        }
    case .invalidEndpoint, .daemonUnavailable, .timedOut(.connect), .transport(.connect):
        return .unavailable
    case .cancelled, .timedOut(.write), .timedOut(.read), .transport(.write), .transport(.read),
         .responseTooLarge, .malformedResponse, .protocolMismatch, .requestIDMismatch:
        return .unavailable
    }
}

func mappedExecutionFailure(_ error: any Error) -> EntryPropertiesFailure {
    guard let clientError = error as? EntryCoreClientError else { return mappedFailure(error) }
    switch clientError {
    case .cancelled, .timedOut(.write), .timedOut(.read), .transport(.write), .transport(.read),
         .responseTooLarge, .malformedResponse, .protocolMismatch, .requestIDMismatch:
        return .ambiguousExecution
    default:
        return mappedFailure(clientError)
    }
}
