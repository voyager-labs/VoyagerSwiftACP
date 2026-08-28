import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

private typealias SecurePlacementCopy = @Sendable (URL, URL) async throws -> Bool

public struct EntryClipboardOperationsCutClearMonitor: Sendable {
    public var heuristic: EntryOperationsCutClearHeuristic

    public struct RuntimeContext: Sendable {
        public var now: Date
        public var readPasteboardChangeCount: @Sendable () -> Int
        public var readPasteboardCutSessionId: @Sendable () -> String?
        public var fileExists: @Sendable (String) -> Bool

        public init(
            now: Date,
            readPasteboardChangeCount: @Sendable @escaping () -> Int,
            readPasteboardCutSessionId: @Sendable @escaping () -> String?,
            fileExists: @Sendable @escaping (String) -> Bool,
        ) {
            self.now = now
            self.readPasteboardChangeCount = readPasteboardChangeCount
            self.readPasteboardCutSessionId = readPasteboardCutSessionId
            self.fileExists = fileExists
        }
    }

    public enum Decision: Equatable, Sendable {
        case noop
        case keep(EntryOperationsCutClearHeuristic.CutSession)
        case clear
    }

    public init(heuristic: EntryOperationsCutClearHeuristic = .init()) {
        self.heuristic = heuristic
    }

    public func evaluateOnAppDidBecomeActive(
        clipboardOperation: ClipboardOperation,
        clipboardItems: [String],
        session: EntryOperationsCutClearHeuristic.CutSession?,
        makeSession: (_ now: Date, _ sourcePaths: [String]) -> EntryOperationsCutClearHeuristic.CutSession?,
        context: RuntimeContext,
    ) -> Decision {
        guard clipboardOperation == .cut, !clipboardItems.isEmpty else {
            return .noop
        }

        guard let activeSession = session ?? makeSession(context.now, clipboardItems) else {
            return .clear
        }

        switch heuristic.evaluate(
            session: activeSession,
            now: context.now,
            readPasteboardChangeCount: context.readPasteboardChangeCount,
            readPasteboardCutSessionId: context.readPasteboardCutSessionId,
            fileExists: context.fileExists,
        ) {
        case let .keep(updatedSession):
            return .keep(updatedSession)
        case .clear:
            return .clear
        }
    }
}

