import CoreGraphics
import Foundation

enum EntryOperationsCommand {
    case navigation(EntryOperationsNavigationCommand)
    case clipboard(EntryOperationsClipboardCommand)
    case mutation(EntryOperationsMutationCommand)
}

enum EntryOperationsNavigationCommand {
    case openSelectedItem
    case quickLookSelectedItem
    case getInfoForSelectedItems
    case shareSelectedItems(anchor: CGPoint?)
    case revealSelectedItemsInFinder
    case performService(serviceName: String)
    case openWithSelectedItem(bundleID: String?, shouldSetAsDefault: Bool)
}

enum EntryOperationsClipboardCommand {
    case copySelectedItems
    case cutSelectedItems
    case pasteItems(destinationPath: String)
    case duplicateSelectedItems
    case copySelectedAbsolutePaths
    case copySelectedURLs
}

enum EntryOperationsMutationCommand {
    case createAliasForSelectedItems
    case compressSelectedItems
    case extractSelectedItem
    case toggleTagForSelectedItem(tag: String)
    case moveSelectedItemsToTrash
    case deleteSelectedItemsImmediately
    case putBackSelectedItems
    case emptyTrash
}

struct EntryOperationsCommandContext {
    var selectedIds: Set<EntryModel.ID>
    var displayItems: [EntryModel]
    var currentPath: String
}

enum EntryOperationsCommandOutput {
    case entryOperations(EntryOperationsAction)
    case delegate(EntryOperationsDelegate)
}

enum EntryOperationsCommandPlanner {
    static func plan(
        command: EntryOperationsCommand,
        context: EntryOperationsCommandContext,
    ) -> [EntryOperationsCommandOutput] {
        switch command {
        case let .navigation(command):
            planNavigation(command, context: context)
        case let .clipboard(command):
            planClipboard(command, context: context)
        case let .mutation(command):
            planMutation(command, context: context)
        }
    }

    private static func planNavigation(
        _ command: EntryOperationsNavigationCommand,
        context: EntryOperationsCommandContext,
    ) -> [EntryOperationsCommandOutput] {
        let selected = selectedItems(in: context)

        switch command {
        case .openSelectedItem:
            return planOpenSelectedItem(selected)
        case .quickLookSelectedItem:
            return planQuickLookSelectedItem(selected)
        case .getInfoForSelectedItems:
            return planGetInfoForSelectedItems(selected)
        case let .shareSelectedItems(anchor):
            return planShareSelectedItems(selected, anchor: anchor)
        case .revealSelectedItemsInFinder:
            return planRevealSelectedItemsInFinder(selected)
        case let .performService(serviceName):
            return planPerformService(selected, serviceName: serviceName)
        case let .openWithSelectedItem(bundleID, shouldSetAsDefault):
            return openWithOutputs(
                selectedItems: selected,
                bundleID: bundleID,
                shouldSetAsDefault: shouldSetAsDefault,
            )
        }
    }

    private static func planClipboard(
        _ command: EntryOperationsClipboardCommand,
        context: EntryOperationsCommandContext,
    ) -> [EntryOperationsCommandOutput] {
        switch command {
        case .copySelectedItems:
            planCopySelectedItems(context)
        case .cutSelectedItems:
            planCutSelectedItems(context)
        case let .pasteItems(destinationPath):
            [.entryOperations(.pasteItemsFromClipboard(destinationPath: destinationPath))]
        case .duplicateSelectedItems:
            planDuplicateSelectedItems(context)
        case .copySelectedAbsolutePaths:
            planCopySelectedAbsolutePaths(context)
        case .copySelectedURLs:
            planCopySelectedURLs(context)
        }
    }

    private static func planMutation(
        _ command: EntryOperationsMutationCommand,
        context: EntryOperationsCommandContext,
    ) -> [EntryOperationsCommandOutput] {
        switch command {
        case .createAliasForSelectedItems:
            planCreateAliasForSelectedItems(context)
        case .compressSelectedItems:
            planCompressSelectedItems(context)
        case .extractSelectedItem:
            planExtractSelectedItem(context)
        case let .toggleTagForSelectedItem(tag):
            planToggleTagForSelectedItem(context, tag: tag)
        case .moveSelectedItemsToTrash:
            planMoveSelectedItemsToTrash(context)
        case .deleteSelectedItemsImmediately:
            planDeleteSelectedItemsImmediately(context)
        case .putBackSelectedItems:
            planPutBackSelectedItems(context)
        case .emptyTrash:
            [.entryOperations(.emptyTrash(paths: context.displayItems.map(\.fullPath)))]
        }
    }

