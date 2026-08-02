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

            case let .routing(.handleDrop(providers: _, destinationPath)):
                let internalPaths = entryFileOpsClient.loadDragPaths()
                guard !internalPaths.isEmpty else { return .none }
                let operation: ClipboardOperation = entryFileOpsClient.loadDragWithOption() ? .copy : .cut
                let operationKind: OperationKind = operation == .copy ? .pasteFileCopy : .pasteFileMove
                return .send(.clipboard(.pasteItems(
                    sourcePaths: topmostPaths(internalPaths),
                    destinationPath: destinationPath,
                    operation: operation,
                    operationKind: operationKind,
                )))

            case let .routing(.dropItems(sourcePaths, destinationPath, isOptionDrag)):
                let topmostSourcePaths = topmostPaths(sourcePaths)
                let validation = EntryDropValidationResolver.resolve(.init(
                    sourcePaths: topmostSourcePaths,
                    destinationPath: destinationPath,
                    allowedOperationsRawValue: NSDragOperation.copy.rawValue | NSDragOperation.move.rawValue,
                    prefersCopy: isOptionDrag,
                ))
                guard validation.resolvedOperation != .none else { return .none }
                let operation: ClipboardOperation = validation.isOptionDrag ? .copy : .cut
                let operationKind: OperationKind = operation == .copy ? .pasteFileCopy : .pasteFileMove
                return .send(.clipboard(.pasteItems(
                    sourcePaths: topmostSourcePaths,
                    destinationPath: destinationPath,
                    operation: operation,
                    operationKind: operationKind,
                )))

            case let .routing(.handleDropToTag(providers, tagName)):
                return .run { @MainActor send in
                    let paths = await resolveEntryOperationDroppedPaths(from: providers)
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

    private func isDescendantPath(_ destinationPath: String, of sourcePath: String) -> Bool {
        let destinationComponents = URL(fileURLWithPath: destinationPath)
            .standardizedFileURL.pathComponents
        let sourceComponents = URL(fileURLWithPath: sourcePath)
            .standardizedFileURL.pathComponents

        guard destinationComponents.count > sourceComponents.count else {
            return false
        }

        return Array(destinationComponents.prefix(sourceComponents.count)) == sourceComponents
    }

    private func topmostPaths(_ paths: [String]) -> [String] {
        paths.filter { path in
            !paths.contains { otherPath in
                otherPath != path && isDescendantPath(path, of: otherPath)
            }
        }
    }
}

private func resolveEntryOperationDroppedPaths(from providers: [NSItemProvider]) async -> [String] {
    var paths: [String] = []
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        if let path = await resolveEntryOperationDroppedPath(from: provider) {
            paths.append(path)
        }
    }
    return paths
}

private func resolveEntryOperationDroppedPath(from provider: NSItemProvider) async -> String? {
    await withCheckedContinuation { continuation in
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let url = item as? URL {
                continuation.resume(returning: url.path)
                return
            }

            if let data = item as? Data {
                if let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString)
                {
                    continuation.resume(returning: url.path)
                    return
                }

                if let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url.path)
                    return
                }

                continuation.resume(returning: nil)
                return
            }

            if let urlString = item as? String,
               let url = URL(string: urlString)
            {
                continuation.resume(returning: url.path)
                return
            }

            continuation.resume(returning: nil)
        }
    }
}