@Reducer
struct EntryClipboardOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient
    @Dependency(\.entryOperationsAlertClient)
    var alertClient
    @Dependency(\.pasteboardClient)
    var pasteboardClient
    @Dependency(\.uuid)
    var uuid
    @Dependency(\.externalDropAcquisitionClient)
    var acquisitionClient

    /// copyPath terminal은 pasteboard write 성공 여부를 그대로 집계한다.
    private func copyPathTerminal(didWrite: Bool) -> EntryActionRecord {
        EntryActionRecord(
            operationKind: .copyPath,
            targets: [],
            failedCount: didWrite ? 0 : 1,
            succeededCount: didWrite ? 1 : 0,
        )
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .clipboard(.copySelectedItems(files)):
                state.clipboardItems = files.map(\.fullPath)
                state.clipboardOperation = .copy
                state.cutClearSession = nil
                entryFileOpsClient.saveClipboardCutSessionId(nil)

                pasteboardClient.clearContents()

                let urls = files.map { URL(fileURLWithPath: $0.fullPath) }
                let didWrite = pasteboardClient.writeObjects(urls as [NSURL])
                entryFileOpsClient.postFileSystemChanged([])

                return .send(.lifecycle(.entryActionCompleted(EntryActionRecord(
                    operationKind: .copyPath,
                    targets: [],
                    failedCount: didWrite ? 0 : 1,
                    succeededCount: didWrite ? 1 : 0,
                ))))

            case .lifecycle(.loadClipboardState):
                let (clipboardPaths, clipboardOperation) = entryFileOpsClient.loadClipboardPaths()
                return .send(.lifecycle(.syncClipboardState(paths: clipboardPaths, operation: clipboardOperation)))

            case .lifecycle(.appDidBecomeActive):
                let now = Date()
                let monitor = EntryClipboardOperationsCutClearMonitor()
                let decision = monitor.evaluateOnAppDidBecomeActive(
                    clipboardOperation: state.clipboardOperation,
                    clipboardItems: state.clipboardItems,
                    session: state.cutClearSession,
                    makeSession: { now, sourcePaths in
                        guard !sourcePaths.isEmpty else {
                            return nil
                        }

                        let existingSessionId = entryFileOpsClient.loadClipboardCutSessionId()
                        let sessionId = existingSessionId ?? uuid().uuidString
                        if existingSessionId == nil {
                            entryFileOpsClient.saveClipboardCutSessionId(sessionId)
                        }

                        let heuristic = EntryOperationsCutClearHeuristic()
                        return heuristic.makeInitialSession(
                            cutSessionId: sessionId,
                            pasteboardChangeCount: entryFileOpsClient.clipboardChangeCount(),
                            sourcePaths: sourcePaths,
                            now: now,
                        )
                    },
                    context: .init(
                        now: now,
                        readPasteboardChangeCount: entryFileOpsClient.clipboardChangeCount,
                        readPasteboardCutSessionId: entryFileOpsClient.loadClipboardCutSessionId,
                        fileExists: entryFileOpsClient.fileExists,
                    ),
                )

                switch decision {
                case .noop:
                    return .none
                case let .keep(updatedSession):
                    state.cutClearSession = updatedSession
                    return .none
                case .clear:
                    return .send(.clipboard(.setClipboardOperation(operation: .copy)))
                }

            case let .clipboard(.copyAbsolutePaths(paths)):
                guard !paths.isEmpty else { return .none }

                let text = paths.joined(separator: "\n")
                pasteboardClient.clearContents()
                let didWrite = pasteboardClient.setString(text, .string)

                return .send(.lifecycle(.entryActionCompleted(
                    copyPathTerminal(didWrite: didWrite),
                )))

            case let .clipboard(.copyURLs(paths)):
                guard !paths.isEmpty else { return .none }

                let text = paths
                    .map { URL(fileURLWithPath: $0).absoluteString }
                    .joined(separator: "\n")
                pasteboardClient.clearContents()
                let didWrite = pasteboardClient.setString(text, .string)

                return .send(.lifecycle(.entryActionCompleted(
                    copyPathTerminal(didWrite: didWrite),
                )))

            case let .clipboard(.setClipboardOperation(operation)):
                state.clipboardOperation = operation
                let operationValue = operation == .cut ? "cut" : "copy"
                _ = pasteboardClient.setString(
                    operationValue,
                    NSPasteboard.PasteboardType("fm.voyager.clipboard.operation"),
                )

                if operation == .cut {
                    guard !state.clipboardItems.isEmpty else {
                        state.cutClearSession = nil
                        entryFileOpsClient.saveClipboardCutSessionId(nil)
                        return .none
                    }

                    let cutSessionId = uuid().uuidString
                    entryFileOpsClient.saveClipboardCutSessionId(cutSessionId)
                    let heuristic = EntryOperationsCutClearHeuristic()
                    state.cutClearSession = heuristic.makeInitialSession(
                        cutSessionId: cutSessionId,
                        pasteboardChangeCount: entryFileOpsClient.clipboardChangeCount(),
                        sourcePaths: state.clipboardItems,
                        now: Date(),
                    )
                } else {
                    state.cutClearSession = nil
                    entryFileOpsClient.saveClipboardCutSessionId(nil)
                }

                return .none

            case let .lifecycle(.syncClipboardState(paths, operation)):
                state.clipboardItems = paths
                state.clipboardOperation = operation

                guard operation == .cut, !paths.isEmpty else {
                    state.cutClearSession = nil
                    return .none
                }

                let existingSessionId = entryFileOpsClient.loadClipboardCutSessionId()
                let sessionId = existingSessionId ?? uuid().uuidString
                if existingSessionId == nil {
                    entryFileOpsClient.saveClipboardCutSessionId(sessionId)
                }

                let heuristic = EntryOperationsCutClearHeuristic()
                state.cutClearSession = heuristic.makeInitialSession(
                    cutSessionId: sessionId,
                    pasteboardChangeCount: entryFileOpsClient.clipboardChangeCount(),
                    sourcePaths: paths,
                    now: Date(),
                )
                return .none

            case let .clipboard(.pasteItemsFromClipboard(destinationPath)):
                let (clipboardPaths, clipboardOperation) = entryFileOpsClient.loadClipboardPaths()
                guard !clipboardPaths.isEmpty else {
                    return .none
                }

                let operationKind: OperationKind = clipboardOperation == .cut ? .pasteFileMove : .pasteFileCopy

                return .concatenate(
                    .send(.lifecycle(.syncClipboardState(paths: clipboardPaths, operation: clipboardOperation))),
                    .send(.clipboard(.pasteItems(
                        sourcePaths: clipboardPaths,
                        destinationPath: destinationPath,
                        operation: clipboardOperation,
                        operationKind: operationKind,
                    ))),
                )

            case let .clipboard(.pasteItems(sourcePaths, destinationPath, operation, operationKind)):
                // 외부 drop placement(.externalObjectImportItem) 복사는 세션별 CancelID로 등록해
                // resetForDuplicate가 진행 중 복사를 취소할 수 있게 한다. 또 effect가 취소되면
                // (창 닫힘 등 child store 제거) acquisition 세션을 finish해 staging/session
                // registry가 영구 잔류하지 않도록 정리한다.
                let placementSessionID: ExternalDropSessionID? = operationKind == .externalObjectImportItem
                    ? state.externalDropImportPlacement?.sessionID
                    : nil
                if operationKind == .externalObjectImportItem, placementSessionID == nil {
                    // placement 세션이 없는 외부 import는 일반 mutable paste로 강등하지 않고
                    // 항목별 실패로 닫는다(fail-closed).
                    return .run { send in
                        for sourcePath in sourcePaths {
                            await send(.lifecycle(.operationFinished(
                                sourcePath,
                                operationKind,
                                .failure(.system(message: "외부 drop placement 세션이 없다")),
                            )))
                        }
                    }
                }
                let secureCopy: SecurePlacementCopy? = if let placementSessionID {
                    { [acquisitionClient] sourceURL, destinationURL in
                        try await acquisitionClient.copyPlacementSource(
                            placementSessionID,
                            sourceURL.path,
                            destinationURL.path,
                        )
                    }
                } else {
                    nil
                }
                var effect = pasteItemsEffect(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    operation: operation,
                    operationKind: operationKind,
                    mutationImpactDestinationPath: nil,
                    onCancelCleanup: placementSessionID.map { sessionID in
                        { @MainActor in acquisitionClient.finish(sessionID) }
                    },
                    secureCopy: secureCopy,
                )
                if let placementSessionID {
                    effect = effect.cancellable(id: CancelID.externalDrop(placementSessionID))
                }
                return effect

            case let .clipboard(.duplicateItems(groups)):
                let destinations = groups.flatMap { group in
                    EntryClipboardOperationsSupport.avoidNameCollisions(
                        sourcePaths: group.sourcePaths,
                        destinationURL: URL(fileURLWithPath: group.destinationPath),
                        operation: .copy,
                        entryFileOpsClient: entryFileOpsClient,
                    )
                }
                return pasteDestinationsEffect(
                    destinations,
                    operation: .copy,
                    operationKind: .pasteFileDuplicate,
                    mutationImpactDestinationPath: nil,
                )

            case let .clipboard(.performDrop(sourcePaths, destinationPath, isOptionDrag)):
                let operation: ClipboardOperation = isOptionDrag ? .copy : .cut
                let operationKind: OperationKind = operation == .copy ? .pasteFileCopy : .pasteFileMove
                return pasteItemsEffect(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    operation: operation,
                    operationKind: operationKind,
                    mutationImpactDestinationPath: destinationPath,
                )

            default:
                return .none
            }
        }
    }

    private func pasteItemsEffect(
        sourcePaths: [String],
        destinationPath: String,
        operation: ClipboardOperation,
        operationKind: OperationKind,
        mutationImpactDestinationPath: String?,
        onCancelCleanup: (@MainActor @Sendable () -> Void)? = nil,
        secureCopy: SecurePlacementCopy? = nil,
    ) -> Effect<Action> {
        let destinations = EntryClipboardOperationsSupport.avoidNameCollisions(
            sourcePaths: sourcePaths,
            destinationURL: URL(fileURLWithPath: destinationPath),
            operation: operation,
            entryFileOpsClient: entryFileOpsClient,
        )
        guard !destinations.isEmpty else {
            return operation == .cut
                ? .send(.lifecycle(.operationFinished(destinationPath, operationKind, .success(()))))
                : .none
        }

        return pasteDestinationsEffect(
            destinations,
            operation: operation,
            operationKind: operationKind,
            mutationImpactDestinationPath: mutationImpactDestinationPath,
            onCancelCleanup: onCancelCleanup,
            secureCopy: secureCopy,
        )
    }

    private func pasteDestinationsEffect(
        _ destinations: [(URL, URL)],
        operation: ClipboardOperation,
        operationKind: OperationKind,
        mutationImpactDestinationPath: String?,
        onCancelCleanup: (@MainActor @Sendable () -> Void)? = nil,
        secureCopy: SecurePlacementCopy? = nil,
    ) -> Effect<Action> {
        let executor = EntryClipboardOperationsSupport.PasteExecutor(
            entryFileOpsClient: entryFileOpsClient,
            alertClient: alertClient,
            mutationImpactDestinationPath: mutationImpactDestinationPath,
            secureCopy: secureCopy,
        )
        let copyLoop: @Sendable (Send<Action>) async throws -> Void = { send in
            var targets: [EntryActionRecord.Target] = []
            var failedCount = 0
            var cancelledCount = 0
            for (sourceURL, destinationURL) in destinations {
                // resetForDuplicate가 effect task를 취소한 뒤에도 live pasteFile(동기 copyItem)은
                // CancellationError를 던지지 않아 루프가 남은 항목까지 계속 진행할 수 있다.
                // 각 항목 복사 전에 명시적으로 취소를 확인해 즉시 중단한다.
                try Task.checkCancellation()
                await send(.lifecycle(.operationStarted(sourceURL.path, operationKind)))
                let result = await executor.execute(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    isCopy: operation == .copy,
                    operationKind: operationKind,
                    send: send,
                )
                switch result {
                case let .success(target):
                    targets.append(target)
                case let .failure(error):
                    if error == .cancelled {
                        cancelledCount += 1
                    } else {
                        failedCount += 1
                    }
                }
            }
            await executor.finishBatch(
                targets,
                failedCount: failedCount,
                cancelledCount: cancelledCount,
                operationKind: operationKind,
                send: send,
            )
        }
        guard let onCancelCleanup else {
            return .run { send in
                try await copyLoop(send)
            }
        }
        // placement 복사 effect가 취소(창 닫힘 등 child store 제거)되면 획득 세션을
        // finish해 staging과 session registry가 영구 잔류하지 않게 정리한다. finish는
        // copyLoop가 종료된 뒤(현재 동기 pasteFile이 반환된 후)에만 수행해, 복사 도중
        // staging이 제거돼 부분 실패/잔류가 생기지 않게 한다. 정상 완료는 reducer의
        // finishPlacementIfComplete가 담당하므로 취소된 경우에만 여기서 정리한다.
        return .run { send in
            defer {
                if Task.isCancelled {
                    Task { @MainActor in
                        onCancelCleanup()
                    }
                }
            }
            try await copyLoop(send)
        }
    }
}

