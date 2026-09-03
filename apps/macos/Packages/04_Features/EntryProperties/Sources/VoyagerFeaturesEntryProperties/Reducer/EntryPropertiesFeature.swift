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
                let interruptedExecutionProposal = interruptedExecution ? state.proposal : nil
                let ambiguousProposal = state.status == .ambiguous ? state.proposal : nil
                let interruptedReadBack = state.activePhase == .applied
                let interruptedReadBackProposal = state.readBackProposal ?? state.appliedProposal
                let preservedPendingReadBack = state.pendingReadBack
                let appliedUnverifiedProposal = state.status == .appliedUnverified ? state.appliedProposal : nil
                state.generation &+= 1
                state.selection = selection
                state.capabilityReport = nil
                state.targetSnapshot = nil
                state.proposal = nil
                state.appliedProposal = nil
                state.pendingReadBack = interruptedExecutionProposal ?? ambiguousProposal ?? appliedUnverifiedProposal
                state.pendingReadBack = state.pendingReadBack ?? preservedPendingReadBack
                state.readBackProposal = nil
                state.canonicalResult = nil
                state.activePhase = nil
                if interruptedExecution {
                    let outcome = EntryPropertiesOutcome.propertyChangeRejected(.ambiguousExecution)
                    state.status = .ambiguous
                    state.lastOutcome = outcome
                    return selectionChangeOutcomeEffect(outcome)
                }
                if interruptedReadBack, let interruptedReadBackProposal {
                    state.pendingReadBack = interruptedReadBackProposal
                    let outcome = EntryPropertiesOutcome.propertyChangeAppliedUnverified(
                        interruptedReadBackProposal.snapshot,
                    )
                    state.status = .idle
                    state.lastOutcome = outcome
                    return selectionChangeOutcomeEffect(outcome)
                }
                if ambiguousProposal != nil {
                    let outcome = EntryPropertiesOutcome.propertyChangeRejected(.ambiguousExecution)
                    state.status = .idle
                    state.lastOutcome = outcome
                    return selectionChangeOutcomeEffect(outcome)
                }
                if let appliedUnverifiedProposal {
                    let outcome = EntryPropertiesOutcome.propertyChangeAppliedUnverified(
                        appliedUnverifiedProposal.snapshot,
                    )
                    state.status = .idle
                    state.lastOutcome = outcome
                    return selectionChangeOutcomeEffect(outcome)
                }
                state.status = .idle
                state.lastOutcome = nil
                return .cancel(id: CancelID.flow)

            case .discoverCapabilities, .reconnect:
                guard state.activePhase != .executing,
                      state.activePhase != .applied,
                      state.status != .appliedUnverified
                else {
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
                guard state.pendingReadBack == nil else { return rejectBusy(&state) }
                guard state.status != .appliedUnverified, state.status != .ambiguous else {
                    return rejectBusy(&state)
                }
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
                guard state.pendingReadBack == nil else { return rejectBusy(&state) }
                guard state.status == .prepared else {
                    let outcome = EntryPropertiesOutcome.propertyChangeRejected(.stale)
                    state.lastOutcome = outcome
                    return .send(.init(kind: .outcome(outcome)))
                }
                guard let proposal = state.proposal,
                      proposal.snapshot == state.targetSnapshot
                else { return reject(&state, .stale) }
                guard state.capabilityReport?.capability(for: .changeValue) == .supported else {
                    return reject(&state, .unsupported)
                }
                guard !proposal.requiresConfirmation || confirmed else {
                    let outcome = EntryPropertiesOutcome.propertyChangeRejected(.confirmationRequired)
                    state.lastOutcome = outcome
                    return .send(.init(kind: .outcome(outcome)))
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
                        // verified 전이에서 실행 전 assignment revision으로 남은
                        // snapshot을 정본 result revision으로 갱신한다. 갱신하지
                        // 않으면 같은 selection 연속 편집의 prepare가 이전 revision을
                        // CAS 토큰으로 보내 정상 daemon에서도 conflict가 난다.
                        state.targetSnapshot = verifiedSnapshot(proposal.snapshot, canonicalResult: canonicalResult)
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
                    // 취소할 active effect가 없어도 recovery 상태(ambiguous,
                    // applied-unverified)는 유지한다. status를 idle로 덮으면
                    // read-only retry 경계와 mutation busy guard가 모두 열리고
                    // 기존 mutation의 적용 여부 복구 경로가 사라진다.
                    if state.status != .ambiguous, state.status != .appliedUnverified {
                        state.status = .idle
                    }
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
            guard let canonicalValue = valuesByTarget[difference.target],
                  canonicalValue.value == difference.after,
                  let expectedRevision = expectedNextAssignmentRevision(
                      for: difference.target,
                      snapshot: proposal.snapshot,
                  ) else { return false }
            return canonicalValue.revision == expectedRevision
        }
    }

    private func expectedNextAssignmentRevision(
        for target: EntryPropertiesTarget,
        snapshot: EntryPropertiesTargetSnapshot,
    ) -> Int64? {
        let previousRevision = snapshot.assignmentRevisions
            .first(where: { $0.target == target })?.revision ?? snapshot.canonicalRevision
        guard previousRevision >= 0, previousRevision < Int64.max else { return nil }
        return previousRevision + 1
    }

    private func snapshotMatchesSelection(
        _ snapshot: EntryPropertiesTargetSnapshot,
        selection: EntryPropertiesSelection,
    ) -> Bool {
        snapshot.targets == selection.targets && snapshot.propertyID == selection.propertyID
    }
}

