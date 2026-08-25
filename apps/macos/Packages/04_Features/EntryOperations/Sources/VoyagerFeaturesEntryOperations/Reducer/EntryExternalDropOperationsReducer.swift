import ComposableArchitecture
import Foundation

/// 외부 drop 획득의 all-promises 성공 배리어를 담당하는 reducer.
///
/// Todo 4/5가 `.externalDrop(.accepted(request:))`로 세션을 열면 이 reducer가 획득 이벤트 스트림을
/// 구독한다. 모든 promise가 성공하기 전까지는 promised/immediate 어느 쪽도 배치를 시작하지 않고,
/// 하나의 promise 실패/누락/취소가 전체 배치를 막는다. 세션 신선도를 위해 현재 active 세션과
/// 일치하지 않는 이벤트는 무시한다. 실제 복사 배치는 `.applyImport`(Todo 7 seam)가 수행한다.
public enum CancelID: Hashable, Sendable {
    case externalDrop(ExternalDropSessionID)
    /// placement 검증·복사 단계 전용 취소 ID. 획득 구독(beginSubscription)과 ID가
    /// 같으면 성공 직후 placement effect 등록이 구독을 취소해 staging이 placement
    /// 전에 삭제된다(코멘트 #3837956590).
    case externalDropPlacement(ExternalDropSessionID)
}

@Reducer
public struct EntryExternalDropOperationsReducer {
    public typealias State = EntryOperationsState
    public typealias Action = EntryOperationsAction

    public init() {}

    @Dependency(\.externalDropAcquisitionClient)
    private var acquisitionClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            // MARK: - Session lifecycle (from Todo 4/5)

            case let .externalDrop(.accepted(request)):
                // 기존 active 세션이 있으면 정확한 세션을 취소하고 교체한다.
                if let previous = state.activeExternalDrop {
                    let previousID = previous.sessionID
                    state.activeExternalDrop = nil
                    state.externalObjectImportStatus = nil
                    return .merge(
                        .cancel(id: CancelID.externalDrop(previousID)),
                        .run { [acquisitionClient] _ in
                            await acquisitionClient.cancel(previousID)
                        },
                        beginSubscription(request: request, state: &state),
                    )
                }
                return beginSubscription(request: request, state: &state)

            case let .externalDrop(.event(event)):
                return handle(event: event, state: &state)

            case let .externalDrop(.cancelSession(sessionID)):
                guard state.activeExternalDrop?.sessionID == sessionID else {
                    return .none
                }
                return teardown(
                    sessionID: sessionID,
                    state: &state,
                    cleanup: .run { [acquisitionClient] _ in
                        await acquisitionClient.cancel(sessionID)
                    },
                )

            case let .externalDrop(.finishSession(sessionID)):
                guard state.activeExternalDrop?.sessionID == sessionID else {
                    return .none
                }
                return teardown(
                    sessionID: sessionID,
                    state: &state,
                    cleanup: .run { [acquisitionClient] _ in
                        await acquisitionClient.finish(sessionID)
                    },
                )

            // Todo 7 seam: 실제 복사 배치를 수행한다. 획득된 staged 파일을 순서대로
            // `Clipboard.pasteItems`(.copy + .externalObjectImportItem)로 보내 destination에 복사한다.
            case let .externalDrop(.applyImport(plan)):
                return verifyPlacementEntry(plan: plan, state: &state)

            case let .externalDrop(.placementSourcesPrepared(plan, isValid)):
                guard state.externalDropImportPlacement?.sessionID == plan.sessionID else {
                    return .none
                }
                guard isValid else {
                    state.externalDropImportPlacement = nil
                    state.externalObjectImportStatus = .failed
                    return .run { [acquisitionClient, sessionID = plan.sessionID] _ in
                        await acquisitionClient.finish(sessionID)
                    }
                }
                return startPlacement(plan: plan, state: &state)