private enum EntryClipboardOperationsSupport {
    struct PasteExecutor {
        let entryFileOpsClient: EntryFileOpsClient
        let alertClient: EntryOperationsAlertClient
        let mutationImpactDestinationPath: String?
        let secureCopy: SecurePlacementCopy?

        func execute(
            sourceURL: URL,
            destinationURL: URL,
            isCopy: Bool,
            operationKind: OperationKind,
            send: Send<EntryOperationsAction>,
        ) async -> Result<EntryActionRecord.Target, FileOpError> {
            let context = OperationContext(isCopy: isCopy, operationKind: operationKind)
            do {
                try await mutate(context: context, sourceURL: sourceURL, destinationURL: destinationURL)
                return await .success(finishSuccess(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    context: .init(
                        finishPath: sourceURL.path,
                        operationKind: operationKind,
                        repeatsPathsMutation: true,
                    ),
                    send: send,
                ))
            } catch let error as FileOpError where error.isFileExists {
                return await replaceExistingItem(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    context: context,
                    error: error,
                    send: send,
                )
            } catch {
                await send(completionAction(
                    sourceURL.path,
                    operationKind: operationKind,
                    result: .failure(error.fileOpError),
                ))
                return .failure(error.fileOpError)
            }
        }

        func finishBatch(
            _ targets: [EntryActionRecord.Target],
            failedCount: Int,
            cancelledCount: Int,
            operationKind: OperationKind,
            send: Send<EntryOperationsAction>,
        ) async {
            // 전체 실패 배치도 실패 aggregate를 담은 terminal로 마무리한다.
            // undo 등록은 소비자가 successful targets 존재로 게이트한다.
            if operationKind.isUndoable {
                let record = EntryActionRecord(
                    operationKind: operationKind,
                    targets: targets,
                    failedCount: failedCount,
                    cancelledCount: cancelledCount,
                    succeededCount: targets.count,
                    id: UUID(),
                    timestamp: Date(),
                )
                await send(.lifecycle(.entryActionCompleted(record)))
            }
            guard !targets.isEmpty, let mutationImpactDestinationPath else { return }
            let impact = EntryOperationsMutationImpact(
                sourceParentPaths: EntryClipboardOperationsSupport.uniqueSourceParentPaths(from: targets),
                destinationPath: mutationImpactDestinationPath,
            )
            await send(.outcome(.entriesMutated(impact)))
        }

