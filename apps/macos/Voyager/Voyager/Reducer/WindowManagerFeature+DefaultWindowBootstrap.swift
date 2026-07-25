import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerShared

enum DefaultWindowBootstrap {
    struct Dependencies {
        let builtInClient: FileManagerBuiltInCollectionClient
        let pinnedRecordClient: ContentTabPinnedRecordClient
        let favoritesClient: FileManagerFavoritesClient
        let managerClient: FileManagerClient
        let loadingClient: EntryLoadingClient
        let defaultsClient: UserDefaultsClient
        let metricsClient: MetricsClient
        let now: @Sendable () -> Date
    }

    struct RestoreResult {
        let state: ContentTabState
        let didCompact: Bool
    }

    static func run(_ dependencies: Dependencies) async -> ContentTabState? {
        guard !Task.isCancelled else { return nil }
        let initialStore = (try? dependencies.pinnedRecordClient.loadStore(dependencies.defaultsClient))
            ?? ContentTabPinnedRecordStore()
        if !dependencies.defaultsClient.bool(SettingsKeys.defaultPinnedTabsSeedCompleted) {
            dependencies.defaultsClient.setBool(true, SettingsKeys.defaultPinnedTabsSeedCompleted)
        }
        seedFinderFavoritesIfNeeded(initialStore: initialStore, dependencies: dependencies)
        guard !Task.isCancelled else { return nil }
        let ensureReport = await dependencies.builtInClient.ensureAll()
        guard !Task.isCancelled else { return nil }
        dependencies.metricsClient.logMetric("built_in_pinned_seed_started", 1, nil)
        seedBuiltInCollectionIfNeeded(
            identity: .recents,
            ensureResult: ensureReport.recents,
            completionKey: SettingsKeys.recentsPinnedSeedCompleted,
            dependencies: dependencies,
        )
        guard !Task.isCancelled else { return nil }
        seedBuiltInCollectionIfNeeded(
            identity: .allTags,
            ensureResult: ensureReport.allTags,
            completionKey: SettingsKeys.allTagsPinnedSeedCompleted,
            dependencies: dependencies,
        )
        guard !Task.isCancelled else { return nil }
        let reloadedStore = (try? dependencies.pinnedRecordClient.loadStore(dependencies.defaultsClient))
            ?? ContentTabPinnedRecordStore()
        let restoreResult = restorePinnedRecords(from: reloadedStore, dependencies: dependencies)
        return compactIfNeeded(restoreResult, dependencies: dependencies)
    }

    private static func seedFinderFavoritesIfNeeded(
        initialStore: ContentTabPinnedRecordStore,
        dependencies: Dependencies,
    ) {
        guard !dependencies.defaultsClient.bool(SettingsKeys.finderFavoritesPinnedSeedCompleted) else { return }
        let applicationSupportURL = dependencies.managerClient.urlsForDirectory(
            .applicationSupportDirectory,
            .userDomainMask,
        ).first
        guard nonBuiltInRecords(
            in: initialStore,
            applicationSupportURL: applicationSupportURL,
        ).isEmpty else {
            dependencies.defaultsClient.setBool(true, SettingsKeys.finderFavoritesPinnedSeedCompleted)
            return
        }
        let favorites = dependencies.favoritesClient.loadFavorites(
            dependencies.loadingClient,
            dependencies.defaultsClient,
        )
        let mappedRecords = uniqueRecordsByID(FileManagerFavoritesPinnedRecordMapper.pinnedRecords(
            from: favorites,
            pinnedAt: dependencies.now(),
            fileExistsWithIsDirectory: { path, isDirectory in
                dependencies.managerClient.fileExistsWithIsDirectory(path, isDirectory)
            },
        ))
        do {
            _ = try dependencies.pinnedRecordClient.updateStoreAndLoad(
                dependencies.defaultsClient,
            ) { latestStore in
                try Task.checkCancellation()
                guard nonBuiltInRecords(
                    in: latestStore,
                    applicationSupportURL: applicationSupportURL,
                ).isEmpty else {
                    return latestStore
                }

                return mergingFinderRecords(
                    mappedRecords,
                    into: latestStore,
                    applicationSupportURL: applicationSupportURL,
                )
            }
            guard !Task.isCancelled else { return }
            dependencies.defaultsClient.setBool(true, SettingsKeys.finderFavoritesPinnedSeedCompleted)
        } catch {
            // Finder 저장 실패 시 완료 플래그를 남기지 않아 다음 부트스트랩에서 재시도한다.
        }
    }

