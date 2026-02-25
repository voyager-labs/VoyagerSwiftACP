import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

enum EntryOperationsExecutionSupport {
    static func avoidNameCollisions(
        sourcePaths: [String],
        destinationURL: URL,
        operation: ClipboardOperation,
        entryFileOpsClient: EntryFileOpsClient,
    ) -> [(URL, URL)] {
        var destinations: [(URL, URL)] = []

        for sourcePath in sourcePaths {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let fileName = sourceURL.lastPathComponent
            let sourceParent = sourceURL.deletingLastPathComponent()

            var destURL = destinationURL.appendingPathComponent(fileName)

            if operation == .copy, sourceParent == destinationURL {
                let nameWithoutExtension = URL(fileURLWithPath: fileName)
                    .deletingPathExtension()
                    .lastPathComponent
                let fileExtension = URL(fileURLWithPath: fileName).pathExtension
                var counter = 1

                while entryFileOpsClient.fileExists(destURL.path) {
                    let name: String = if counter == 1 {
                        fileExtension.isEmpty
                            ? "\(nameWithoutExtension) copy"
                            : "\(nameWithoutExtension) copy.\(fileExtension)"
                    } else {
                        fileExtension.isEmpty
                            ? "\(nameWithoutExtension) copy \(counter)"
                            : "\(nameWithoutExtension) copy \(counter).\(fileExtension)"
                    }
                    destURL = destinationURL.appendingPathComponent(name)
                    counter += 1
                }
            }

            if operation == .cut, sourceParent == destinationURL {
                continue
            }

            destinations.append((sourceURL, destURL))
        }

        return destinations
    }

    static func validateDefaultAppSetting(file: EntryModel, capabilities: EntryCapabilities) -> FileOpError? {
        guard !file.isFolder else {
            return .unsupportedType
        }
        guard capabilities.supportsDefaultAppManagement else {
            return .system(
                message: "Setting default apps is not supported yet.",
                suggestion: "Enable default-app capability before using this action.",
            )
        }
        return nil
    }