        private func replaceExistingItem(
            sourceURL: URL,
            destinationURL: URL,
            context: OperationContext,
            error: FileOpError,
            send: Send<EntryOperationsAction>,
        ) async -> Result<EntryActionRecord.Target, FileOpError> {
            guard let itemName = error.itemName else {
                await send(completionAction(
                    sourceURL.path,
                    operationKind: context.operationKind,
                    result: .failure(error),
                ))
                return .failure(error)
            }
            guard await alertClient.showReplaceAlert(itemName, .move) == .replace else {
                await send(completionAction(
                    sourceURL.path,
                    operationKind: context.operationKind,
                    result: .failure(.cancelled),
                ))
                return .failure(.cancelled)
            }
            do {
                // 기존 목적지를 먼저 삭제하지 않고 같은 디렉터리 임시 이름으로 치워둔다
                // (코멘트 #3837908188). 복사가 성공한 뒤에만 임시 항목을 제거하고, 실패 시
                // 원래 항목을 되돌려 새 파일·기존 파일 이중 상실을 막는다.
                let backupURL = destinationURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(".voyager-replace-\(UUID().uuidString)")
                try await entryFileOpsClient.moveFile(destinationURL, backupURL)
                do {
                    try await mutate(context: context, sourceURL: sourceURL, destinationURL: destinationURL)
                } catch {
                    // 부분 목적지 정리와 백업 복원을 시도한다. 복원에 실패하면 백업이
                    // 임시 이름에 남은 채 묻히지 않도록 복구 오류로 전파한다(코멘트 #3837956593).
                    // 부분 목적지는 copier가 생성 전에 실패하면 존재하지 않는다. 정리는
                    // 선택적으로 처리하고 백업 복원은 항상 시도하며, 복원 자체가 실패할
                    // 때만 복구 오류로 전파한다(코멘트 #3840293881).
                    try? await entryFileOpsClient.deleteImmediately(destinationURL)
                    do {
                        try await entryFileOpsClient.moveFile(backupURL, destinationURL)
                    } catch {
                        throw FileOpError.system(
                            message: "교체 복구 실패, 원본 백업이 \(backupURL.path)에 보존됐다",
                        )
                    }
                    throw error
                }
                try? await entryFileOpsClient.deleteImmediately(backupURL)
                return await .success(finishSuccess(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    context: .init(
                        finishPath: sourceURL.path,
                        operationKind: context.operationKind,
                        repeatsPathsMutation: false,
                    ),
                    send: send,
                ))
            } catch {
                await send(completionAction(
                    sourceURL.path,
                    operationKind: context.operationKind,
                    result: .failure(error.fileOpError),
                ))
                return .failure(error.fileOpError)
            }
        }