private extension EntryPropertiesFeature {
    func selectionChangeOutcomeEffect(_ outcome: EntryPropertiesOutcome) -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.flow),
            .send(.init(kind: .outcome(outcome))),
        )
    }
}

/// 검증 성공 뒤 같은 selection의 연속 편집이 정본 revision을 CAS 토큰으로
/// 쓰도록 snapshot의 assignment revision을 canonical result로 갱신한다.
private func verifiedSnapshot(
    _ snapshot: EntryPropertiesTargetSnapshot,
    canonicalResult: EntryPropertiesCanonicalResult,
) -> EntryPropertiesTargetSnapshot {
    EntryPropertiesTargetSnapshot(
        reconcilingTargets: snapshot.targets,
        propertyID: snapshot.propertyID,
        catalogVersion: snapshot.catalogVersion,
        canonicalRevision: canonicalResult.values.map(\.revision).max() ?? snapshot.canonicalRevision,
        definitionRevision: snapshot.definitionRevision,
        valueKind: snapshot.valueKind,
        cardinality: snapshot.cardinality,
        assignmentRevisions: canonicalResult.values.map {
            .init(target: $0.target, revision: $0.revision)
        },
    )
}

func mappedFailure(_ error: any Error) -> EntryPropertiesFailure {
    if let failure = error as? EntryPropertiesFailure {
        return failure
    }
    guard let clientError = error as? EntryCoreClientError else { return .unavailable }
    if case let .server(code) = clientError {
        return mappedServerFailure(code)
    }
    switch clientError {
    case .server:
        return .unavailable
    case .invalidEndpoint, .daemonUnavailable, .timedOut(.connect), .transport(.connect):
        return .unavailable
    case .cancelled, .timedOut(.write), .timedOut(.read), .transport(.write), .transport(.read),
         .responseTooLarge, .malformedResponse, .protocolMismatch, .requestIDMismatch:
        return .unavailable
    case .localValidation:
        return .validation
    }
}

private func mappedServerFailure(_ code: EntryCoreServerErrorCode) -> EntryPropertiesFailure {
    switch code {
    case .conflict:
        .conflict
    case .unsupported, .unknownMethod:
        .unsupported
    case .permissionDenied:
        .authorization
    case .requestTooLarge, .invalidRequest, .invalidPath, .invalidSelector, .contextMismatch,
         .scopeTooLarge, .invalidPageToken, .propertyNotFound, .responseTooLarge:
        .validation
    case .mountNotFound, .sourceNotFound, .sourceUnavailable, .sourceDeleted, .entryNotFound,
         .adapterFailure, .internalError:
        .unavailable
    }
}

func mappedExecutionFailure(_ error: any Error) -> EntryPropertiesFailure {
    guard let clientError = error as? EntryCoreClientError else { return mappedFailure(error) }
    switch clientError {
    case .localValidation:
        return .validation
    case .cancelled, .timedOut(.write), .timedOut(.read), .transport(.write), .transport(.read),
         .responseTooLarge, .malformedResponse, .protocolMismatch, .requestIDMismatch:
        return .ambiguousExecution
    default:
        return mappedFailure(clientError)
    }
}
