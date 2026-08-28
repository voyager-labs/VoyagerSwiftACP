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
            case let .routing(.executeCommand(command, context)):
                let outputs = EntryOperationsCommandPlanner.plan(
                    command: command,
                    context: context,
                )
                guard !outputs.isEmpty else { return .none }
                return .merge(outputs.map(effect(for:)))

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

    private func effect(for output: EntryOperationsCommandOutput) -> Effect<Action> {
        switch output {
        case let .entryOperations(action):
            .send(action)
        case let .delegate(delegate):
            .send(.delegate(delegate))
        }
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
