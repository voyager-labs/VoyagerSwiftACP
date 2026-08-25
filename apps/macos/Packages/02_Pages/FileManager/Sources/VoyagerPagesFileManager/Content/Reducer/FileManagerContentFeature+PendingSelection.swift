import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

/// 네비게이션 기원 pending selection의 로딩 이벤트 브리지.
/// FileManagerContentFeature 본문의 세대 바인딩·터미널 소비 규칙을 담당한다.
extension FileManagerContentFeature {
    func handlePendingSelectionBeforeEntryLayoutLoaded(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action> {
        guard case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))) = action,
              case let .coreBatch(items: entries, batchIndex: batchIndex) = streamEvent.event,
              streamEvent.generation == state.entryViewLayout.entryOperations.loadingContext.generation,
              batchIndex == state.entryViewLayout.entryOperations.loadingContext.expectedCoreBatchIndex
        else {
            return .none
        }
        guard FileManagerContentEntryOpsCoordinator.applyPendingSelectionForLoadedEntries(
            entries: entries,
            state: &state,
        ) else {
            return .none
        }
        return .send(.entryViewLayout(.delegate(.selectionChanged)))
    }

    /// 터미널 로딩 이벤트의 pending selection 소비 규칙. nil 반환 시 후속 핸들러로 흐른다.
    func handlePendingSelectionTerminal(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        guard isCurrentNavigationPendingSelection(state) else { return nil }

        switch action {
        case let .entryViewLayout(.entryOperations(.loading(.streamFinished(generation)))),
             let .entryViewLayout(.entryOperations(.loading(.streamFailed(generation)))):
            // 네비게이션 기원 pending은 목적지 로드 세대에 바인딩된 경우에만 소비한다.
            // 목적지 loadItems가 세대를 증가시키기 전에 도착한 이전 로딩의 터미널은 무시한다.
            guard generation == state.entryViewLayout.entryOperations.loadingContext.generation,
                  state.pendingSelectEntryLoadGeneration == generation
            else {
                return .none
            }
            let entries = Array(state.entryViewLayout.entryOperations.loadingContext.items)
            if FileManagerContentEntryOpsCoordinator.applyPendingSelectionForLoadedEntries(
                entries: entries,
                state: &state,
            ) {
                return .send(.entryViewLayout(.delegate(.selectionChanged)))
            }
            state.setPendingEntrySelection(entryID: nil, destinationPath: nil)
            return .none

        case .entryViewLayout(.entryOperations(.loading(.itemsLoadFailed))):
            // itemsLoadFailed는 바인딩된 pending 세대가 현재 로딩 세대와 일치할 때만 pending을 정리한다.
            guard state.pendingSelectEntryLoadGeneration == state.entryViewLayout.entryOperations.loadingContext
                .generation
            else {
                return .none
            }
            state.setPendingEntrySelection(entryID: nil, destinationPath: nil)
            return .none

        default:
            return nil
        }
    }

    /// 자식 리듀서 통과 후 처리: 목적지 폴더 로드 세대에 네비게이션 기원 pending을 바인딩하고,
    /// legacy itemsLoaded 경로의 선택 적용을 수행한다.
    func handlePendingSelectionAfterEntryLayoutLoaded(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case .entryViewLayout(.entryOperations(.loading(.loadItems))):
            // loadItems가 EntryViewLayoutFeature를 통과해 로딩 세대가 증가된 뒤 네비게이션 기원 pending을
            // 현재 세대에 바인딩한다. destination이 nil인 외부 오픈 pending은 세대 바인딩 대상이 아니다.
            if isCurrentNavigationPendingSelection(state) {
                state.pendingSelectEntryLoadGeneration = state.entryViewLayout.entryOperations.loadingContext
                    .generation
            }
            return .none
        case let .entryViewLayout(.entryOperations(.loading(.itemsLoaded(loadedEntries)))):
            return handleLegacyItemsLoaded(loadedEntries, state: &state)
        case .entryViewLayout(.entryOperations(.loading(.streamEvent))):
            return .none
        default:
            return .none
        }
    }

    private func handleLegacyItemsLoaded(
        _ entries: [EntryModel],
        state: inout State,
    ) -> Effect<Action> {
        guard FileManagerContentEntryOpsCoordinator.applyPendingSelectionForLoadedEntries(
            entries: entries,
            state: &state,
        ) else {
            if isCurrentNavigationPendingSelection(state) {
                state.setPendingEntrySelection(entryID: nil, destinationPath: nil)
            }
            return .none
        }
        return .send(.entryViewLayout(.delegate(.selectionChanged)))
    }

    private func isCurrentNavigationPendingSelection(_ state: State) -> Bool {
        guard let destinationPath = state.pendingSelectEntryDestinationPath else { return false }
        guard case let .folder(path) = state.navigation.navigationState else { return false }
        return URL(fileURLWithPath: path).standardizedFileURL.path
            == URL(fileURLWithPath: destinationPath).standardizedFileURL.path
    }
}
