import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@Reducer
struct EntryOperationsCommandRoutingReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    private var entryFileOpsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .routing(.executeCommand(command, context)):
                let outputs = EntryOperationsCommandPlanner.plan(
                    command: command,
                    context: context,
                )
                guard !outputs.isEmpty else { return .none }
                return .merge(outputs.map(effect(for:)))

            case let .routing(.validateDrop(context)):
                state.dropValidationResult = resolveDropValidation(context)
                return .none

            case let .routing(.saveDragPaths(paths)):
                entryFileOpsClient.saveDragPaths(paths)
                entryFileOpsClient.saveDragWithOption(entryFileOpsClient.loadDragWithOption())
                return .none

            case let .routing(.handleDrop(providers, destinationPath, isOptionDrag)):
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
                guard isOptionDrag || isAllowedMoveDrop(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                ) else { return .none }
                return .send(.clipboard(.performDrop(
                    sourcePaths: sourcePaths,
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

    private func effect(for output: EntryOperationsCommandOutput) -> Effect<Action> {
        switch output {
        case let .entryOperations(action):
            .send(action)
        case let .delegate(delegate):
            .send(.delegate(delegate))
        }
    }

    private func resolveDropValidation(_ context: EntryDropValidationContext) -> EntryDropValidationResult {
        let destinationPath = context.destinationPath
        let sourcePaths = context.sourcePaths
        let isInternalDrag = !sourcePaths.isEmpty

        if isInternalDrag,
           !context.prefersCopy,
           !isAllowedMoveDrop(sourcePaths: sourcePaths, destinationPath: destinationPath)
        {
            return .init(
                destinationPath: destinationPath,
                resolvedOperation: .none,
                isOptionDrag: false,
            )
        }

        let allowedOperations = NSDragOperation(rawValue: context.allowedOperationsRawValue)
        let preferredOperation: EntryDropResolvedOperation = context.prefersCopy ? .copy : .move
        if contains(allowedOperations, preferredOperation) {
            return .init(
                destinationPath: destinationPath,
                resolvedOperation: preferredOperation,
                isOptionDrag: preferredOperation == .copy,
            )
        }

        if contains(allowedOperations, .copy) {
            return .init(
                destinationPath: destinationPath,
                resolvedOperation: .copy,
                isOptionDrag: true,
            )
        }

        return .init(
            destinationPath: destinationPath,
            resolvedOperation: .none,
            isOptionDrag: false,
        )
    }

    private func isAllowedMoveDrop(sourcePaths: [String], destinationPath: String) -> Bool {
        guard let sourcePath = sourcePaths.first else { return false }
        let sourceParent = URL(fileURLWithPath: sourcePath).deletingLastPathComponent().path
        guard !EntryDropPathPolicy.areEquivalent(sourceParent, destinationPath) else { return false }
        return !sourcePaths.contains {
            EntryDropPathPolicy.isSameOrDescendant(destinationPath, of: $0)
        }
    }

    private func contains(_ allowed: NSDragOperation, _ operation: EntryDropResolvedOperation) -> Bool {
        switch operation {
        case .none:
            false
        case .copy:
            allowed.contains(.copy)
        case .move:
            allowed.contains(.move)
        }
    }
}
