// swiftlint:disable file_length cyclomatic_complexity function_body_length
import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

extension EntriesOperationsFeature {
    func reduceEntriesOperations(state: inout State, action: Action) -> Effect<Action> {
        logDAUEntryActionIfNeeded(action)
        switch action {
        case let .clearError(filePath):
            state.itemStates[filePath]?.lastError = nil
            return .none

        case let .operationStarted(filePath, _):
            state.itemStates[filePath] = ItemOperationState(isBusy: true, lastError: nil)
            return .none

        case let .operationFinished(filePath, kind, result):
            state.itemStates[filePath]?.isBusy = false
            switch result {
            case .success:
                state.itemStates[filePath]?.lastError = nil

                // 기본 앱 설정 성공 시 앱 목록 재로드
                if case .setDefaultApp = kind {
                    state.applicationsForItems[filePath] = nil
                    let url = URL(fileURLWithPath: filePath)
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let fileExtension = url.pathExtension
                    guard !isDirectory else { return .none }
                    let fileType = UTType(filenameExtension: fileExtension) ?? .data

                    return loadApplications(for: filePath, url: url, fileType: fileType)
                }
            case let .failure(error):
                state.itemStates[filePath]?.lastError = error

                if case .getInfo = kind {
                    return .run { _ in
                        await MainActor.run {
                            EntryAlertUtils.showGetInfoFailureAlert(
                                message: error.message,
                                suggestion: error.suggestion,
                            )
                        }
                    }
                }
            }
            return .none

        case .entryActionCompleted:
            return .none

        case let .openFiles(files):
            guard !files.isEmpty else {
                return .none
            }

            let entryClient = entryClient
            return .run { [entryClient] send in
                guard let firstFile = files.first else { return }
                let firstFilePath = firstFile.fullPath
                let isTrash = await MainActor.run {
                    guard let trashPath = entryClient.trashDirectoryPath(), !trashPath.isEmpty else {
                        return false
                    }
                    return firstFilePath.starts(with: trashPath + "/")
                }

                if isTrash {
                    for (index, file) in files.enumerated() {
                        let hasMoreFiles = index < files.count - 1
                        _ = await MainActor.run {
                            EntryAlertUtils.showTrashFileAlert(fileName: file.name, hasMoreFiles: hasMoreFiles)
                        }
                    }
                    return
                }

                var groupedFiles: [String: [(Entry, Int)]] = [:]
                for (index, file) in files.enumerated() {
                    let ext = file.fileExtension.lowercased()
                    groupedFiles[ext, default: []].append((file, index))
                }

                for (_, groupFiles) in groupedFiles {
                    let urls = groupFiles.map { URL(fileURLWithPath: $0.0.fullPath) }
                    guard let firstURL = urls.first else { continue }

                    let appURL = await Task { @MainActor in
                        let workspace = NSWorkspace.shared
                        return workspace.urlForApplication(toOpen: firstURL)
                    }.value
                    guard let appURL else {
                        for (file, _) in groupFiles {
                            let filePath = file.fullPath
                            let url = URL(fileURLWithPath: filePath)
                            await send(.operationStarted(filePath, .openDefault))
                            do {
                                try await entryClient.open(url, .defaultApp)
                                await send(.operationFinished(filePath, .openDefault, .success(())))
                            } catch {
                                await send(.operationFinished(filePath, .openDefault, .failure(error.fileOpError)))
                            }
                        }
                        continue
                    }

                    for (file, _) in groupFiles {
                        let filePath = file.fullPath
                        await send(.operationStarted(filePath, .openDefault))
                    }

                    do {
                        try await withScopedAccess(urls) {
                            try await Task { @MainActor in
                                let workspace = NSWorkspace.shared
                                let configuration = NSWorkspace.OpenConfiguration()
                                configuration.createsNewApplicationInstance = false
                                try await workspace.open(
                                    urls,
                                    withApplicationAt: appURL,
                                    configuration: configuration,
                                )
                            }.value
                        }
                        for (file, _) in groupFiles {
                            let filePath = file.fullPath
                            await send(
                                .operationFinished(filePath, .openDefault, .success(())),
                            )
                        }
                    } catch {
                        for (file, _) in groupFiles {
                            let filePath = file.fullPath
                            await send(.operationFinished(filePath, .openDefault, .failure(error.fileOpError)))
                        }
                    }
                }
            }

        case let .quickLookFile(file):
            let filePath = file.fullPath
            let url = URL(fileURLWithPath: filePath)
            return run(for: filePath, kind: .quickLook) {
                try await entryClient.quickLook(url)
            }

        case let .quickLookFiles(files):
            let urls = files.map { URL(fileURLWithPath: $0.fullPath) }
            let keyPath = files.first?.fullPath ?? "quicklook"
            return run(for: keyPath, kind: .quickLook) {
                try await entryClient.quickLookFiles(urls)
            }

        case let .openFinderInfo(items):
            let urls = items.map { URL(fileURLWithPath: $0.fullPath) }
            let keyPath = items.first?.fullPath ?? "getinfo"
            return run(for: keyPath, kind: .getInfo) {
                try await entryClient.openFinderInfo(urls)
            }

        case let .shareItems(items, anchor):
            let urls = items.map { URL(fileURLWithPath: $0.fullPath) }
            let keyPath = items.first?.fullPath ?? "share"
            return run(for: keyPath, kind: .share) {
                try await entryClient.shareItems(urls, anchor)
            }

        case let .performService(items, name):
            let urls = items.map { URL(fileURLWithPath: $0.fullPath) }
            let keyPath = items.first?.fullPath ?? "service"
            return run(for: keyPath, kind: .performService(name)) {
                try await entryClient.performService(name, urls)
            }

        case let .revealInFinder(items):
            let urls = items.map { URL(fileURLWithPath: $0.fullPath) }
            let keyPath = items.first?.fullPath ?? "reveal"
            return run(for: keyPath, kind: .revealInFinder) {
                try await entryClient.revealInFinder(urls)
            }

        case let .openFileWithApp(file):
            return selectApplicationAndOpenFile(for: file, defaultChecked: false, workspaceClient: workspaceClient)

        case let .openFileWithAppBundleID(filePath, bundleID, url):
            return .run { [entryClient] send in
                let isTrash = await MainActor.run {
                    guard let trashPath = entryClient.trashDirectoryPath(), !trashPath.isEmpty else {
                        return false
                    }
                    return filePath.starts(with: trashPath + "/")
                }
                if isTrash {
                    let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                    _ = await MainActor.run {
                        EntryAlertUtils.showTrashFileAlert(fileName: fileName, hasMoreFiles: false)
                    }
                    return
                }

                await send(.operationStarted(filePath, .openWithApp(bundleID)))
                do {
                    try await entryClient.open(url, .bundleID(bundleID))
                    await send(.operationFinished(filePath, .openWithApp(bundleID), .success(())))
                } catch {
                    await send(.operationFinished(
                        filePath,
                        .openWithApp(bundleID),
                        .failure(error.fileOpError),
                    ))
                }
            }

        case let .setDefaultAppForFile(type, bundleID, file):
            if let error = validateDefaultAppSetting(file: file) {
                state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                return .none
            }

            let resolvedType = type ?? UTType(filenameExtension: file.fileExtension)
            guard let fileType = resolvedType else {
                state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: .unsupportedType)
                return .none
            }
            let filePath = file.fullPath
            return run(for: filePath, kind: .setDefaultApp(bundleID)) {
                try await entryClient.setDefaultApp(fileType, bundleID)
            }

        case let .setDefaultAppWithOther(file):
            if let error = validateDefaultAppSetting(file: file) {
                state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                return .none
            }

            return selectApplicationAndOpenFile(for: file, defaultChecked: true, workspaceClient: workspaceClient)

        case let .openFilesWithAppFromOther(files, shouldSetAsDefault):
            for file in files {
                if let error = validateDefaultAppSetting(file: file) {
                    state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                    return .none
                }
            }

            return selectApplicationAndOpenFile(
                for: files,
                defaultChecked: shouldSetAsDefault,
                workspaceClient: workspaceClient,
            )

        case let .loadApplicationsForFile(file):
            guard !file.isDirectory else { return .none }
            let filePath = file.fullPath

            guard state.applicationsForItems[filePath] == nil else {
                return .none
            }

            let url = URL(fileURLWithPath: filePath)
            let fileType = UTType(filenameExtension: file.fileExtension) ?? .data

            return loadApplications(for: filePath, url: url, fileType: fileType)

        case let .applicationsLoaded(filePath, apps):
            state.applicationsForItems[filePath] = apps
            return .none

        case let .loadCommonApplicationsForFiles(files):
            return loadCommonApplications(for: files)

        case let .commonApplicationsLoaded(apps):
            state.commonApplicationsForSelectedFiles = apps
            return .none

        case let .createNewFolder(name, parentPath):
            let parentURL = URL(fileURLWithPath: parentPath)
            let targetPath = parentURL.appendingPathComponent(name).path

            return .run { send in
                await send(.operationStarted(targetPath, .createFolder))
                do {
                    try await entryClient.createFolder(parentURL, name)
                    await send(.operationFinished(targetPath, .createFolder, .success(())))
                    let record = EntryActionRecord(
                        actionKind: .createFolder,
                        targets: [.init(beforePath: nil, afterPath: targetPath)],
                    )
                    await send(.entryActionCompleted(record))
                } catch {
                    await send(.operationFinished(targetPath, .createFolder, .failure(error.fileOpError)))
                }
            }

        case let .createAliases(items):
            return .run { [entryClient] send in
                var targets: [EntryActionRecord.Target] = []

                for item in items {
                    let sourceURL = URL(fileURLWithPath: item.fullPath)
                    let parentURL = sourceURL.deletingLastPathComponent()
                    let baseName = sourceURL.lastPathComponent

                    var aliasName = "\(baseName) alias"
                    var aliasURL = parentURL.appendingPathComponent(aliasName)
                    var counter = 2

                    while entryClient.fileExists(aliasURL.path) {
                        aliasName = "\(baseName) alias \(counter)"
                        aliasURL = parentURL.appendingPathComponent(aliasName)
                        counter += 1
                    }

                    await send(.operationStarted(item.fullPath, .createAlias))
                    do {
                        try await entryClient.createAlias(sourceURL, aliasURL)
                        await send(.operationFinished(item.fullPath, .createAlias, .success(())))
                        targets.append(.init(beforePath: item.fullPath, afterPath: aliasURL.path))
                        entryClient.postFileSystemChanged([aliasURL.path])
                    } catch {
                        await send(.operationFinished(item.fullPath, .createAlias, .failure(error.fileOpError)))
                    }
                }

                guard !targets.isEmpty else { return }
                let record = EntryActionRecord(actionKind: .createAlias, targets: targets)
                await send(.entryActionCompleted(record))
            }

        case let .copySelectedItems(files):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            let urls = files.map { URL(fileURLWithPath: $0.fullPath) }
            pasteboard.writeObjects(urls as [NSURL])

            return .none

        case let .pasteItems(sourcePaths, destinationPath, operation, actionKind):
            let destinationURL = URL(fileURLWithPath: destinationPath)
            let destinations = avoidNameCollisions(
                sourcePaths: sourcePaths,
                destinationURL: destinationURL,
                operation: operation,
            )

            guard !destinations.isEmpty else {
                if operation == .cut {
                    return .run { send in
                        await send(.operationFinished(destinationPath, .pasteFile, .success(())))
                    }
                }
                return .none
            }

            let isCopy = operation == .copy

            return .run { [entryClient] send in
                var targets: [EntryActionRecord.Target] = []

                for (sourceURL, destURL) in destinations {
                    let sourcePath = sourceURL.path
                    let kind: OperationKind = .pasteFile

                    await send(.operationStarted(sourcePath, kind))

                    do {
                        if isCopy {
                            try await entryClient.pasteFile(sourceURL, destURL)
                        } else {
                            try await entryClient.moveFile(sourceURL, destURL)
                        }
                        targets.append(.init(beforePath: sourcePath, afterPath: destURL.path))
                        await send(.operationFinished(sourcePath, kind, .success(())))
                    } catch let error as FileOpError where error.isFileExists {
                        guard let itemName = error.itemName else {
                            await send(.operationFinished(sourcePath, kind, .failure(error)))
                            continue
                        }

                        let shouldReplace = await MainActor.run {
                            EntryAlertUtils.showReplaceAlert(itemName: itemName, context: .move) == .replace
                        }

                        if shouldReplace {
                            do {
                                try await entryClient.deleteImmediately(destURL)
                                if isCopy {
                                    try await entryClient.pasteFile(sourceURL, destURL)
                                } else {
                                    try await entryClient.moveFile(sourceURL, destURL)
                                }

                                let destinationFolder = destURL.deletingLastPathComponent().path
                                targets.append(.init(beforePath: sourcePath, afterPath: destURL.path))
                                await send(.operationFinished(destinationFolder, kind, .success(())))
                            } catch {
                                await send(.operationFinished(sourcePath, kind, .failure(error.fileOpError)))
                            }
                        } else {
                            await send(.operationFinished(sourcePath, kind, .failure(.cancelled)))
                        }
                    } catch {
                        await send(.operationFinished(sourcePath, kind, .failure(error.fileOpError)))
                    }
                }

                if !targets.isEmpty {
                    let record = EntryActionRecord(actionKind: actionKind, targets: targets)
                    await send(.entryActionCompleted(record))
                }
            }

        case let .renameItem(oldPath, newPath):
            let sourceURL = URL(fileURLWithPath: oldPath)
            let destURL = URL(fileURLWithPath: newPath)

            return .run { send in
                await send(.operationStarted(oldPath, .rename))
                do {
                    try await entryClient.renameFile(sourceURL, destURL)
                    await send(.operationFinished(oldPath, .rename, .success(())))
                    let record = EntryActionRecord(
                        actionKind: .rename,
                        targets: [.init(beforePath: oldPath, afterPath: newPath)],
                    )
                    await send(.entryActionCompleted(record))
                } catch let error as FileOpError where error.isFileExists {
                    guard let itemName = error.itemName else {
                        await send(.operationFinished(oldPath, .rename, .failure(error)))
                        return
                    }
                    await MainActor.run {
                        EntryAlertUtils.showRenameConflictAlert(itemName: itemName)
                    }
                    await send(.operationFinished(oldPath, .rename, .failure(error)))
                } catch {
                    await send(.operationFinished(oldPath, .rename, .failure(error.fileOpError)))
                }
            }

        case let .moveToTrash(items):
            return runParallelWithTargets(
                items: items,
                kind: .moveToTrash,
                actionKind: .moveToTrash,
            ) { url in
                let trashURL = try await entryClient.moveToTrashAndReturnURL(url)
                let result: NSURL? = trashURL as NSURL

                if let trashURL = result as URL? {
                    let metadata = TrashMetadata(
                        trashPath: trashURL.path,
                        originalPath: url.path,
                        deletedDate: Date(),
                    )
                    await TrashMetadataStore.shared.save(metadata)
                    return EntryActionRecord.Target(
                        beforePath: url.path,
                        afterPath: trashURL.path,
                    )
                }
                return nil
            }

        case let .deleteImmediately(items):
            return runParallel(items: items, kind: .deleteImmediately) { url in
                try await entryClient.deleteImmediately(url)
            }

        case let .emptyTrash(items):
            return runParallel(
                items: items,
                kind: .deleteImmediately,
                operation: { url in
                    try await entryClient.deleteImmediately(url)
                },
                onComplete: {
                    await TrashMetadataStore.shared.removeAll()
                },
            )

        case let .putBackFromTrash(items):
            return .run { [entryClient] send in
                var targets: [EntryActionRecord.Target] = []

                for item in items {
                    await send(.operationStarted(item.fullPath, .putBack))

                    guard let metadata = await TrashMetadataStore.shared.find(trashPath: item.fullPath)
                    else {
                        await send(.operationFinished(
                            item.fullPath,
                            .putBack,
                            .failure(.system(message: "Original path not found")),
                        ))
                        continue
                    }

                    let originalPath = metadata.originalPath

                    do {
                        try await entryClient.putBackFromTrash(
                            URL(fileURLWithPath: item.fullPath),
                            originalPath,
                        )
                        await send(.operationFinished(item.fullPath, .putBack, .success(())))
                        targets.append(.init(beforePath: item.fullPath, afterPath: originalPath))
                    } catch let error as FileOpError where error.isFileExists {
                        guard let itemName = error.itemName else {
                            await send(.operationFinished(item.fullPath, .putBack, .failure(error)))
                            continue
                        }

                        let shouldReplace = await MainActor.run {
                            EntryAlertUtils.showReplaceAlert(itemName: itemName, context: .putBack) == .replace
                        }

                        if shouldReplace {
                            do {
                                let originalURL = URL(fileURLWithPath: originalPath)
                                try await entryClient.deleteImmediately(originalURL)
                                try await entryClient.putBackFromTrash(
                                    URL(fileURLWithPath: item.fullPath),
                                    originalPath,
                                )
                                await send(.operationFinished(item.fullPath, .putBack, .success(())))
                                targets.append(.init(beforePath: item.fullPath, afterPath: originalPath))
                            } catch {
                                await send(.operationFinished(item.fullPath, .putBack, .failure(error.fileOpError)))
                            }
                        } else {
                            await send(.operationFinished(item.fullPath, .putBack, .failure(.cancelled)))
                        }
                    } catch {
                        await send(.operationFinished(item.fullPath, .putBack, .failure(error.fileOpError)))
                    }
                }

                if !targets.isEmpty {
                    let record = EntryActionRecord(actionKind: .putBack, targets: targets)
                    await send(.entryActionCompleted(record))
                }
            }

        case let .compressItems(items):
            let itemURLs = items.map { URL(fileURLWithPath: $0.fullPath) }
            guard let firstItem = items.first else { return .none }
            let parentPath = URL(fileURLWithPath: firstItem.fullPath).deletingLastPathComponent().path

            return .run { [entryClient] send in
                await send(.operationStarted(parentPath, .compress))

                do {
                    let archiveURL = try await entryClient.compressItems(itemURLs)
                    await send(.operationFinished(parentPath, .compress, .success(())))
                    entryClient.postFileSystemChanged([archiveURL.path])
                } catch {
                    await send(.operationFinished(parentPath, .compress, .failure(error.fileOpError)))
                }
            }

        case let .extractCompressedFile(file):
            let zipURL = URL(fileURLWithPath: file.fullPath)
            let parentPath = zipURL.deletingLastPathComponent().path

            return .run { [entryClient] send in
                await send(.operationStarted(parentPath, .extract))

                do {
                    try await entryClient.extractCompressedFile(zipURL)
                    await send(.operationFinished(parentPath, .extract, .success(())))
                    entryClient.postFileSystemChanged([parentPath])
                } catch {
                    await send(.operationFinished(parentPath, .extract, .failure(error.fileOpError)))
                }
            }

        case let .setTagsForItems(targets):
            return .run { [entryClient] send in
                var completedTargets: [EntryActionRecord.Target] = []

                for target in targets {
                    let filePath = target.file.fullPath
                    let url = URL(fileURLWithPath: filePath)

                    await send(.operationStarted(filePath, .setTags))
                    do {
                        try await entryClient.setTags(url, target.afterTags)
                        await send(.operationFinished(filePath, .setTags, .success(())))
                        completedTargets.append(EntryActionRecord.Target(
                            beforePath: filePath,
                            afterPath: filePath,
                            beforeTags: target.beforeTags,
                            afterTags: target.afterTags,
                        ))
                    } catch {
                        await send(.operationFinished(filePath, .setTags, .failure(error.fileOpError)))
                    }
                }

                guard !completedTargets.isEmpty else { return }
                let record = EntryActionRecord(actionKind: .setTags, targets: completedTargets)
                await send(.entryActionCompleted(record))
            }
        }
    }
}

// swiftlint:enable file_length cyclomatic_complexity function_body_length
