import ComposableArchitecture

@Reducer
public struct FileManagerSidebarFeature {
    public typealias State = FileManagerSidebarState
    public typealias Action = FileManagerSidebarAction

    public var body: some Reducer<State, Action> {
        FileManagerSidebarPreferenceReducer()
        FileManagerSidebarContentTabMoveReducer()
        FileManagerSidebarContentTabSyncReducer()
        FileManagerSidebarContentTabSelectionRoutingReducer()
        FileManagerSidebarContentTabDuplicateCloseRoutingReducer()
        FileManagerSidebarContentTabPinRoutingReducer()
        FileManagerSidebarEntryDropRoutingReducer()
        FileManagerSidebarTopNavigationReorderRoutingReducer()
        FileManagerSidebarPresentationRoutingReducer()
    }
}

@Reducer
struct FileManagerSidebarContentTabDuplicateCloseRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .view(.duplicateContentTab(id)):
                .send(.delegate(.duplicateContentTab(id)))

            case .view(.duplicateSelectedContentTabs):
                .send(.delegate(.duplicateSelectedContentTabs))

            case let .view(.closeContentTab(id)):
                .send(.delegate(.closeContentTab(id)))

            case let .view(.closeContentTabFromTrailingControl(id)):
                .send(.delegate(.closeContentTabFromTrailingControl(id)))

            case .view(.closeSelectedContentTabs):
                .send(.delegate(.closeSelectedContentTabs))

            default:
                .none
            }
        }
    }
}

@Reducer
struct FileManagerSidebarPresentationRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard case .view(.dismissTopNavigationPresentation) = action else { return .none }
            return .send(.delegate(.dismissTopNavigationPresentation))
        }
    }
}

@Reducer
struct FileManagerSidebarContentTabSyncReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .internal(.syncContentTabSidebarItems(items)):
                state.contentTabSidebarItems = items
                return .none
            default:
                return .none
            }
        }
    }
}

@Reducer
struct FileManagerSidebarContentTabSelectionRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .view(.toggleContentTabSelection(id)):
                .send(.delegate(.toggleContentTabSelection(id)))

            case let .view(.selectContentTabRange(to: id)):
                .send(.delegate(.selectContentTabRange(to: id)))

            case .view(.collapseContentTabSelectionToActive):
                .send(.delegate(.collapseContentTabSelectionToActive))

            default:
                .none
            }
        }
    }
}

@Reducer
struct FileManagerSidebarContentTabPinRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .view(.pinContentTab(id)):
                .send(.delegate(.pinContentTab(id)))

            case let .view(.unpinContentTab(id)):
                .send(.delegate(.unpinContentTab(id)))

            case let .view(.unpinContentTabFromTrailingControl(id)):
                .send(.delegate(.unpinContentTabFromTrailingControl(id)))

            case let .view(.setSelectedContentTabsPinned(target)):
                .send(.delegate(.setSelectedContentTabsPinned(target: target)))

            default:
                .none
            }
        }
    }
}

@Reducer
struct FileManagerSidebarEntryDropRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard case let .view(.entryDropRequested(request)) = action else {
                return .none
            }
            return .send(.delegate(.entryDropRequested(request)))
        }
    }
}

@Reducer
struct FileManagerSidebarTopNavigationReorderRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard case let .view(.fileManagerTopNavigationReorderRequested(
                sourceID,
                anchorID,
                placement,
                actionSource,
            )) = action
            else {
                return .none
            }
            return .send(.delegate(.fileManagerTopNavigationReorderRequested(
                sourceID: sourceID,
                anchorID: anchorID,
                placement: placement,
                actionSource: actionSource,
            )))
        }
    }
}

