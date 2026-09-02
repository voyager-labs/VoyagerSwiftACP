import ComposableArchitecture
import Foundation

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
                state.generation &+= 1
                state.selection = selection
                state.capabilityReport = nil
                state.targetSnapshot = nil
                state.proposal = nil
                state.appliedProposal = nil
                state.canonicalResult = nil
                state.activePhase = nil
                state.status = .idle
                state.lastOutcome = nil
                return .cancel(id: CancelID.flow)

            case .discoverCapabilities, .reconnect:
                guard state.activePhase != .executing else {
                    return rejectBusy(&state)
                }
                state.generation &+= 1
                let generation = state.generation
                let selection = state.selection
                state.activePhase = .discovering
                state.status = .discovering
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
                    } catch is CancellationError {
                        result = .failure(.ambiguousExecution)
                    } catch {
                        result = .failure(mappedFailure(error))
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
                    return .merge(outcomeEffect, readBackEffect(state: &state, snapshot: receipt.snapshot))
                case .failure(.ambiguousExecution):
                    state.status = .ambiguous
                    state.lastOutcome = .propertyChangeRejected(.ambiguousExecution)
                    return .send(.init(kind: .outcome(.propertyChangeRejected(.ambiguousExecution))))
                case let .failure(failure):
                    return reject(&state, failure)
                }

            case .retryReadBack:
                guard state.activePhase == nil else { return rejectBusy(&state) }
                guard state.status == .appliedUnverified,
                      let snapshot = state.appliedProposal?.snapshot
                else { return reject(&state, .stale) }
                return readBackEffect(state: &state, snapshot: snapshot)

            case let .readBackCompleted(generation, result):
                guard generation == state.generation, state.activePhase == .applied else { return .none }
                state.activePhase = nil
                switch result {
                case let .success(canonicalResult):
                    guard let proposal = state.appliedProposal,
                          canonicalResultMatchesProposal(canonicalResult, proposal: proposal)
                    else {
                        guard let snapshot = state.appliedProposal?.snapshot else { return reject(&state, .stale) }
                        state.status = .appliedUnverified
                        return emit(&state, .propertyChangeAppliedUnverified(snapshot))
                    }
                    state.canonicalResult = canonicalResult
                    state.status = .verified
                    return emit(&state, .propertyChangeVerified(canonicalResult))
                case .failure:
                    guard let snapshot = state.appliedProposal?.snapshot else { return reject(&state, .stale) }
                    state.status = .appliedUnverified
                    return emit(&state, .propertyChangeAppliedUnverified(snapshot))
                }

            case .cancel:
                state.generation &+= 1
                if state.activePhase == .executing {
                    state.status = .ambiguous
                    state.lastOutcome = .propertyChangeRejected(.ambiguousExecution)
                } else if state.activePhase == .applied {
                    state.status = .appliedUnverified
                } else {
                    state.status = .idle
                }
                state.activePhase = nil
                return .cancel(id: CancelID.flow)

            case let .outcome(outcome):
                state.lastOutcome = outcome
                return .none
            }
        }
    }

    private func readBackEffect(
        state: inout State,
        snapshot: EntryPropertiesTargetSnapshot,
    ) -> Effect<Action> {
        let generation = state.generation
        state.activePhase = .applied
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
}

private func mappedFailure(_ error: any Error) -> EntryPropertiesFailure {
    error as? EntryPropertiesFailure ?? .unavailable
}