    private static func seedBuiltInCollectionIfNeeded(
        identity: BuiltInCollectionIdentity,
        ensureResult: BuiltInCollectionEnsureItemResult,
        completionKey: String,
        dependencies: Dependencies,
    ) {
        guard !Task.isCancelled else { return }
        if dependencies.defaultsClient.bool(completionKey) {
            logSeedMetric("built_in_pinned_item_suppressed", identity: identity, dependencies: dependencies)
            return
        }
        let descriptor: BuiltInCollectionDescriptor
        switch ensureResult {
        case let .ready(value): descriptor = value
        case .deferred:
            logSeedMetric("built_in_pinned_item_deferred", identity: identity, dependencies: dependencies)
            return
        case .failed:
            logSeedMetric("built_in_pinned_item_failed", identity: identity, dependencies: dependencies)
            return
        }
        let policyDescriptor = BuiltInContentTabPinnedRecordSeedPolicy.VerifiedDescriptor(
            identity: descriptor.identity,
            canonicalPackageURL: descriptor.packageURL,
        )
        do {
            let finalStore = try dependencies.pinnedRecordClient.updateStoreAndLoad(
                dependencies.defaultsClient,
            ) { latestStore in
                try Task.checkCancellation()
                let result = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
                    ensureResult: .ready(policyDescriptor),
                    completion: false,
                    store: latestStore,
                    now: dependencies.now(),
                )
                return switch result {
                case let .seed(store), let .alreadyPresent(store):
                    store
                case .suppressed, .deferred, .failed:
                    latestStore
                }
            }
            guard BuiltInContentTabPinnedRecordSeedPolicy.containsCanonicalRecord(
                in: finalStore,
                descriptor: policyDescriptor,
            ) else {
                logSeedMetric("built_in_pinned_item_deferred", identity: identity, dependencies: dependencies)
                return
            }
            guard !Task.isCancelled else { return }
            dependencies.defaultsClient.setBool(true, completionKey)
            logSeedMetric("built_in_pinned_item_seeded", identity: identity, dependencies: dependencies)
        } catch {
            logSeedMetric("built_in_pinned_item_failed", identity: identity, dependencies: dependencies)
            // 항목별 저장 실패는 완료 플래그를 남기지 않아 독립적으로 재시도한다.
        }
    }

    private static func logSeedMetric(
        _ name: String,
        identity: BuiltInCollectionIdentity,
        dependencies: Dependencies,
    ) {
        let outcome = name.replacingOccurrences(of: "built_in_pinned_item_", with: "")
        dependencies.metricsClient.logMetric(
            name,
            1,
            ["identity": identity.rawValue, "outcome": outcome],
        )
    }

    private static func compactIfNeeded(
        _ restoreResult: RestoreResult,
        dependencies: Dependencies,
    ) -> ContentTabState {
        guard restoreResult.didCompact else { return restoreResult.state }

        do {
            let compactedStore = try dependencies.pinnedRecordClient.updateStoreAndLoad(
                dependencies.defaultsClient,
            ) { latestStore in
                try Task.checkCancellation()
                let latestRestoreResult = restorePinnedRecords(
                    from: latestStore,
                    dependencies: dependencies,
                )
                guard latestRestoreResult.didCompact else { return latestStore }

                return ContentTabPinnedRecordStore(
                    schemaVersion: latestStore.schemaVersion,
                    records: latestRestoreResult.state.tabs.compactMap { tab in
                        latestRestoreResult.state.pinnedRecords[tab.id]
                    },
                )
            }
            return restorePinnedRecords(from: compactedStore, dependencies: dependencies).state
        } catch {
            return restoreResult.state
        }
    }

    nonisolated private static func mergingFinderRecords(
        _ records: [ContentTabPinnedRecord],
        into store: ContentTabPinnedRecordStore,
        applicationSupportURL: URL?,
    ) -> ContentTabPinnedRecordStore {
        let recentsResidue = BuiltInContentTabPinnedRecordSeedPolicy.records(
            classifiedAs: .recents,
            in: store,
            applicationSupportURL: applicationSupportURL,
        )
        let allTagsResidue = BuiltInContentTabPinnedRecordSeedPolicy.records(
            classifiedAs: .allTags,
            in: store,
            applicationSupportURL: applicationSupportURL,
        )
        return ContentTabPinnedRecordStore(
            schemaVersion: store.schemaVersion,
            records: recentsResidue + records + allTagsResidue,
        )
    }

    nonisolated private static func nonBuiltInRecords(
        in store: ContentTabPinnedRecordStore,
        applicationSupportURL: URL?,
    ) -> [ContentTabPinnedRecord] {
        store.records.filter {
            BuiltInContentTabPinnedRecordSeedPolicy.classify(
                $0,
                applicationSupportURL: applicationSupportURL,
            ) == nil
        }
    }

    private static func uniqueRecordsByID(
        _ records: [ContentTabPinnedRecord],
    ) -> [ContentTabPinnedRecord] {
        var seenIDs = Set<String>()
        return records.filter { seenIDs.insert($0.id).inserted }
    }

    nonisolated private static func restorePinnedRecords(
        from store: ContentTabPinnedRecordStore,
        dependencies: Dependencies,
    ) -> RestoreResult {
        let result = ContentTabState.restoringPinnedRecords(
            from: store,
            isRestorableAnchor: { anchor in
                switch anchor {
                case let .directory(path):
                    var isDirectory = ObjCBool(false)
                    return dependencies.managerClient.fileExistsWithIsDirectory(path, &isDirectory)
                        && isDirectory.boolValue
                case let .collectionFile(url):
                    return dependencies.managerClient.fileExistsWithIsDirectory(url.path, nil)
                case .homeDefault, .virtualCollection, .aiChat:
                    return true
                }
            },
        )
        return RestoreResult(state: result.state, didCompact: result.didCompact)
    }
}