@Reducer
struct FileManagerSidebarContentTabMoveReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    @Dependency(\.uuid)
    private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .view(.moveContentTab(tabID, targetWindowID)):
                guard state.pendingContentTabMoveRequest == nil,
                      let sourceWindowID = state.currentWindowID,
                      state.contentTabSidebarItems.contains(where: { $0.id == tabID })
                else { return .none }
                let availableTargets = ContentTabMoveProjection.availableTargets(
                    state.contentTabMoveTargets,
                    currentWindowID: sourceWindowID,
                    tabID: tabID,
                )
                guard availableTargets.contains(where: { $0.windowID == targetWindowID }) else {
                    return .none
                }

                let request = ContentTabMoveRequest(
                    requestID: uuid(),
                    sourceWindowID: sourceWindowID,
                    tabID: tabID,
                    targetWindowID: targetWindowID,
                )
                state.pendingContentTabMoveRequest = request
                return .send(.delegate(.requestContentTabMove(request)))

            case let .view(.moveSelectedContentTabs(initiatingTabID, orderedTabIDs, targetWindowID)):
                guard state.pendingContentTabMoveRequest == nil,
                      let sourceWindowID = state.currentWindowID,
                      !orderedTabIDs.isEmpty,
                      Set(orderedTabIDs).count == orderedTabIDs.count,
                      orderedTabIDs.contains(initiatingTabID)
                else { return .none }
                let sourceTabIDs = Set(state.contentTabSidebarItems.map(\.id))
                guard sourceTabIDs.contains(initiatingTabID) else { return .none }
                let normalizedOrderedTabIDs = orderedTabIDs.filter(sourceTabIDs.contains)
                guard !normalizedOrderedTabIDs.isEmpty else { return .none }

                let availableTargets = ContentTabMoveProjection.availableTargets(
                    state.contentTabMoveTargets,
                    currentWindowID: sourceWindowID,
                    orderedTabIDs: normalizedOrderedTabIDs,
                )
                guard availableTargets.contains(where: { $0.windowID == targetWindowID }) else {
                    return .none
                }

                let requestID = uuid()
                let request = if normalizedOrderedTabIDs.count == 1 {
                    ContentTabMoveRequest(
                        requestID: requestID,
                        sourceWindowID: sourceWindowID,
                        tabID: initiatingTabID,
                        targetWindowID: targetWindowID,
                    )
                } else {
                    ContentTabMoveRequest(
                        operationID: requestID,
                        requestID: requestID,
                        sourceWindowID: sourceWindowID,
                        initiatingTabID: initiatingTabID,
                        orderedTabIDs: normalizedOrderedTabIDs,
                        targetWindowID: targetWindowID,
                    )
                }
                state.pendingContentTabMoveRequest = request
                return .send(.delegate(.requestContentTabMove(request)))

            case let .view(.moveContentTabs(payload, targetWindowID, targetDomain, placement)):
                guard state.pendingContentTabMoveRequest == nil,
                      let sourceWindowID = state.currentWindowID,
                      sourceWindowID == payload.sourceWindowID,
                      !payload.orderedTabIDs.isEmpty,
                      Set(payload.orderedTabIDs).count == payload.orderedTabIDs.count,
                      payload.orderedTabIDs.contains(payload.initiatingTabID)
                else { return .none }
                let sourceTabIDs = Set(state.contentTabSidebarItems.map(\.id))
                guard Set(payload.orderedTabIDs).isSubset(of: sourceTabIDs) else { return .none }

                switch payload.schemaVersion {
                case ContentTabDragPayload.legacySchemaVersion:
                    return .none
                case ContentTabDragPayload.supportedSchemaVersion:
                    guard let snapshot = state.contentTabDragSnapshot,
                          snapshot.lifecycle == .inFlight || snapshot.lifecycle == .awaitingPayload,
                          snapshot.matches(payload)
                    else { return .none }
                default:
                    return .none
                }

                let availableTargets = ContentTabMoveProjection.availableTargets(
                    state.contentTabMoveTargets,
                    currentWindowID: sourceWindowID,
                    orderedTabIDs: payload.orderedTabIDs,
                )
                guard availableTargets.contains(where: { $0.windowID == targetWindowID }) else {
                    return .none
                }

                let requestID = uuid()
                let request = ContentTabMoveRequest(
                    operationID: payload.operationID ?? requestID,
                    requestID: requestID,
                    sourceWindowID: sourceWindowID,
                    initiatingTabID: payload.initiatingTabID,
                    orderedTabIDs: payload.orderedTabIDs,
                    targetWindowID: targetWindowID,
                    sourceDomain: payload.sourceDomain,
                    targetDomain: targetDomain,
                    placement: placement,
                )
                state.contentTabDragSnapshot = nil
                state.pendingContentTabMoveRequest = request
                return .send(.delegate(.requestContentTabMove(request)))

            case let .view(.prepareContentTabDrag(initiatingTabID, selectedTabIDs)):
                guard let sourceWindowID = state.currentWindowID,
                      state.contentTabSidebarItems.contains(where: { $0.id == initiatingTabID })
                else { return .none }
                if case .inFlight = state.contentTabDragSnapshot?.lifecycle {
                    return .none
                }

                // Sidebar 표시 순서와 isPinned에서 source domain lookup을 만들어 frozen batch를 같은 domain으로 좁힌다.
                let domainByTabID = Dictionary(
                    state.contentTabSidebarItems.map {
                        ($0.id, ContentTabDomain.domain(isPinned: $0.isPinned))
                    },
                    uniquingKeysWith: { current, _ in current },
                )
                guard let orderedTabIDs = ContentTabDragSnapshot.frozenOrderedTabIDs(
                    initiatingTabID: initiatingTabID,
                    selectedTabIDs: selectedTabIDs,
                    displayedOrderedTabIDs: state.contentTabSelectionOrderedIDs,
                    sourceTabIDs: Set(domainByTabID.keys),
                    domainForTabID: { domainByTabID[$0] },
                ) else { return .none }
                state.contentTabDragSnapshot = ContentTabDragSnapshot(
                    operationID: uuid(),
                    sourceWindowID: sourceWindowID,
                    initiatingTabID: initiatingTabID,
                    orderedTabIDs: orderedTabIDs,
                    sourceDomain: domainByTabID[initiatingTabID],
                )
                return .none

            case let .view(.beginContentTabDrag(payload)):
                guard var snapshot = state.contentTabDragSnapshot,
                      snapshot.lifecycle == .prepared,
                      snapshot.matches(payload)
                else { return .none }
                snapshot.lifecycle = .inFlight
                state.contentTabDragSnapshot = snapshot
                return .none

            case let .view(.contentTabDragTerminal(operationID)):
                guard var snapshot = state.contentTabDragSnapshot,
                      snapshot.operationID == operationID
                else { return .none }
                switch snapshot.lifecycle {
                case .prepared:
                    state.contentTabDragSnapshot = nil
                case .inFlight:
                    snapshot.lifecycle = .awaitingPayload
                    state.contentTabDragSnapshot = snapshot
                case .awaitingPayload:
                    break
                }
                return .none

            case .view(.teardownContentTabDragSource):
                state.contentTabDragSnapshot = nil
                return .none

            case let .view(.receiveContentTabDrag(payload)):
                guard ContentTabDragPayload.isSupported(schemaVersion: payload.schemaVersion),
                      let currentWindowID = state.currentWindowID,
                      currentWindowID != payload.sourceWindowID,
                      state.pendingContentTabMoveRequest == nil
                else { return .none }
                return .send(.delegate(.receiveContentTabDrag(payload)))

            case let .view(.receiveContentTabExplicitDomainDrag(payload, targetDomain, placement)):
                // 외부 창 explicit domain 경계 drop도 preserve-domain transfer와 동일한 target-side guard를 적용한다.
                // 실제 canonical ContentTabMoveRequest 구성은 window manager가 source 창으로 route한 뒤
                // `moveContentTabs`에서 수행한다. 여기서는 target 가용성/중복 pending만 fail-safe로 검증한다.
                guard ContentTabDragPayload.isSupported(schemaVersion: payload.schemaVersion),
                      let currentWindowID = state.currentWindowID,
                      currentWindowID != payload.sourceWindowID,
                      state.pendingContentTabMoveRequest == nil
                else { return .none }
                return .send(.delegate(.receiveContentTabExplicitDomainDrag(
                    payload: payload,
                    targetDomain: targetDomain,
                    placement: placement,
                )))

            case let .view(.contentTabDomainTransitionRequested(request)):
                return .send(.delegate(.contentTabDomainTransitionRequested(request)))

            default:
                return .none
            }
        }
    }
}