    private static func selectedItems(in context: EntryOperationsCommandContext) -> [EntryModel] {
        context.displayItems.filter { context.selectedIds.contains($0.id) }
    }

    private static func selectedPaths(in context: EntryOperationsCommandContext) -> [String] {
        selectedItems(in: context).map(\.fullPath)
    }

    private static func planOpenSelectedItem(_ selected: [EntryModel]) -> [EntryOperationsCommandOutput] {
        guard !selected.isEmpty else { return [] }
        if selected.count == 1, let entry = selected.first {
            let url = URL(fileURLWithPath: entry.fullPath)
            if CollectionFileUtils.isCollectionFile(url) {
                return [.delegate(.openCollectionFile(url))]
            }

            if entry.isFolder {
                return [.delegate(.navigateToPath(entry.fullPath))]
            }
        }
        return [.entryOperations(.openFiles(paths: selected.map(\.fullPath)))]
    }

    private static func planQuickLookSelectedItem(_ selected: [EntryModel]) -> [EntryOperationsCommandOutput] {
        if selected.count == 1, let path = selected.first?.fullPath {
            return [.entryOperations(.quickLookFile(path: path))]
        }
        guard !selected.isEmpty else { return [] }
        return [.entryOperations(.quickLookFiles(paths: selected.map(\.fullPath)))]
    }

    private static func planGetInfoForSelectedItems(_ selected: [EntryModel]) -> [EntryOperationsCommandOutput] {
        guard !selected.isEmpty else { return [] }
        return [.entryOperations(.openFinderInfo(paths: selected.map(\.fullPath)))]
    }

    private static func planShareSelectedItems(
        _ selected: [EntryModel],
        anchor: CGPoint?,
    ) -> [EntryOperationsCommandOutput] {
        guard !selected.isEmpty else { return [] }
        return [.entryOperations(.shareItems(paths: selected.map(\.fullPath), anchor: anchor))]
    }

    private static func planRevealSelectedItemsInFinder(_ selected: [EntryModel]) -> [EntryOperationsCommandOutput] {
        guard !selected.isEmpty else { return [] }
        return [.entryOperations(.revealInFinder(paths: selected.map(\.fullPath)))]
    }

    private static func planPerformService(
        _ selected: [EntryModel],
        serviceName: String,
    ) -> [EntryOperationsCommandOutput] {
        guard !selected.isEmpty else { return [] }
        return [.entryOperations(.performService(paths: selected.map(\.fullPath), name: serviceName))]
    }

    private static func planCopySelectedItems(_ context: EntryOperationsCommandContext)
        -> [EntryOperationsCommandOutput]
    {
        let selected = selectedItems(in: context)
        guard !selected.isEmpty else { return [] }
        return [.entryOperations(.copySelectedItems(files: selected))]
    }

    private static func planCutSelectedItems(_ context: EntryOperationsCommandContext)
        -> [EntryOperationsCommandOutput]
    {
        let selected = selectedItems(in: context)
        guard !selected.isEmpty else { return [] }
        return [
            .entryOperations(.copySelectedItems(files: selected)),
            .entryOperations(.setClipboardOperation(operation: .cut)),
        ]
    }

    private static func planDuplicateSelectedItems(_ context: EntryOperationsCommandContext)
        -> [EntryOperationsCommandOutput]
    {
        let selectedPaths = selectedPaths(in: context)
        guard !selectedPaths.isEmpty else { return [] }
        return [
            .entryOperations(.pasteItems(
                sourcePaths: selectedPaths,
                destinationPath: context.currentPath,
                operation: .copy,
                operationKind: .pasteFileDuplicate,
            )),
        ]
    }

    private static func planCopySelectedAbsolutePaths(_ context: EntryOperationsCommandContext)
        -> [EntryOperationsCommandOutput]
    {
        let selectedPaths = selectedPaths(in: context)
        guard !selectedPaths.isEmpty else { return [] }
        return [.entryOperations(.copyAbsolutePaths(paths: selectedPaths))]
    }

