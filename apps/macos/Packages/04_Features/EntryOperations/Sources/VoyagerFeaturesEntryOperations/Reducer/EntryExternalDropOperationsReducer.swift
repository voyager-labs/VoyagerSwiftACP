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

    private func startPlacement(plan: ExternalDropImportPlan, state: inout State) -> Effect<Action> {
        // 진행 중 placement가 있으면 새 세션으로 덮어써 첫 세션의 복사 완료·staging 정리·
        // 종합 reload가 유실되지 않도록 차단한다. (전체 취소/직렬화 배선은 별도 이슈로 분리)
        guard state.externalDropImportPlacement == nil else {
            // 버려진 plan의 세션도 finish해 두 번째 staging이 남지 않게 정리한다.
            return .run { [acquisitionClient, sessionID = plan.sessionID] _ in
                await acquisitionClient.finish(sessionID)
            }
        }
        // 획득된 staged 파일을 item/callback ordinal 순서로 정렬하고, mixed drop의 즉시
        // file URL을 뒤에 이어 붙여 promise/materialization과 함께 복사 배치로 전달한다.
        let orderedSources = plan.receivedFiles
            .sorted { ($0.itemOrdinal, $0.callbackOrdinal) < ($1.itemOrdinal, $1.callbackOrdinal) }
            .map(\.stagedPath)
            + plan.immediateURLPaths
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
        return .send(.clipboard(.pasteItems(
            sourcePaths: orderedSources,
            destinationPath: plan.destination,
            operation: .copy,
            operationKind: .externalObjectImportItem,
        )))
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
            cleanup,
        )
    }

    private func cancelActiveIfAny(state: inout State) -> Effect<Action> {
        guard let active = state.activeExternalDrop else { return .none }
        let sessionID = active.sessionID
        state.activeExternalDrop = nil
        state.externalObjectImportStatus = nil
        return .merge(
            .cancel(id: CancelID.externalDrop(sessionID)),
            .run { [acquisitionClient] _ in
                await acquisitionClient.cancel(sessionID)
            },
        )
    }
}
