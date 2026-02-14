import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@Reducer
struct EntryIntentOpenReducer {
    typealias State = EntryState
    typealias Action = EntryAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .delegate:
                return .none

            case .navigateFolder:
                return .none

            case .openCollectionFile:
                return .none

            case .openSelectedItem:
                guard !state.selectedIds.isEmpty else {
                    return .none
                }

                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                let selectedCollections = selectedItems.filter { $0.fileExtension.lowercased() == "voycoll" }
                if !selectedCollections.isEmpty, selectedCollections.count == selectedItems.count {
                    if selectedCollections.count == 1, let item = selectedCollections.first {
                        return .send(.openCollectionFile(URL(fileURLWithPath: item.fullPath)))
                    }
                    return .concatenate(selectedCollections.map {
                        .send(.openCollectionFile(URL(fileURLWithPath: $0.fullPath)))
                    })
                }

                let selectedPackages = selectedItems.filter { EntryReducerSupport.isPackageItem($0) }
                let selectedFolders = selectedItems.filter { $0.isDirectory && !EntryReducerSupport.isPackageItem($0) }
                let selectedFiles = selectedItems.filter { !$0.isDirectory } + selectedPackages

                if selectedFolders.count == 1, selectedFiles.isEmpty {
                    return .send(.navigateFolder(id: selectedFolders[0].id))
                } else if selectedFolders.count > 1, selectedFiles.isEmpty {
                    let folderPaths = selectedFolders.map(\.fullPath)
                    return .send(.delegate(.openFoldersInNewWindows(paths: folderPaths)))
                } else if !selectedFolders.isEmpty {
                    let folderPaths = selectedFolders.map(\.fullPath)
                    let openWindowsEffect: Effect<Action> =
                        .send(.delegate(.openFoldersInNewWindows(paths: folderPaths)))

                    guard !selectedFiles.isEmpty else {
                        return openWindowsEffect
                    }

                    return .merge(
                        openWindowsEffect,
                        .send(.delegate(.intent(.openFiles(files: selectedFiles)))),
                    )
                }

                guard !selectedFiles.isEmpty else {
                    return .none
                }

                if selectedFolders.isEmpty,
                   selectedFiles.count == 1,
                   let file = selectedFiles.first,
                   URL(fileURLWithPath: file.fullPath).pathExtension.lowercased() == "voycoll"
                {
                    return .send(.openCollectionFile(URL(fileURLWithPath: file.fullPath)))
                }

                return .send(.delegate(.intent(.openFiles(files: selectedFiles))))

            case .quickLookSelectedItem:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else { return .none }

                if selectedItems.count == 1, let item = selectedItems.first {
                    return .send(.delegate(.intent(.quickLookFile(file: item))))
                }

                return .send(.delegate(.intent(.quickLookFiles(files: selectedItems))))

            case .getInfoForSelectedItems:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else { return .none }
                return .send(.delegate(.intent(.openFinderInfo(items: selectedItems))))

            case let .shareSelectedItems(anchor):
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else { return .none }
                return .send(.delegate(.intent(.shareItems(items: selectedItems, anchor: anchor))))

            case .revealSelectedItemsInFinder:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else { return .none }
                return .send(.delegate(.intent(.revealInFinder(items: selectedItems))))

            case let .performService(serviceName):
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else { return .none }
                return .send(.delegate(.intent(.performService(items: selectedItems, name: serviceName))))

            case let .openWithSelectedItem(bundleID, shouldSetAsDefault):
                let selectedFiles = EntryReducerSupport.getSelectedFiles(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )

                guard !selectedFiles.isEmpty else { return .none }

                if selectedFiles.count == 1 {
                    guard let item = selectedFiles.first else { return .none }

                    if let bundleID {
                        let filePath = item.fullPath
                        let url = URL(fileURLWithPath: filePath)
                        let fileType = UTType(filenameExtension: item.fileExtension)

                        var effects: [Effect<Action>] = []

                        if shouldSetAsDefault, let fileType {
                            effects.append(.send(.delegate(.intent(.setDefaultAppForFile(
                                type: fileType,
                                bundleID: bundleID,
                                file: item,
                            )))))
                        }

                        effects.append(.send(.delegate(.intent(.openFileWithAppBundleID(
                            filePath: filePath,
                            bundleID: bundleID,
                            url: url,
                        )))))

                        return .concatenate(effects)
                    } else {
                        if shouldSetAsDefault {
                            return .send(.delegate(.intent(.setDefaultAppWithOther(file: item))))
                        } else {
                            return .send(.delegate(.intent(.openFileWithApp(file: item))))
                        }
                    }
                } else {
                    if let bundleID {
                        var effects: [Effect<Action>] = []

                        for file in selectedFiles {
                            let filePath = file.fullPath
                            let url = URL(fileURLWithPath: filePath)
                            let fileType = UTType(filenameExtension: file.fileExtension)

                            if shouldSetAsDefault, let fileType {
                                effects.append(.send(.delegate(.intent(.setDefaultAppForFile(
                                    type: fileType,
                                    bundleID: bundleID,
                                    file: file,
                                )))))
                            }

                            effects.append(.send(.delegate(.intent(.openFileWithAppBundleID(
                                filePath: filePath,
                                bundleID: bundleID,
                                url: url,
                            )))))
                        }

                        return .concatenate(effects)
                    } else {
                        return .send(.delegate(.intent(.openFilesWithAppFromOther(
                            files: selectedFiles,
                            shouldSetAsDefault: shouldSetAsDefault,
                        ))))
                    }
                }

            default:
                return .none
            }
        }
    }
}