            // Todo 7: placement 항목의 종단을 추적해 모든 항목이 끝나면 정확히 한 번 종합 완료를 emit한다.
            case let .lifecycle(.pathsMutated(paths)):
                // 복사 배치가 source(staging) → destination 쌍을 보고하면 매핑을 캡처한다.
                // 종합 결과에는 staging이 아닌 실제 destination 경로를 담기 위함이다.
                return captureDestinationPaths(paths: paths, state: &state)

            case let .lifecycle(.operationFinished(path, kind, result)):
                guard kind == .externalObjectImportItem,
                      let placement = state.externalDropImportPlacement,
                      placement.pendingPaths.contains(path)
                else {
                    return .none
                }
                state.externalDropImportPlacement?.pendingPaths.remove(path)
                switch result {
                case .success:
                    let destinationPath = state.externalDropImportPlacement?.destinationBySource[path] ?? path
                    state.externalDropImportPlacement?.succeededPaths.append(destinationPath)
                case .failure:
                    state.externalDropImportPlacement?.failedPaths.append(path)
                }
                return finishPlacementIfComplete(state: &state)

            // Todo 7: 종합 완료 후 in-flight 추적 상태를 정리한다.
            case .externalDrop(.importFinished):
                state.externalDropImportPlacement = nil
                return .none

            // MARK: - Lifecycle cancellation (windowID change / duplicate reset)

            case .lifecycle(.windowIDChanged), .lifecycle(.resetForDuplicate):
                return cancelActiveIfAny(state: &state)