        private func completionAction(
            _ path: String,
            operationKind: OperationKind,
            result: Result<Void, FileOpError>,
        ) -> EntryOperationsAction {
            if mutationImpactDestinationPath == nil {
                return .lifecycle(.operationFinished(path, operationKind, result))
            }
            return .lifecycle(.dropOperationFinished(path, operationKind, result))
        }

        private func mutate(context: OperationContext, sourceURL: URL, destinationURL: URL) async throws {
            switch (context.isCopy, context.operationKind) {
            case (true, .externalObjectImportItem):
                // 외부 import는 고정 descriptor 복사만 허용한다. copier 부재·false 반환을
                // 일반 paste 경로로 강등하지 않는 fail-closed 계약이다.
                guard let secureCopy else {
                    throw FileOpError.system(message: "placement copier가 준비되지 않았다")
                }
                do {
                    guard try await secureCopy(sourceURL, destinationURL) else {
                        throw FileOpError.system(message: "placement copier가 항목을 처리하지 않았다")
                    }
                } catch let error as POSIXError where error.code == .EEXIST {
                    // descriptor 복사의 O_EXCL 목적지 충돌을 기존 교체 알림 계약으로 정규화한다.
                    // stop/replace와 per-item 집합 의미는 execute의 fileExists 분기가 소유한다.
                    throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
                }
            case (true, _):
                try await entryFileOpsClient.pasteFile(sourceURL, destinationURL)
            case (false, _):
                try await entryFileOpsClient.moveFile(sourceURL, destinationURL)
            }
        }

