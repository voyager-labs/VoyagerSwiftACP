@preconcurrency import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry

extension EntryListCoordinator: NSOutlineViewDataSource {
    public func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item else { return outlineItems.count }
        guard let outlineItem = item as? OutlineItem else { return 0 }
        return outlineItem.children.count
    }

    public func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        switch outlineItem.kind {
        case .group:
            return !outlineItem.children.isEmpty
        case let .entry(entry):
            return isHierarchyOutlineEnabled && entry.supportsListHierarchyExpansion
        case .empty, .error:
            return false
        }
    }

    public func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item else { return outlineItems[index] }
        guard let outlineItem = item as? OutlineItem else { return outlineItems[index] }
        return outlineItem.children[index]
    }

    public func outlineView(_: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let outlineItem = item as? OutlineItem else { return nil }
        guard case let .entry(entry) = outlineItem.kind else { return nil }
        return NSURL(fileURLWithPath: entry.fullPath)
    }

    public func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: any NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex _: Int,
    ) -> NSDragOperation {
        var destinationPath = state.currentPath
        if let outlineItem = item as? OutlineItem,
           case let .entry(entry) = outlineItem.kind,
           entry.isFolder,
           !entry.isPackage
        {
            outlineView.setDropItem(outlineItem, dropChildIndex: NSOutlineViewDropOnItemIndex)
            destinationPath = entry.fullPath
        } else {
            outlineView.setDropItem(nil, dropChildIndex: -1)
        }

        let origin = resolveDropOrigin(info, ownView: outlineView)
        // 외부 promise 드래그는 source path 유무와 무관하게 획득 경로가 우선한다.
        // Photos는 file URL과 promise를 함께 제공해 sourcePaths가 비지 않으므로
        // path 검증보다 먼저 판정해야 acceptDrop이 획득 세션을 시작할 수 있다.
        if EntryViewLayoutDropValidationAdapter.prefersPromiseAcquisition(
            draggingInfo: info,
            isInternalDrag: origin.isInternal,
        ) {
            store.send(.view(.setDropTargeted(true)))
            return .copy
        }
        // 빈 source는 항상 no-op으로 처리한다 (reducer의 empty-source 방어 이전 단계).
        // 단, 외부 promise/mixed drag는 source path가 없어도 pasteboard가 지원 표현을
        // 노출하면 `.copy`를 제안해 acceptDrop이 획득 세션을 시작할 수 있게 한다.
        guard !origin.sourcePaths.isEmpty else {
            let hasRepresentation = !origin.isInternal
                && EntryViewLayoutDropValidationAdapter.hasSupportedExternalRepresentation(
                    in: info.draggingPasteboard,
                )
            let operationRawValue = hasRepresentation ? NSDragOperation.copy.rawValue : NSDragOperation().rawValue
            EntryViewLayoutDropValidationAdapter.validationLogger.info(
                "list empty rep=\(hasRepresentation, privacy: .public) op=\(operationRawValue, privacy: .public)",
            )
            if hasRepresentation {
                store.send(.view(.setDropTargeted(true)))
                return .copy
            }
            outlineView.setDropItem(nil, dropChildIndex: -1)
            store.send(.view(.setDropTargeted(false)))
            return []
        }
        let validation = EntryViewLayoutDropValidationAdapter.resolve(
            sourcePaths: origin.sourcePaths,
            destinationPath: destinationPath,
            allowedOperations: info.draggingSourceOperationMask,
            prefersCopy: origin.wantsCopy,
        )
        let operation = EntryViewLayoutDropValidationAdapter.dragOperation(from: validation.resolvedOperation)
        store.send(.view(.setDropTargeted(!operation.isEmpty)))
        return operation
    }

    public func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: any NSDraggingInfo,
        item: Any?,
        childIndex _: Int,
    ) -> Bool {
        var destinationPath = state.currentPath
        if let outlineItem = item as? OutlineItem,
           case let .entry(entry) = outlineItem.kind,
           entry.isFolder,
           !entry.isPackage
        {
            destinationPath = entry.fullPath
        }

        let origin = resolveDropOrigin(info, ownView: outlineView)
        // promise/mixed 외부 drop은 path 기반 이동이 아니라 ExternalDropAcquisitionClient로
        // 획득 세션을 시작하고, 그 결과를 EntryOperations에 accepted action으로 전달한다.
        // promise-only는 source path가 없어 아래 empty-source guard보다 먼저 처리해야 한다.
        let negotiation = EntryViewLayoutDropValidationAdapter.negotiateExternalDrop(
            from: info.draggingPasteboard,
            wantsCopy: origin.wantsCopy,
        )
        if !negotiation.promisedOrdinals.isEmpty || !negotiation.dataFlavors.isEmpty {
            return beginExternalDropAcquisition(
                draggingInfo: info,
                negotiation: negotiation,
                destinationPath: destinationPath,
            )
        }
        // 빈 source는 항상 no-op으로 처리한다 (reducer의 empty-source 방어 이전 단계).
        guard !origin.sourcePaths.isEmpty else {
            clearListDropTargetState()
            return false
        }
        let validation = EntryViewLayoutDropValidationAdapter.resolve(
            sourcePaths: origin.sourcePaths,
            destinationPath: destinationPath,
            allowedOperations: info.draggingSourceOperationMask,
            prefersCopy: origin.wantsCopy,
        )
        let resolvedOperation = EntryViewLayoutDropValidationAdapter.dragOperation(from: validation.resolvedOperation)
        guard !resolvedOperation.isEmpty else {
            // accept-reject terminal path: transport/visual 상태를 정리한다.
            clearListDropTargetState()
            return false
        }
        store.send(.view(.dropItems(
            sourcePaths: origin.sourcePaths,
            destinationPath: destinationPath,
            isOptionDrag: validation.isOptionDrag,
        )))
        if !origin.isInternal {
            // 외부 accept는 transport를 정리하고 visual highlight를 유지하지 않는다.
            // 내부 accept transport 정리는 `draggingSession endedAt` + `EntryViewLayoutDragStateClearRuleSet`이 담당한다.
            clearListDropTargetState()
        }
        return true
    }

    /// external accept/reject terminal 경로에서 transport와 visual highlight를 정리한다.
    private func clearListDropTargetState() {
        entryFileOpsClient.saveDragPaths([])
        store.send(.view(.setDropTargeted(false)))
    }

    /// 외부 drop 세션 진입/거절 시 transport·visual highlight를 정리한다 (List 기존 동작 유지).
    @MainActor
    func clearExternalDropDropState() {
        clearListDropTargetState()
    }

    /// promise/mixed 외부 drop의 획득 세션을 시작한다. 공유 adapter 구현에 위임한다.
    @MainActor
    private func beginExternalDropAcquisition(
        draggingInfo: any NSDraggingInfo,
        negotiation: EntryViewLayoutDropValidationAdapter.ExternalDropNegotiation,
        destinationPath: String,
    ) -> Bool {
        EntryViewLayoutDropValidationAdapter.beginExternalDropAcquisition(
            activeSessionID: &activeExternalDropSessionID,
            context: .init(
                client: externalDropAcquisitionClient,
                sendAccepted: { [weak self] request in
                    self?.store.send(.view(.externalDropAccepted(request: request)))
                },
                clearDropState: { [weak self] in
                    self?.clearExternalDropDropState()
                },
            ),
            draggingInfo: draggingInfo,
            negotiation: negotiation,
            destinationPath: destinationPath,
        )
    }

    /// 현재 활성 외부 drop 획득 세션이 있으면 해당 세션만 취소하고 정리한다.
    /// representable teardown / current-path change에서 호출되며, 취소된 세션이 다음 Grid/List 세션을 오염시키지 않는다.
    @MainActor
    func cancelActiveExternalDropSession() {
        EntryViewLayoutDropValidationAdapter.cancelActiveExternalDropSession(
            activeSessionID: &activeExternalDropSessionID,
            client: externalDropAcquisitionClient,
            sendCancelSession: { [weak self] sessionID in
                self?.store.send(.view(.externalDropCancelSession(sessionID)))
            },
        )
    }

    /// 내부/외부 drop origin과 active source path를 결정한다.
    /// 외부 session 진입 시 stale 내부 transport를 무효화한다 (FIX 7).
    @MainActor
    private func resolveDropOrigin(
        _ draggingInfo: any NSDraggingInfo,
        ownView: AnyObject?,
    ) -> EntryViewLayoutDropValidationAdapter.DropOrigin {
        let transportPaths = entryFileOpsClient.loadDragPaths()
        let isInternal = EntryViewLayoutDropValidationAdapter.isInternalDrag(draggingInfo, ownView: ownView)
        if isInternal {
            return .init(
                sourcePaths: transportPaths,
                wantsCopy: NSEvent.modifierFlags.contains(.option),
                isInternal: true,
            )
        }
        entryFileOpsClient.saveDragPaths([])
        return .init(
            sourcePaths: EntryViewLayoutDropValidationAdapter.sourcePaths(from: draggingInfo.draggingPasteboard),
            wantsCopy: NSEvent.modifierFlags.contains(.option),
            isInternal: false,
        )
    }
}

extension EntryListCoordinator: NSTextFieldDelegate {
    public func controlTextDidChange(_ notification: Notification) {
        guard let renamingItemId = state.entryOperations.renamingItemId else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard (textField.delegate as AnyObject?) === self else { return }
        guard let renamingItem = state.entries.first(where: { $0.id == renamingItemId }) else { return }
        store.send(.view(.startRename(item: renamingItem, text: textField.stringValue)))
    }

    public func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard state.entryOperations.renamingItemId != nil else { return false }
        guard let textField = control as? NSTextField else { return false }
        guard (textField.delegate as AnyObject?) === self else { return false }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            store.send(.view(.commitRename(
                itemID: state.entryOperations.renamingItemId ?? "",
                newName: textField.stringValue,
            )))
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            store.send(.delegate(.renameCanceled))
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            store.send(.view(.commitRename(
                itemID: state.entryOperations.renamingItemId ?? "",
                newName: textField.stringValue,
            )))
            return true
        }

        return false
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        guard state.entryOperations.renamingItemId != nil else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard (textField.delegate as AnyObject?) === self else { return }
        store.send(.view(.commitRename(
            itemID: state.entryOperations.renamingItemId ?? "",
            newName: textField.stringValue,
        )))
    }
}