            default:
                return .none
            }
        }
    }

    private func beginSubscription(
        request: ExternalDropAcceptedRequest,
        state: inout State,
    ) -> Effect<Action> {
        state.activeExternalDrop = ExternalDropActiveSession(request: request)
        state.externalObjectImportStatus = .pending
        return .run { [acquisitionClient, sessionID = request.sessionID] send in
            await withTaskCancellationHandler {
                for await event in await acquisitionClient.events(sessionID) {
                    await send(.externalDrop(.event(event)))
                }
            } onCancel: {
                // effect 취소(창/탭 닫힘, child store 제거) 시 획득 세션을 정리해
                // receiver 작업과 staging이 남지 않게 한다. cancel은 멱등이다.
                Task { @MainActor in
                    acquisitionClient.cancel(sessionID)
                }
            }
        }
        .cancellable(id: CancelID.externalDrop(request.sessionID), cancelInFlight: true)
    }

    private func handle(event: ExternalDropAcquisitionEvent, state: inout State) -> Effect<Action> {
        switch event {
        case let .received(file):
            // 세션 신선도: 현재 active 세션과 일치하는 이벤트만 처리한다.
            guard state.activeExternalDrop?.sessionID == file.sessionID else { return .none }
            state.activeExternalDrop?.receivedFiles.append(file)
            return .none

        case let .succeeded(sessionID):
            guard let active = state.activeExternalDrop, active.sessionID == sessionID else {
                return .none
            }
            let plan = ExternalDropImportPlan(
                sessionID: sessionID,
                destination: active.destination,
                forcedCopy: active.forcedCopy,
                orderedPromisedNames: active.orderedPromisedNames,
                promisedOrdinals: active.promisedOrdinals,
                receivedFiles: active.receivedFiles,
                immediateURLPaths: active.immediateURLPaths,
                immediateOrdinals: active.immediateOrdinals,
            )
            state.activeExternalDrop = nil
            // 획득은 완료됐지만 placement(복사)는 아직 시작 전이므로 pending을 유지한다.
            // 종단 상태는 placement의 모든 항목이 종료된 뒤 결정된다.
            state.externalObjectImportStatus = .pending
            return .send(.externalDrop(.applyImport(plan)))

        case let .failed(sessionID, _):
            // 하나의 promise 실패가 promised/immediate 전체 배치를 막는다.
            guard state.activeExternalDrop?.sessionID == sessionID else { return .none }
            state.activeExternalDrop = nil
            state.externalObjectImportStatus = .failed
            return .run { [acquisitionClient] _ in
                await acquisitionClient.cancel(sessionID)
            }

        case let .cancelled(sessionID):
            guard state.activeExternalDrop?.sessionID == sessionID else { return .none }
            state.activeExternalDrop = nil
            state.externalObjectImportStatus = nil
            return .run { [acquisitionClient] _ in
                await acquisitionClient.cancel(sessionID)
            }
        }
    }

    private func verifyPlacementEntry(
        plan: ExternalDropImportPlan,
        state: inout State,
    ) -> Effect<Action> {
        guard state.externalDropImportPlacement == nil else {
            return .run { [acquisitionClient, sessionID = plan.sessionID] _ in
                await acquisitionClient.finish(sessionID)
            }
        }
        let orderedSources = orderedSources(for: plan)
        guard !orderedSources.isEmpty else {
            state.externalObjectImportStatus = .failed
            return .run { [acquisitionClient, sessionID = plan.sessionID] _ in
                await acquisitionClient.finish(sessionID)
            }
        }
        state.externalDropImportPlacement = ExternalDropImportPlacementState(
            sessionID: plan.sessionID,
            destination: plan.destination,
            pendingPaths: Set(orderedSources),
        )
        state.externalObjectImportStatus = .pending
        return .run { [acquisitionClient] send in
            await withTaskCancellationHandler {
                let isValid = await acquisitionClient.preparePlacementSources(
                    plan.sessionID,
                    orderedSources,
                )
                guard !Task.isCancelled else { return }
                await send(.externalDrop(.placementSourcesPrepared(
                    plan: plan,
                    isValid: isValid,
                )))
            } onCancel: {
                Task { @MainActor in
                    acquisitionClient.finish(plan.sessionID)
                }
            }
        }
        .cancellable(id: CancelID.externalDropPlacement(plan.sessionID), cancelInFlight: true)
    }

    private func startPlacement(plan: ExternalDropImportPlan, state: inout State) -> Effect<Action> {
        guard state.externalDropImportPlacement?.sessionID == plan.sessionID else { return .none }
        let orderedSources = orderedSources(for: plan)
        return .send(.clipboard(.pasteItems(
            sourcePaths: orderedSources,
            destinationPath: plan.destination,
            operation: .copy,
            operationKind: .externalObjectImportItem,
        )))
    }

    private func orderedSources(for plan: ExternalDropImportPlan) -> [String] {
        // 표현(promise/data/immediate/legacy) 전체를 원본 pasteboard logical ordinal 하나로
        // 통합 정렬한다(코멘트 #3831133039). data/legacy를 전역 먼저, immediate를 전역 나중에
        // 두지 않고, 동률은 receiver 내 콜백 순번 → 도착 순번으로 결정적 유지한다. ordinal이
        // 없는 구형 plan(immediateOrdinals 비어 있음)은 기존 계약대로 immediate를 마지막에 붙인다.
        var orderedEntries: [PlacementEntry] = plan.receivedFiles.map { file in
            PlacementEntry(
                pasteboardOrdinal: file.pasteboardOrdinal,
                withinItemOrdinal: file.callbackOrdinal,
                arrivalOrdinal: file.itemOrdinal,
                sourcePath: file.stagedPath,
            )
        }
        let immediateCount = plan.immediateURLPaths.count
        for (index, path) in plan.immediateURLPaths.enumerated() {
            let ordinal = index < plan.immediateOrdinals.count
                ? plan.immediateOrdinals[index]
                : Int.max - immediateCount + index
            orderedEntries.append(PlacementEntry(
                pasteboardOrdinal: ordinal,
                withinItemOrdinal: 0,
                arrivalOrdinal: Int.max / 2 + index,
                sourcePath: path,
            ))
        }
        return orderedEntries
            .sorted {
                ($0.pasteboardOrdinal, $0.withinItemOrdinal, $0.arrivalOrdinal)
                    < ($1.pasteboardOrdinal, $1.withinItemOrdinal, $1.arrivalOrdinal)
            }
            .map(\.sourcePath)
    }

    /// 복사 배치가 `.pathsMutated([source, destination])`으로 보고한 경로 쌍에서 source(staging)를
    /// 키로 destination을 기록한다. source는 pendingPaths에 속하고 destination은 그 짝이다.
    private func captureDestinationPaths(paths: [String], state: inout State) -> Effect<Action> {
        guard let placement = state.externalDropImportPlacement, !placement.pendingPaths.isEmpty else {
            return .none
        }
        for source in placement.pendingPaths where paths.contains(source) {
            guard let destination = paths.first(where: { $0 != source }),
                  state.externalDropImportPlacement?.destinationBySource[source] == nil
            else {
                continue
            }
            state.externalDropImportPlacement?.destinationBySource[source] = destination
        }
        return .none
    }

    private func finishPlacementIfComplete(state: inout State) -> Effect<Action> {
        guard let placement = state.externalDropImportPlacement, placement.isComplete else {
            return .none
        }
        let sessionID = placement.sessionID
        let result = ExternalDropImportResult(
            sessionID: sessionID,
            succeededPaths: placement.succeededPaths,
            failedPaths: placement.failedPaths,
            status: makeImportStatus(placement),
        )
        state.externalObjectImportStatus = result.status
        return .merge(
            .send(.externalDrop(.importFinished(result))),
            .run { [acquisitionClient] _ in
                await acquisitionClient.finish(sessionID)
            },
        )
    }

    private func makeImportStatus(_ placement: ExternalDropImportPlacementState) -> ExternalObjectImportStatus {
        switch (placement.succeededPaths.isEmpty, placement.failedPaths.isEmpty) {
        case (true, _):
            .failed
        case (_, true):
            .applied
        default:
            .partiallyApplied
        }
    }

    private func teardown(
        sessionID: ExternalDropSessionID,
        state: inout State,
        cleanup: Effect<Action>,
    ) -> Effect<Action> {
        state.activeExternalDrop = nil
        state.externalObjectImportStatus = nil
        return .merge(
            .cancel(id: CancelID.externalDrop(sessionID)),
            .cancel(id: CancelID.externalDropPlacement(sessionID)),
            cleanup,
        )
    }

    private func cancelActiveIfAny(state: inout State) -> Effect<Action> {
        // 획득(activeExternalDrop)과 placement 복사(externalDropImportPlacement)는 각각
        // 별도 세션 ID로 관리된다. windowIDChanged가 placement 복사 중 도착하면 acquisition은
        // 이미 종단(nil)됐을 수 있으므로 placement 상태도 함께 정리해야 다음 drop이 시작된다.
        let acquisitionSessionID = state.activeExternalDrop?.sessionID
        let placementSessionID = state.externalDropImportPlacement?.sessionID
        guard acquisitionSessionID != nil || placementSessionID != nil else {
            return .none
        }
        state.activeExternalDrop = nil
        state.externalDropImportPlacement = nil
        state.externalObjectImportStatus = nil
        var effects: [Effect<Action>] = []
        if let acquisitionSessionID {
            effects.append(.cancel(id: CancelID.externalDrop(acquisitionSessionID)))
            effects.append(.run { [acquisitionClient] _ in
                await acquisitionClient.cancel(acquisitionSessionID)
            })
        }
        if let placementSessionID {
            // placement 복사 effect 취소는 onCancelCleanup이 staging finish를 단일 소유한다.
            // 여기서 client.cancel을 호출하면 복사가 읽던 staging을 지워 부분 파일이 생기므로
            // effect 취소만 적용한다.
            effects.append(.cancel(id: CancelID.externalDropPlacement(placementSessionID)))
            effects.append(.cancel(id: CancelID.externalDrop(placementSessionID)))
        }
        return .merge(effects)
    }
}

/// placement 통합 정렬의 한 항목. pasteboard logical ordinal이 1차 키고, 동률은
/// receiver 내 콜백 순번 → 도착 순번으로 결정적 유지한다(코멘트 #3831133039).
private struct PlacementEntry {
    let pasteboardOrdinal: Int
    let withinItemOrdinal: Int
    let arrivalOrdinal: Int
    let sourcePath: String
}