        private func finishSuccess(
            sourceURL: URL,
            destinationURL: URL,
            context: SuccessContext,
            send: Send<EntryOperationsAction>,
        ) async -> EntryActionRecord.Target {
            let mutatedPaths = [sourceURL.path, destinationURL.path]
            await send(.lifecycle(.pathsMutated(mutatedPaths)))
            if mutationImpactDestinationPath == nil {
                entryFileOpsClient.postFileSystemChanged([
                    sourceURL.deletingLastPathComponent().path,
                    destinationURL.deletingLastPathComponent().path,
                ])
            }
            if context.repeatsPathsMutation {
                await send(.lifecycle(.pathsMutated(mutatedPaths)))
            }
            await send(completionAction(
                context.finishPath,
                operationKind: context.operationKind,
                result: .success(()),
            ))
            return .init(beforePath: sourceURL.path, afterPath: destinationURL.path)
        }
    }

    private struct OperationContext {
        let isCopy: Bool
        let operationKind: OperationKind
    }

    private struct SuccessContext {
        let finishPath: String
        let operationKind: OperationKind
        let repeatsPathsMutation: Bool
    }

    static func uniqueSourceParentPaths(from targets: [EntryActionRecord.Target]) -> [String] {
        var result: [String] = []

        for target in targets {
            guard let sourcePath = target.beforePath else { continue }
            let parentPath = URL(fileURLWithPath: sourcePath).deletingLastPathComponent().path
            if !result.contains(where: { EntryDropPathPolicy.areEquivalent($0, parentPath) }) {
                result.append(parentPath)
            }
        }

        return result
    }

