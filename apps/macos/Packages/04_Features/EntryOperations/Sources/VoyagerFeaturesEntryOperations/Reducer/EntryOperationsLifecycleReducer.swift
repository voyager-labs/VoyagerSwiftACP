import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

@Reducer
struct EntryOperationsLifecycleReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryOperationsAlertClient)
    var alertClient
    @Dependency(\.entryOperationSoundClient)
    var soundClient
    @Dependency(\.entryThumbnailCacheClient)
    var entryThumbnailCacheClient
    @Dependency(\.trashMetadataStoreClient)
    var trashMetadataStoreClient
    @Dependency(\.externalDropAcquisitionClient)
    var externalDropAcquisitionClient
    @Dependency(\.uuid)
    var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .lifecycle(.windowIDChanged(id)):
                state.windowID = id
                return .none

            case let .lifecycle(.resetForDuplicate(windowID)):
                // reset이 activeExternalDrop/placement를 nil로 만들기 전에 진행 중인 외부
                // drop 세션을 정확한 ID로 취소한다. ExternalDrop reducer는 Lifecycle 뒤에
                // 실행돼 reset 후 activeExternalDrop이 이미 nil이므로, 취소는 여기서 보장한다.
                // 성공 종단(.succeeded) 이후에는 activeExternalDrop이 nil이고 세션 ID가
                // placement에만 남는다. placement 단계에서 reset되면 finishPlacementIfComplete
                // 가 실행되지 않아 staging/session registry가 잔류하므로 placement 세션도
                // 함께 취소한다.
                let externalDropSessionID = state.activeExternalDrop?.sessionID
                let placementSessionID = state.externalDropImportPlacement?.sessionID
                state.resetForDuplicate(
                    windowID: windowID,
                    loadingCancellationOwnerID: uuid(),
                    undoOwnerID: uuid(),
                )
                let sessionIDs = [externalDropSessionID, placementSessionID].compactMap(\.self)
                guard !sessionIDs.isEmpty else { return .none }
                // placement 세션은 즉시 cancel(staging 삭제)하지 않고 effect 취소만 적용한다.
                // placement 복사(.pasteItemsEffect)가 진행 중일 때 staging을 지우면 읽던 원본이
                // 사라져 부분 파일/복사 실패가 생긴다. placement staging 정리는 pasteItemsEffect의
                // onCancelCleanup 지연 finish 경로가 단일 소유한다.
                // placement 준비 effect(.externalDropPlacement)도 함께 취소해야
                // onCancel의 finish가 세션/staging을 정리한다. 미취소면 준비 결과가
                // 초기화된 상태에서 무시되고 세션이 영구 잔류한다(코멘트 #3838035175).
                var effects: [Effect<Action>] = sessionIDs.flatMap {
                    [
                        .cancel(id: CancelID.externalDrop($0)),
                        .cancel(id: CancelID.externalDropPlacement($0)),
                    ]
                }
                if let externalDropSessionID {
                    effects.append(.run { [externalDropAcquisitionClient] _ in
                        await externalDropAcquisitionClient.cancel(externalDropSessionID)
                    })
                }
                return .merge(effects)

            case let .loading(.itemsLoaded(generation, _)):
                guard generation == state.loadingContext.generation else { return .none }
                return refreshRestorableTrashPaths()

            case let .loading(.streamFinished(generation)):
                guard generation == state.loadingContext.generation,
                      state.loadingContext.streamTerminal
                else {
                    return .none
                }
                return refreshRestorableTrashPaths()

            case let .lifecycle(.restorableTrashPathsLoaded(paths)):
                state.restorableTrashPaths = paths
                return .none

            case let .lifecycle(.syncSelectedEntryIDs(ids)):
                state.selectedEntryIDs = ids
                return .none

            case let .lifecycle(.clearError(filePath)):
                state.itemStates[filePath]?.lastError = nil
                return .none

            case let .lifecycle(.operationStarted(filePath, _)):
                state.itemStates[filePath] = ItemOperationState(isBusy: true, lastError: nil)
                return .none

            case let .lifecycle(.operationFinished(filePath, kind, result)),
                 let .lifecycle(.dropOperationFinished(filePath, kind, result)):
                state.itemStates[filePath]?.isBusy = false

                if case .rename = kind {
                    state.renamingItemId = nil
                    state.renamingText = ""
                    state.renamingCommandSource = nil
                }

                switch result {
                case .success:
                    state.itemStates[filePath]?.lastError = nil

                    if case .createFolder = kind {
                        state.renamingItemId = filePath
                        state.renamingText = URL(fileURLWithPath: filePath).lastPathComponent
                        state.renamingCommandSource = .fileManagerContent
                    }

                case let .failure(error):
                    state.itemStates[filePath]?.lastError = error
                }

                var effects: [Effect<EntryOperationsAction>] = []

                // Alert effect (existing behavior)
                if case let .failure(error) = result {
                    if case .getInfo = kind {
                        effects.append(.run { [alertClient] _ in
                            await alertClient.showGetInfoFailureAlert(error.message, error.suggestion)
                        })
                    } else if case .revealInFinder = kind {
                        effects.append(.run { [alertClient] _ in
                            await alertClient.showGetInfoFailureAlert(error.message, error.suggestion)
                        })
                    }
                }

                if case let .failure(error) = result, error != .cancelled {
                    effects.append(.run { [soundClient] _ in
                        await soundClient.play(.error)
                    })
                }

                return effects.isEmpty ? .none : .merge(effects)

            case let .lifecycle(.pathsMutated(paths)):
                let uniquePaths = Array(Set(paths))
                guard !uniquePaths.isEmpty else { return .none }
                return .run { [entryThumbnailCacheClient] _ in
                    await MainActor.run {
                        entryThumbnailCacheClient.removeThumbnails(for: uniquePaths)
                    }
                }

            case let .lifecycle(.entryActionCompleted(record)):
                switch record.operationKind {
                case .moveToTrash:
                    state.restorableTrashPaths.formUnion(record.targets.compactMap(\.afterPath))
                case .putBack:
                    state.restorableTrashPaths.subtract(record.targets.compactMap(\.beforePath))
                default:
                    break
                }

                switch record.operationKind {
                // 성공 사운드는 성공 semantic target이 있을 때만 재생한다(전체 실패 배치는 무음).
                case .moveToTrash:
                    guard !record.targets.isEmpty else { return .none }
                    return .run { [soundClient] _ in
                        await soundClient.play(.moveToTrash)
                    }
                case .pasteFileCopy, .pasteFileMove, .pasteFileDuplicate, .putBack:
                    guard !record.targets.isEmpty else { return .none }
                    return .run { [soundClient] _ in
                        await soundClient.play(.operationCompleted)
                    }
                default:
                    return .none
                }

            case .lifecycle(.emptyTrashCompleted):
                state.restorableTrashPaths = []
                return .run { [soundClient] _ in
                    await soundClient.play(.emptyTrash)
                }

            default:
                return .none
            }
        }
    }

    private func refreshRestorableTrashPaths() -> Effect<Action> {
        .run { [trashMetadataStoreClient] send in
            let paths = await Set(trashMetadataStoreClient.load().map(\.trashPath))
            await send(.lifecycle(.restorableTrashPathsLoaded(paths)))
        }
    }
}