    private static func planCopySelectedURLs(_ context: EntryOperationsCommandContext)
        -> [EntryOperationsCommandOutput]
    {
        let selectedPaths = selectedPaths(in: context)
        guard !selectedPaths.isEmpty else { return [] }
        return [.entryOperations(.copyURLs(paths: selectedPaths))]
    }

    private static func planCreateAliasForSelectedItems(
        _ context: EntryOperationsCommandContext,
    ) -> [EntryOperationsCommandOutput] {
        let selectedPaths = selectedPaths(in: context)
        guard !selectedPaths.isEmpty else { return [] }
        return [.entryOperations(.createAliases(paths: selectedPaths))]
    }

    private static func planCompressSelectedItems(_ context: EntryOperationsCommandContext)
        -> [EntryOperationsCommandOutput]
    {
        let selectedPaths = selectedPaths(in: context)
        guard !selectedPaths.isEmpty else { return [] }
        return [.entryOperations(.compressItems(paths: selectedPaths))]
    }

    private static func planExtractSelectedItem(_ context: EntryOperationsCommandContext)
        -> [EntryOperationsCommandOutput]
    {
        guard let selectedPath = selectedPaths(in: context).first else { return [] }
        return [.entryOperations(.extractCompressedFile(path: selectedPath))]
    }

    private static func planToggleTagForSelectedItem(
        _ context: EntryOperationsCommandContext,
        tag: String,
    ) -> [EntryOperationsCommandOutput] {
        let selectedPaths = selectedPaths(in: context)
        guard !selectedPaths.isEmpty else { return [] }
        return [
            .entryOperations(.requestTagMutation(request: .init(
                mode: .toggle,
                tagName: tag,
                paths: selectedPaths,
            ))),
        ]
    }

    private static func planMoveSelectedItemsToTrash(
        _ context: EntryOperationsCommandContext,
    ) -> [EntryOperationsCommandOutput] {
        let selectedPaths = selectedPaths(in: context)
        guard !selectedPaths.isEmpty else { return [] }
        return [.entryOperations(.moveToTrash(paths: selectedPaths))]
    }

    private static func planDeleteSelectedItemsImmediately(
        _ context: EntryOperationsCommandContext,
    ) -> [EntryOperationsCommandOutput] {
        let selectedPaths = selectedPaths(in: context)
        guard !selectedPaths.isEmpty else { return [] }
        return [.entryOperations(.deleteImmediately(paths: selectedPaths))]
    }

    private static func planPutBackSelectedItems(
        _ context: EntryOperationsCommandContext,
    ) -> [EntryOperationsCommandOutput] {
        let selectedPaths = selectedPaths(in: context)
        guard !selectedPaths.isEmpty else { return [] }
        return [.entryOperations(.putBackFromTrash(paths: selectedPaths))]
    }

    private static func openWithOutputs(
        selectedItems: [EntryModel],
        bundleID: String?,
        shouldSetAsDefault: Bool,
    ) -> [EntryOperationsCommandOutput] {
        let selectedFiles = selectedItems.filter { !$0.isFolder }
        guard !selectedFiles.isEmpty else { return [] }

        if let bundleID {
            return selectedFiles.flatMap { file -> [EntryOperationsCommandOutput] in
                var outputs: [EntryOperationsCommandOutput] = []
                if shouldSetAsDefault {
                    outputs.append(.entryOperations(.setDefaultAppForFile(
                        type: nil,
                        bundleID: bundleID,
                        file: file,
                    )))
                }
                outputs.append(.entryOperations(.openFileWithAppBundleID(
                    filePath: file.fullPath,
                    bundleID: bundleID,
                    url: URL(fileURLWithPath: file.fullPath),
                )))
                return outputs
            }
        }

        if selectedFiles.count == 1, let file = selectedFiles.first {
            return [
                .entryOperations(
                    shouldSetAsDefault
                        ? .setDefaultAppWithOther(file: file)
                        : .openFileWithApp(file: file),
                ),
            ]
        }

        return [
            .entryOperations(
                .openFilesWithAppFromOther(
                    files: selectedFiles,
                    shouldSetAsDefault: shouldSetAsDefault,
                ),
            ),
        ]
    }
}
