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
            case let .executeCommand(command, context):
                let outputs = EntryOperationsCommandPlanner.plan(
                    command: command,
                    context: context,
                )
                guard !outputs.isEmpty else { return .none }
                return .merge(outputs.map(effect(for:)))

            case let .validateDrop(context):
                state.dropValidationResult = resolveDropValidation(context)
                return .none

            case let .saveDragPaths(paths):
                entryFileOpsClient.saveDragPaths(paths)
                return .none

            case let .handleDrop(providers: _, destinationPath):
                let internalPaths = entryFileOpsClient.loadDragPaths()
                guard !internalPaths.isEmpty else { return .none }
                let operation: ClipboardOperation = entryFileOpsClient.loadDragWithOption() ? .copy : .cut
                let operationKind: OperationKind = operation == .copy ? .pasteFileCopy : .pasteFileMove
                return .send(.pasteItems(
                    sourcePaths: internalPaths,
                    destinationPath: destinationPath,
                    operation: operation,
                    operationKind: operationKind,
                ))

            case let .dropItems(sourcePaths, destinationPath, isOptionDrag):
                let operation: ClipboardOperation = isOptionDrag ? .copy : .cut
                let operationKind: OperationKind = operation == .copy ? .pasteFileCopy : .pasteFileMove
                return .send(.pasteItems(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    operation: operation,
                    operationKind: operationKind,
                ))

            case let .handleDropToTag(providers, tagName):
                return .run { @MainActor send in
                    let paths = await resolveEntryOperationDroppedPaths(from: providers)
                    guard !paths.isEmpty else { return }
                    send(.requestTagMutation(request: .init(
                        mode: .add,
                        tagName: tagName,
                        paths: paths,
                    )))
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
        case let .navigateFolder(id):
            .send(.delegate(.navigateFolder(id: id)))
        }
    }

    private func resolveDropValidation(_ context: EntryDropValidationContext) -> EntryDropValidationResult {
        let destinationPath = context.destinationPath
        let sourcePaths = context.sourcePaths
        let isInternalDrag = !sourcePaths.isEmpty

        if isInternalDrag, !context.prefersCopy {
            guard let sourcePath = sourcePaths.first else {
                return .init(
                    destinationPath: destinationPath,
                    resolvedOperation: .none,
                    isOptionDrag: false,
                )
            }

            let sourceParent = URL(fileURLWithPath: sourcePath).deletingLastPathComponent().path
            if sourceParent == destinationPath {
                return .init(
                    destinationPath: destinationPath,
                    resolvedOperation: .none,
                    isOptionDrag: false,
                )
            }

            for sourcePath in sourcePaths {
                if destinationPath == sourcePath || isDescendantPath(destinationPath, of: sourcePath) {
                    return .init(
                        destinationPath: destinationPath,
                        resolvedOperation: .none,
                        isOptionDrag: false,
                    )
                }
            }
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
