import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

// TODO(voy-142): 타입명과 맞추기 위해 파일명을 EntryIntentDragDropReducer.swift로 변경 필요.
@Reducer
struct EntryIntentDragDropReducer {
    typealias State = EntryState
    typealias Action = EntryAction

    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .startDrag(paths):
                entryFileOpsClient.saveDragPaths(paths)
                let isOptionPressed = NSEvent.modifierFlags.contains(.option)
                entryFileOpsClient.saveDragWithOption(isOptionPressed)
                return .none

            case let .handleDrop(providers, destinationPath):
                let draggedPaths = entryFileOpsClient.loadDragPaths()
                if !draggedPaths.isEmpty {
                    return .send(.dropToFolder(destinationPath: destinationPath))
                }

                entryFileOpsClient.saveDragPaths([])

                return .run { @MainActor send in
                    var urls: [URL] = []
                    for provider in providers
                        where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    {
                        let result: URL? = await withCheckedContinuation { continuation in
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                                var url: URL?
                                if let urlItem = item as? URL {
                                    url = urlItem
                                } else if let data = item as? Data {
                                    url = URL(dataRepresentation: data, relativeTo: nil)
                                }
                                continuation.resume(returning: url)
                            }
                        }
                        if let url = result {
                            urls.append(url)
                        }
                    }

                    if !urls.isEmpty {
                        let paths = urls.map(\.path)
                        let isOption = NSEvent.modifierFlags.contains(.option)
                        await send(.dropItems(
                            sourcePaths: paths,
                            destinationPath: destinationPath,
                            isOptionDrag: isOption,
                        ))
                    }
                }

            case let .handleDropToTag(providers, tagName):
                return .run { @MainActor send in
                    var urls: [URL] = []
                    for provider in providers
                        where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    {
                        let result: URL? = await withCheckedContinuation { continuation in
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                                var url: URL?
                                if let urlItem = item as? URL {
                                    url = urlItem
                                } else if let data = item as? Data {
                                    url = URL(dataRepresentation: data, relativeTo: nil)
                                }
                                continuation.resume(returning: url)
                            }
                        }
                        if let url = result {
                            urls.append(url)
                        }
                    }

                    let paths = urls.map(\.path)
                    guard !paths.isEmpty else { return }
                    await send(.delegate(.intent(.toggleTagForDroppedPaths(paths: paths, tagName: tagName))))
                }

            case let .dropToFolder(destinationPath):
                let sourcePaths = entryFileOpsClient.loadDragPaths()
                let isOptionPressed = entryFileOpsClient.loadDragWithOption()

                entryFileOpsClient.saveDragPaths([])

                guard !sourcePaths.isEmpty else {
                    return .none
                }
                return .send(.dropItems(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    isOptionDrag: isOptionPressed,
                ))

            case let .dropItems(sourcePaths, destinationPath, isOptionDrag):
                guard !sourcePaths.isEmpty else {
                    return .none
                }

                if !isOptionDrag {
                    let sourceParent = URL(fileURLWithPath: sourcePaths[0])
                        .deletingLastPathComponent().path
                    if sourceParent == destinationPath {
                        return .none
                    }

                    for sourcePath in sourcePaths {
                        if destinationPath == sourcePath || isDescendantPath(destinationPath, of: sourcePath) {
                            return .none
                        }
                    }
                }

                state.isDragDropOperation = true

                if destinationPath == state.currentFolderPath {
                    let fileNames = sourcePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
                    state.selectAfterLoadFileNames = fileNames
                }

                let operation: ClipboardOperation = isOptionDrag ? .copy : .cut
                let actionKind: EntryActionRecord.ActionKind = isOptionDrag ? .paste : .move

                return .merge(
                    .send(.delegate(.intent(.pasteItems(
                        sourcePaths: sourcePaths,
                        destinationPath: destinationPath,
                        operation: operation,
                        actionKind: actionKind,
                    )))),
                    .run { [destinationPath] send in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await send(.delegate(.focusWindow(path: destinationPath)))
                    },
                )

            default:
                return .none
            }
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