    static func avoidNameCollisions(
        sourcePaths: [String],
        destinationURL: URL,
        operation: ClipboardOperation,
        entryFileOpsClient: EntryFileOpsClient,
    ) -> [(URL, URL)] {
        var destinations: [(URL, URL)] = []
        var reservedNameKeys: Set<String> = []
        let volumeSupportsCaseSensitiveNames = (try? destinationURL.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey],
        ))?.volumeSupportsCaseSensitiveNames ?? false

        for sourcePath in sourcePaths {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let fileName = sourceURL.lastPathComponent
            let sourceParent = sourceURL.deletingLastPathComponent()

            if operation == .cut, sourceParent == destinationURL {
                continue
            }

            var destURL = destinationURL.appendingPathComponent(fileName)
            let collisionInBatch = reservedNameKeys.contains(destinationNameKey(
                destURL.lastPathComponent,
                volumeSupportsCaseSensitiveNames: volumeSupportsCaseSensitiveNames,
            ))
            if collisionInBatch
                || (operation == .copy
                    && sourceParent == destinationURL
                    && entryFileOpsClient.fileExists(destURL.path))
            {
                destURL = nextAvailableDestinationURL(
                    baseName: fileName,
                    destinationURL: destinationURL,
                    reservedNameKeys: reservedNameKeys,
                    volumeSupportsCaseSensitiveNames: volumeSupportsCaseSensitiveNames,
                    entryFileOpsClient: entryFileOpsClient,
                )
            }

            reservedNameKeys.insert(destinationNameKey(
                destURL.lastPathComponent,
                volumeSupportsCaseSensitiveNames: volumeSupportsCaseSensitiveNames,
            ))
            destinations.append((sourceURL, destURL))
        }

        return destinations
    }

    private static func nextAvailableDestinationURL(
        baseName: String,
        destinationURL: URL,
        reservedNameKeys: Set<String>,
        volumeSupportsCaseSensitiveNames: Bool,
        entryFileOpsClient: EntryFileOpsClient,
    ) -> URL {
        let nameWithoutExtension = URL(fileURLWithPath: baseName)
            .deletingPathExtension()
            .lastPathComponent
        let fileExtension = URL(fileURLWithPath: baseName).pathExtension
        var counter = 1
        while true {
            let name: String = if counter == 1 {
                fileExtension.isEmpty
                    ? "\(nameWithoutExtension) copy"
                    : "\(nameWithoutExtension) copy.\(fileExtension)"
            } else {
                fileExtension.isEmpty
                    ? "\(nameWithoutExtension) copy \(counter)"
                    : "\(nameWithoutExtension) copy \(counter).\(fileExtension)"
            }
            let candidate = destinationURL.appendingPathComponent(name)
            let reserved = reservedNameKeys.contains(destinationNameKey(
                candidate.lastPathComponent,
                volumeSupportsCaseSensitiveNames: volumeSupportsCaseSensitiveNames,
            ))
            let filesystemCollision = entryFileOpsClient.fileExists(candidate.path)
            if !reserved, !filesystemCollision {
                return candidate
            }
            counter += 1
        }
    }

    private static func destinationNameKey(
        _ name: String,
        volumeSupportsCaseSensitiveNames: Bool,
    ) -> String {
        let casedName = volumeSupportsCaseSensitiveNames
            ? name
            : name.folding(options: [.caseInsensitive], locale: nil)
        return casedName.precomposedStringWithCanonicalMapping
    }
}
