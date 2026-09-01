import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesEntry

@Reducer
struct EntryOperationsCommandRoutingReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    private var entryFileOpsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .routing(.executeCommand(command, context, metadata)):
                let outputs = EntryOperationsCommandPlanner.plan(
                    command: command,
                    context: context,
                )
                guard !outputs.isEmpty else { return .none }
                return .merge(outputs.map { effect(for: $0, metadata: metadata) })

            case let .acceptedCommand(
                metadata,
                .routing(.handleDrop(providers, destinationPath, isOptionDrag)),
            ) where !providers.isEmpty:
                return .run { @MainActor send in
                    let sourcePaths = await resolveEntryDroppedPaths(from: providers)
                    guard !sourcePaths.isEmpty else {
                        send(Self.cancelledDropTerminal(
                            metadata: metadata,
                            operationKind: isOptionDrag ? .pasteFileCopy : .pasteFileMove,
                            cancelledCount: providers.count,
                        ))
                        return
                    }
                    await send(.acceptedCommand(
                        metadata: metadata,
                        action: .routing(.dropItems(
                            sourcePaths: sourcePaths,
                            destinationPath: destinationPath,
                            isOptionDrag: isOptionDrag,
                        )),
                    ))
                }

            case let .acceptedCommand(metadata, .routing(.handleDropToTrash(providers)))
                where !providers.isEmpty:
                return .run { @MainActor send in
                    let paths = await resolveEntryDroppedPaths(from: providers)
                    guard !paths.isEmpty else {
                        send(Self.cancelledDropTerminal(
                            metadata: metadata,
                            operationKind: .moveToTrash,
                            cancelledCount: providers.count,
                        ))
                        return
                    }
                    await send(.acceptedCommand(
                        metadata: metadata,
                        action: .trash(.moveToTrash(paths: paths)),
                    ))
                }

            case let .acceptedCommand(
                metadata,
                .routing(.dropItems(sourcePaths, destinationPath, isOptionDrag)),
            ) where !sourcePaths.isEmpty:
                let topmostSourcePaths = topmostPaths(sourcePaths)
                let validation = EntryDropValidationResolver.resolve(.init(
                    sourcePaths: topmostSourcePaths,
                    destinationPath: destinationPath,
                    allowedOperationsRawValue: NSDragOperation.copy.rawValue | NSDragOperation.move.rawValue,
                    prefersCopy: isOptionDrag,
                ))
                guard validation.resolvedOperation != .none else {
                    return .send(Self.cancelledDropTerminal(
                        metadata: metadata,
                        operationKind: isOptionDrag ? .pasteFileCopy : .pasteFileMove,
                        cancelledCount: topmostSourcePaths.count,
                    ))
                }
                return .send(.acceptedCommand(
                    metadata: metadata,
                    action: .clipboard(.performDrop(
                        sourcePaths: topmostSourcePaths,
                        destinationPath: destinationPath,
                        isOptionDrag: isOptionDrag,
                    )),
                ))

            case let .acceptedCommand(metadata, nestedAction):
                let effect = if case .routing = nestedAction {
                    EntryOperationsCommandRoutingReducer().reduce(into: &state, action: nestedAction)
                } else {
                    EntryOperationsExecutionReducer().reduce(into: &state, action: nestedAction)
                }
                return effect.map { Self.propagate(metadata, through: $0) }

            case let .routing(.validateDrop(context)):
                state.dropValidationResult = EntryDropValidationResolver.resolve(context)
                return .none

            case let .routing(.saveDragPaths(paths)):
                entryFileOpsClient.saveDragPaths(paths)
                entryFileOpsClient.saveDragWithOption(entryFileOpsClient.loadDragWithOption())
                return .none

            case let .routing(.handleDrop(providers, destinationPath, isOptionDrag)):
                if providers.isEmpty {
                    let sourcePaths = entryFileOpsClient.loadDragPaths()
                    guard !sourcePaths.isEmpty else { return .none }
                    return .send(.routing(.dropItems(
                        sourcePaths: sourcePaths,
                        destinationPath: destinationPath,
                        isOptionDrag: isOptionDrag,
                    )))
                }
                return .run { @MainActor send in
                    let sourcePaths = await resolveEntryDroppedPaths(from: providers)
                    guard !sourcePaths.isEmpty else { return }
                    await send(.routing(.dropItems(
                        sourcePaths: sourcePaths,
                        destinationPath: destinationPath,
                        isOptionDrag: isOptionDrag,
                    )))
                }

            case let .routing(.handleDropToTrash(providers)):
                return .run { @MainActor send in
                    let paths = await resolveEntryDroppedPaths(from: providers)
                    guard !paths.isEmpty else { return }
                    send(.trash(.moveToTrash(paths: paths)))
                }

            case let .routing(.dropItems(sourcePaths, destinationPath, isOptionDrag)):
                let topmostSourcePaths = topmostPaths(sourcePaths)
                let validation = EntryDropValidationResolver.resolve(.init(
                    sourcePaths: topmostSourcePaths,
                    destinationPath: destinationPath,
                    allowedOperationsRawValue: NSDragOperation.copy.rawValue | NSDragOperation.move.rawValue,
                    prefersCopy: isOptionDrag,
                ))
                guard validation.resolvedOperation != .none else { return .none }
                return .send(.clipboard(.performDrop(
                    sourcePaths: topmostSourcePaths,
                    destinationPath: destinationPath,
                    isOptionDrag: isOptionDrag,
                )))

            case let .routing(.handleDropToTag(providers, tagName)):
                return .run { @MainActor send in
                    let paths = await resolveEntryDroppedPaths(from: providers)
                    guard !paths.isEmpty else { return }
                    send(.tagging(.requestTagMutation(request: .init(
                        mode: .add,
                        tagName: tagName,
                        paths: paths,
                    ))))
                }

            default:
                return .none
            }
        }
    }

    private func effect(
        for output: EntryOperationsCommandOutput,
        metadata: EntryCommandMetadata,
    ) -> Effect<Action> {
        switch output {
        case let .entryOperations(action):
            .send(.acceptedCommand(metadata: metadata, action: action))
        case let .delegate(delegate):
            .send(.delegate(delegate))
        }
    }

    private static func propagate(
        _ metadata: EntryCommandMetadata,
        through action: Action,
    ) -> Action {
        switch action {
        case let .lifecycle(.entryActionCompleted(record)):
            .lifecycle(.entryActionCompleted(record.attaching(command: metadata)))
        case .lifecycle, .delegate, .outcome:
            action
        default:
            .acceptedCommand(metadata: metadata, action: action)
        }
    }

    private static func cancelledDropTerminal(
        metadata: EntryCommandMetadata,
        operationKind: OperationKind,
        cancelledCount: Int,
    ) -> Action {
        .lifecycle(.entryActionCompleted(EntryActionRecord(
            operationKind: operationKind,
            targets: [],
            failedCount: 0,
            cancelledCount: cancelledCount,
            succeededCount: 0,
            id: metadata.id,
            timestamp: Date(),
        ).attaching(command: metadata)))
    }

    private func topmostPaths(_ paths: [String]) -> [String] {
        paths.filter { path in
            !paths.contains { otherPath in
                otherPath != path && EntryDropPathPolicy.isDescendant(path, of: otherPath)
            }
        }
    }

    private func isAllowedMoveDrop(sourcePaths: [String], destinationPath: String) -> Bool {
        guard let sourcePath = sourcePaths.first else { return false }
        let sourceParent = URL(fileURLWithPath: sourcePath).deletingLastPathComponent().path
        guard !EntryDropPathPolicy.areEquivalent(sourceParent, destinationPath) else { return false }
        return !sourcePaths.contains {
            EntryDropPathPolicy.isSameOrDescendant(destinationPath, of: $0)
        }
    }
}