    static func run(
        for filePath: String,
        kind: OperationKind,
        operation: @escaping @Sendable () async throws -> Void,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            await send(.operationStarted(filePath, kind))
            do {
                try await operation()
                await send(.operationFinished(filePath, kind, .success(())))
            } catch {
                await send(.operationFinished(filePath, kind, .failure(error.fileOpError)))
            }
        }
    }

    static func runParallel(
        items: [EntryModel],
        kind: OperationKind,
        operation: @escaping @Sendable (URL) async throws -> Void,
        onComplete: (@Sendable () async -> Void)? = nil,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            await withTaskGroup(of: Void.self) { group in
                for item in items {
                    group.addTask {
                        await send(.operationStarted(item.fullPath, kind))

                        do {
                            let url = URL(fileURLWithPath: item.fullPath)
                            try await operation(url)
                            await send(.operationFinished(item.fullPath, kind, .success(())))
                        } catch {
                            await send(.operationFinished(
                                item.fullPath,
                                kind,
                                .failure(error.fileOpError),
                            ))
                        }
                    }
                }
            }

            await onComplete?()
        }
    }

    static func runParallelWithTargets(
        items: [EntryModel],
        kind: OperationKind,
        actionKind: EntryActionRecord.ActionKind,
        operation: @escaping @Sendable (URL) async throws -> EntryActionRecord.Target?,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            let accumulator = EntryActionTargetAccumulator()

            await withTaskGroup(of: Void.self) { group in
                for item in items {
                    group.addTask {
                        await send(.operationStarted(item.fullPath, kind))

                        do {
                            let url = URL(fileURLWithPath: item.fullPath)
                            let target = try await operation(url)
                            if let target {
                                await accumulator.append(target)
                            }
                            await send(.operationFinished(item.fullPath, kind, .success(())))
                        } catch {
                            await send(.operationFinished(
                                item.fullPath,
                                kind,
                                .failure(error.fileOpError),
                            ))
                        }
                    }
                }
            }

            let targets = await accumulator.targets
            guard !targets.isEmpty else { return }
            let record = EntryActionRecord(actionKind: actionKind, targets: targets)
            await send(.entryActionCompleted(record))
        }
    }

    static func loadApplications(
        for filePath: String,
        url: URL,
        fileType: UTType,
        entryOpenClient: EntryOpenClient,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            let apps = await entryOpenClient.applicationsForFile(url)
            let defaultApp = await entryOpenClient.defaultApplication(fileType)

            let appsWithDefaultFlag = apps.map { app in
                let isDefault = defaultApp?.bundleID == app.bundleID
                return ApplicationInfo(
                    id: app.id,
                    name: app.name,
                    bundleID: app.bundleID,
                    isDefault: isDefault,
                )
            }

            let finalApps = await MainActor.run {
                finalizeApplicationList(appsWithDefaultFlag)
            }
            await send(.applicationsLoaded(filePath, finalApps))
        }
    }

    static func loadCommonApplications(
        for files: [EntryModel],
        entryOpenClient: EntryOpenClient,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            let commonApps = await computeCommonApplications(files: files, entryOpenClient: entryOpenClient)
            let finalApps = await MainActor.run {
                finalizeApplicationList(commonApps)
            }
            await send(.commonApplicationsLoaded(finalApps))
        }
    }

    static func computeCommonApplications(
        files: [EntryModel],
        entryOpenClient: EntryOpenClient,
    ) async -> [ApplicationInfo] {
        let fileInfos = prepareFileInfos(from: files)
        guard !fileInfos.isEmpty else { return [] }

        let allAppMaps = await collectApplicationMaps(fileInfos: fileInfos, entryOpenClient: entryOpenClient)
        guard !allAppMaps.isEmpty else { return [] }

        let commonBundleIDs = findCommonBundleIDs(from: allAppMaps)
        let fileTypeToDefaultApp = await loadDefaultApps(fileInfos: fileInfos, entryOpenClient: entryOpenClient)
        return buildCommonApps(
            bundleIDs: commonBundleIDs,
            appMaps: allAppMaps,
            fileInfos: fileInfos,
            fileTypeToDefaultApp: fileTypeToDefaultApp,
        )
    }

    private struct FileInfo {
        let file: EntryModel
        let fileType: UTType
        let url: URL
    }

    private actor EntryActionTargetAccumulator {
        private var storage: [EntryActionRecord.Target] = []

        func append(_ target: EntryActionRecord.Target) {
            storage.append(target)
        }

        var targets: [EntryActionRecord.Target] {
            storage
        }
    }

    private static func prepareFileInfos(from files: [EntryModel]) -> [FileInfo] {
        files.compactMap { file in
            guard !file.isFolder,
                  let fileType = UTType(filenameExtension: file.fileExtension)
            else { return nil }
            return FileInfo(file: file, fileType: fileType, url: URL(fileURLWithPath: file.fullPath))
        }
    }

    private static func collectApplicationMaps(
        fileInfos: [FileInfo],
        entryOpenClient: EntryOpenClient,
    ) async -> [[String: ApplicationInfo]] {
        var allAppMaps: [[String: ApplicationInfo]] = []
        await withTaskGroup(of: [String: ApplicationInfo]?.self) { group in
            for fileInfo in fileInfos {
                group.addTask {
                    let apps = await entryOpenClient.applicationsForFile(fileInfo.url)
                    var appMap: [String: ApplicationInfo] = [:]
                    for app in apps {
                        if let bundleID = app.bundleID {
                            appMap[bundleID] = app
                        }
                    }
                    return appMap
                }
            }

            for await appMap in group {
                if let appMap {
                    allAppMaps.append(appMap)
                }
            }
        }
        return allAppMaps
    }

    private static func findCommonBundleIDs(from allAppMaps: [[String: ApplicationInfo]]) -> Set<String> {
        guard let firstMap = allAppMaps.first else { return [] }
        var commonBundleIDs = Set(firstMap.keys)
        for appMap in allAppMaps.dropFirst() {
            commonBundleIDs = commonBundleIDs.intersection(Set(appMap.keys))
        }
        return commonBundleIDs
    }

    private static func loadDefaultApps(
        fileInfos: [FileInfo],
        entryOpenClient: EntryOpenClient,
    ) async -> [String: String] {
        var fileTypeToDefaultApp: [String: String] = [:]
        await withTaskGroup(of: (String, String?)?.self) { group in
            for fileInfo in fileInfos {
                group.addTask {
                    let defaultApp = await entryOpenClient.defaultApplication(fileInfo.fileType)
                    return (fileInfo.fileType.identifier, defaultApp?.bundleID)
                }
            }

            for await result in group {
                if let (typeID, bundleID) = result, let bundleID {
                    fileTypeToDefaultApp[typeID] = bundleID
                }
            }
        }
        return fileTypeToDefaultApp
    }

    private static func buildCommonApps(
        bundleIDs: Set<String>,
        appMaps: [[String: ApplicationInfo]],
        fileInfos: [FileInfo],
        fileTypeToDefaultApp: [String: String],
    ) -> [ApplicationInfo] {
        var commonApps: [ApplicationInfo] = []
        guard let firstAppMap = appMaps.first else { return [] }

        for bundleID in bundleIDs {
            guard let app = firstAppMap[bundleID] else { continue }

            let isDefault = fileInfos.allSatisfy { fileInfo in
                fileTypeToDefaultApp[fileInfo.fileType.identifier] == bundleID
            }

            commonApps.append(ApplicationInfo(
                id: app.id,
                name: app.name,
                bundleID: app.bundleID,
                isDefault: isDefault,
            ))
        }
        return commonApps
    }
}

private func finalizeApplicationList(_ apps: [ApplicationInfo]) -> [ApplicationInfo] {
    var result = apps
    result.append(ApplicationInfo(
        id: "other",
        name: "Other…",
        bundleID: nil,
        isDefault: false,
    ))
    result.sort { lhs, rhs in
        if lhs.isDefault != rhs.isDefault {
            return lhs.isDefault
        }
        return lhs.name < rhs.name
    }
    return result
}

extension Error {
    var fileOpError: FileOpError {
        if let error = self as? FileOpError { return error }
        if let nsError = self as NSError?, nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return .notFound
            case NSUserCancelledError:
                return .cancelled
            default:
                return .system(message: nsError.localizedDescription)
            }
        }
        return .system(message: localizedDescription)
    }
}
